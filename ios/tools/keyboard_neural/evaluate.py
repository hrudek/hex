#!/usr/bin/env python3
"""Offline bounded neural spike. Run with python -I, BLAS threads=1.
Only trusted repository Python is loaded; all corpora/weights are data.
"""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import runpy
import sqlite3
import struct
import time


def events(sentence):
    a, b = '<s>', '<s>'
    for w in sentence:
        if w is None:
            a, b = '<s>', '<s>'
            continue
        import unicodedata
        w = unicodedata.normalize('NFC', w.lower())
        yield a, b, w
        a, b = b, w


def inspect_hxn(path):
    """Validate the copied HXN1 layout without importing any upstream code."""
    if path.stat().st_size > 12000000:
        raise ValueError('HXN1 exceeds inspection byte cap')
    raw = path.read_bytes()
    if len(raw) < 20 or raw[:4] != b'HXN1':
        raise ValueError('invalid HXN1')
    v, e, h, s = struct.unpack_from('<4I', raw, 4)
    if not (4 <= v <= 30000 and 1 <= e <= 256 and 1 <= h <= 2048 and s <= 4000000):
        raise ValueError('dimensions exceed inspection caps')
    matrix = (20 + 8*v + s + 3)//4*4 + 4*(2*v + 12*h + 2*e)
    expected = matrix + v*e + 4*h*(e+h) + e*h
    if len(raw) != expected:
        raise ValueError('invalid HXN1 extent')
    mac_step = 4*h*(e+h)
    return dict(bytes=len(raw), sha256=hashlib.sha256(raw).hexdigest(), vocabulary=v,
                embedding=e, hidden=h, mac_step=mac_step,
                mac_cold16=16*mac_step+e*h+v*e,
                float_workspace_lower_bound=4*(6*h+2*e+2*v),
                note='Workspace lower bound excludes cached states, tokens, allocator and framework.')


def hxn_predictor(path, np):
    """Independent NumPy interpretation of inspected format, never upstream Python."""
    inspect_hxn(path)
    raw = path.read_bytes()
    v,e,h,s = struct.unpack_from('<4I',raw,4)
    spell = 20+4*v
    offsets = struct.unpack_from('<'+str(v)+'I',raw,20)
    words = [raw[spell+o:raw.index(b'\0',spell+o)].decode('utf-8') for o in offsets]
    ids = {w:i for i,w in enumerate(words)}
    at = (20+8*v+s+3)//4*4
    scales = np.frombuffer(raw,dtype='<f4',count=v+8*h+e,offset=at)
    at += scales.nbytes
    bias = np.frombuffer(raw,dtype='<f4',count=4*h+e+v,offset=at)
    at += bias.nbytes
    matrices = []
    si = 0
    for rows,cols in ((v,e),(4*h,e),(4*h,h),(e,h)):
        q = np.frombuffer(raw,dtype='int8',count=rows*cols,offset=at).reshape(rows,cols)
        matrices.append(q.astype('float32')*scales[si:si+rows,None])
        at += q.nbytes; si += rows
    emb,wi,wh,proj = matrices
    def predict(prefix):
        hidden = np.zeros(h,dtype='float32'); cell = hidden.copy()
        for word in prefix[-16:]:
            gates = wi@emb[ids.get(word,1)] + wh@hidden + bias[:4*h]
            sig = lambda x: 1/(1+np.exp(-np.clip(x,-80,80)))
            cell = sig(gates[h:2*h])*cell + sig(gates[:h])*np.tanh(gates[2*h:3*h])
            hidden = sig(gates[3*h:])*np.tanh(cell)
        logits = emb@(proj@hidden+bias[4*h:4*h+e])+bias[4*h+e:]
        return [words[j] for j in np.argsort(-logits,kind='stable') if j>=4][:3]
    return predict


def quantize(x, np):
    scale = np.maximum(np.max(np.abs(x), axis=1), 1e-8)/127
    q = np.rint(x/scale[:, None]).clip(-127, 127).astype('int8')
    return q, scale.astype('<f4')


def write_model(path, matrices, biases, np):
    v, e = matrices[0].shape
    h = matrices[1].shape[0]
    data = bytearray(struct.pack('<4sIII', b'TNN1', v, e, h))
    decoded = []
    for x in matrices:
        q, s = quantize(x, np)
        data.extend(s.tobytes()); data.extend(q.tobytes())
        decoded.append(q.astype('float32')*s[:, None])
    for b in biases:
        data.extend(b.astype('<f4').tobytes())
    path.write_bytes(data)
    return decoded, dict(bytes=len(data), sha256=hashlib.sha256(data).hexdigest(),
                         macs=2*e*h+v*h, float_workspace_bytes=4*(2*e+h+v))


def forward(ids, matrices, biases, np):
    emb, hidden, output = matrices
    x = np.concatenate((emb[ids[:, 0]], emb[ids[:, 1]]), axis=1)
    z = np.maximum(x@hidden.T+biases[0], 0)
    return z@output.T+biases[1]


def personal_top3(base, row):
    """Exact top3 under production personal backoff; corpus rank is uniformly scaled."""
    n,t = sum(row.values()),len(row)
    def score(w):
        c = base.get(w,0)
        return (max(row.get(w,0)-.5,0)+1.5*t*c)/(n+t) if t else c
    before = sorted(base, key=lambda w:(-base[w],w.encode()))[:3]
    eligible = {w for w,c in row.items() if w in base or c >= 2}
    return sorted(set(before)|eligible, key=lambda w:(-score(w),w.encode()))[:3]


def load_sentences(db_path, lang, part, limit):
    db = sqlite3.connect(f'file:{db_path.resolve()}?mode=ro', uri=True)
    try:
        # Dedup across sources. Existing digest split never changes.
        rows = db.execute('SELECT tokens FROM sentences WHERE lang=? AND part=? GROUP BY digest ORDER BY digest LIMIT ?', (lang, part, limit))
        return [json.loads(row[0]) for row in rows]
    finally:
        db.close()


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('database', type=Path)
    p.add_argument('word_data', type=Path)
    p.add_argument('output', type=Path)
    p.add_argument('--hxn', type=Path)
    args = p.parse_args()
    import numpy as np
    start = time.monotonic()
    args.output.mkdir(parents=True, exist_ok=True)
    api = runpy.run_path(str(Path(__file__).resolve().parents[1]/'keyboard_context/tools/build_bigrams.py'))
    train = {l: load_sentences(args.database, l, 'train', 6000) for l in ('de', 'en')}
    triples = [t for l in train for s in train[l] for t in events(s)][:160000]
    counts = Counter(w for t in triples for w in t if w != '<s>')
    vocab = ['<unk>', '<s>'] + sorted(counts, key=lambda w: (-counts[w], w.encode()))[:2046]
    ids = {w: i for i, w in enumerate(vocab)}
    data = np.array([[ids.get(w, 0) for w in t] for t in triples], dtype='int32')
    rng = np.random.default_rng(210)
    v, e, h = len(vocab), 16, 32
    emb = rng.normal(0, .1, (v,e)).astype('float32')
    hidden = rng.normal(0, .1, (h,2*e)).astype('float32')
    output = rng.normal(0, .02, (v,h)).astype('float32')
    hb = np.zeros(h, dtype='float32')
    ob = np.log(np.bincount(data[:,2], minlength=v)+1).astype('float32')
    ob -= ob.mean()
    # Fixed updates, fixed seed, single-thread BLAS. No time-dependent stopping.
    for step in range(1200):
        batch = data[rng.integers(len(data), size=128)]
        x = np.concatenate((emb[batch[:,0]], emb[batch[:,1]]), axis=1)
        z = np.maximum(x@hidden.T+hb, 0)
        logits = z@output.T+ob
        prob = np.exp(logits-logits.max(axis=1, keepdims=True))
        prob /= prob.sum(axis=1, keepdims=True)
        prob[np.arange(len(batch)), batch[:,2]] -= 1
        prob /= len(batch)
        dz = (prob@output)*(z>0)
        dx = dz@hidden
        rate = .4
        output -= rate*(prob.T@z); ob -= rate*prob.sum(axis=0)
        hidden -= rate*(dz.T@x); hb -= rate*dz.sum(axis=0)
        np.add.at(emb, batch[:,0], -rate*dx[:,:e])
        np.add.at(emb, batch[:,1], -rate*dx[:,e:])
    matrices, model_info = write_model(args.output/'tiny.tnn', [emb,hidden,output], [hb,ob], np)
    (args.output/'vocab.json').write_text(json.dumps(vocab, ensure_ascii=False))
    packs = [api['Model']((args.word_data/f'keyboard-{l}.tbg').read_bytes()) for l in ('de','en')]
    union = sorted(set(packs[0].vocab[1:]) | set(packs[1].vocab[1:]))
    # Controlled neutral bilingual posterior. No hidden tuning on held-out targets.
    def corpus(b):
        return {w: .5*packs[0].prob(b,w)+.5*packs[1].prob(b,w) for w in union}
    # Small synthetic trusted profile from TRAIN only, no held-out learning.
    rows = {}
    for a,b,w in triples[:100]:
        if all(x.isalpha() and len(x)<=32 for x in (a,b,w)):
            for key in (b,a+' '+b):
                row = rows.setdefault(key, Counter())
                row[w] += 1
    if sum(map(len, rows.values())) > 512 or any(len(r) > 8 for r in rows.values()):
        raise ValueError('synthetic profile exceeds production edge/follower limits')
    (args.output/'profile.json').write_text(json.dumps({k:dict(v) for k,v in rows.items()},ensure_ascii=False))
    fixture = json.loads((args.word_data/'context-heldout-r2.json').read_text())['sentences']
    sets = {l: [s for key, ss in fixture.items() if key.startswith(l+'_') for s in ss] for l in ('de','en')}
    sets['mixed'] = [d[:len(d)//2]+en[len(en)//2:] for d,en in zip(sets['de'],sets['en'])]
    results = {}
    upstream = hxn_predictor(args.hxn, np) if args.hxn else None
    upstream_results = {}
    vectors = []
    for language, sentences in sets.items():
        ev = [t for s in sentences for t in events(s)]
        inputs = np.array([[ids.get(a,0),ids.get(b,0)] for a,b,w in ev], dtype='int32')
        logits = forward(inputs, matrices, [hb,ob], np)
        metrics = {k: [0,0] for k in ('corpus','personal','neural','rerank','personal_rerank')}
        cache = {}
        for i,(a,b,target) in enumerate(ev):
            if b not in cache:
                if len(cache) >= 32: cache.clear()
                cache[b] = corpus(b)
            base = cache[b]
            row = rows.get(a+' '+b, rows.get(b, {}))
            before = sorted(base, key=lambda w:(-base[w],w.encode()))[:3]
            learned = personal_top3(base, row)
            # Most conservative rerank: only the three existing words; no new candidates.
            def rerank(pool):
                return sorted(pool, key=lambda w:(-float(logits[i,ids[w]]) if w in ids else float('inf'),w.encode()))
            top = [vocab[j] for j in np.argsort(-logits[i], kind='stable') if j>1][:3]
            for k,pred in zip(metrics,(before,learned,top,rerank(before),rerank(learned))):
                metrics[k][0] += bool(pred and target==pred[0]); metrics[k][1] += target in pred[:3]
            if i < 2:
                vectors.append(dict(inputs=inputs[i].tolist(), logits=logits[i].tolist()))
        if upstream:
            hits = [0,0]; control = [0,0]; prefix = ['<s>']; sampled = 0
            for sentence in sentences:
                prefix = ['<s>']
                for a,b,target in events(sentence):
                    if sampled == 32: break
                    pred = upstream(prefix)
                    base_pred = [w for w,_ in api['mixture_suggest'](*packs,b)]
                    for acc, guesses in ((hits,pred),(control,base_pred)):
                        acc[0] += target == guesses[0]; acc[1] += target in guesses
                    prefix.append(target); sampled += 1
                if sampled == 32: break
            upstream_results[language] = dict(events=sampled, corpus=control, iikb=hits)
            print('EVAL R2_10_iikb_subset',language,json.dumps(upstream_results[language]),flush=True)
        results[language] = dict(events=len(ev), **{k:dict(recall1=a/len(ev),recall3=b/len(ev)) for k,(a,b) in metrics.items()})
        print('EVAL R2_10_quality',language,json.dumps(results[language]),flush=True)
    (args.output/'vectors.json').write_text(json.dumps(vectors))
    # Simple numeric stream lets standalone Swift verify every output, without JSON model decoding.
    with (args.output/'parity.txt').open('w') as f:
        for vector in vectors:
            f.write(' '.join(map(str,vector['inputs']+vector['logits']))+'\n')
    input_paths = [args.database, args.word_data/'context-heldout-r2.json']
    input_paths += [args.word_data/f'keyboard-{l}.tbg' for l in ('de','en')]
    inputs = {str(p): hashlib.file_digest(p.open('rb'),'sha256').hexdigest() for p in input_paths}
    summary = dict(inputs=inputs, model=model_info, results=results, train_events=len(data), updates=1200,
                   numpy=np.__version__, seconds=time.monotonic()-start,
                   profile_rows=len(rows), profile_edges=sum(map(len,rows.values())),
                   gate='DE and EN recall3 gain >= .02; mixed no regression; wide device memory margin',
                   decision='evaluation only; conservative top3 rerank cannot increase recall3')
    if args.hxn:
        summary['iikb'] = inspect_hxn(args.hxn)
        summary['iikb_subset'] = upstream_results
    (args.output/'results.json').write_text(json.dumps(summary,indent=2)+'\n')
    print('EVAL R2_10_work', json.dumps({k:v for k,v in summary.items() if k!='results'}),flush=True)


if __name__ == '__main__':
    main()
