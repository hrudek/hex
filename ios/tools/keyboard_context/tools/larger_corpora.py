#!/usr/bin/env python3
"""Offline R2-9 corpus experiment. Run with python3 -I; stdlib only.
Archives are data: stream only regular *-sentences.txt members, never extract,
import or execute archive content. All input/work/output paths are explicit.
"""
import argparse
from collections import Counter
import gzip
import hashlib
import io
import itertools
import json
from pathlib import Path
import runpy
import sqlite3
import tarfile

API = runpy.run_path(str(Path(__file__).with_name('build_bigrams.py')))


def digest(sentence):
    canonical = json.dumps([API['key'](w) if w else None for w in sentence],
                           ensure_ascii=False, separators=(',', ':'))
    return hashlib.sha256(canonical.encode()).digest()


def partition(d):
    n = int.from_bytes(d[:8], 'big') % 10
    return 'test' if n == 0 else 'dev' if n == 1 else 'train'


def lines(path, kind):
    if kind == 'opus':
        with gzip.open(path, 'rt', encoding='utf-8') as f:
            yield from f
    else:
        found = False
        with tarfile.open(path, 'r:gz') as archive:
            for member in archive:
                if member.isfile() and member.name.endswith('-sentences.txt'):
                    if found:
                        raise ValueError('multiple sentence members')
                    found = True
                    with io.TextIOWrapper(archive.extractfile(member), encoding='utf-8') as f:
                        for line in f:
                            sid, sep, text = line.partition('\t')
                            if not sep or not sid.isdigit():
                                raise ValueError('unexpected Leipzig sentence schema')
                            yield text
        if not found:
            raise ValueError('missing sentences member')


def prepare(spec, cache):
    config = json.loads(spec.read_text())
    # Exclusive creation: never silently reuse a stale experiment database.
    with cache.open('xb'):
        pass
    db = sqlite3.connect(cache)
    db.execute('CREATE TABLE sentences(lang TEXT,digest BLOB,part TEXT,source TEXT,tokens TEXT,PRIMARY KEY(lang,digest,source)) WITHOUT ROWID')
    records = []
    for entry in config:
        path = Path(entry['path'])
        sha = hashlib.file_digest(path.open('rb'), 'sha256').hexdigest()
        if sha != entry['sha256']:
            raise ValueError('input SHA256 mismatch')
        counts = Counter()
        for text in itertools.islice(lines(path, entry['kind']), entry['max_lines']):
            counts['input_lines'] += 1
            if len(text) > 16384:
                counts['overlong_lines'] += 1
                continue
            for sentence in API['tokenize'](text, entry['language']):
                d = digest(sentence)
                cursor = db.execute('INSERT OR IGNORE INTO sentences VALUES(?,?,?,?,?)',
                    (entry['language'], d, partition(d), entry['source'], json.dumps(sentence, ensure_ascii=False)))
                counts['unique' if cursor.rowcount else 'duplicates'] += 1
        db.commit()
        records.append(dict(entry, counts=dict(counts), bytes=path.stat().st_size))
        print(json.dumps(records[-1]), flush=True)
    db.execute('CREATE INDEX split_index ON sentences(lang,part,source)')
    db.commit()
    db.close()
    cache.with_suffix('.json').write_text(json.dumps(records, indent=2)+'\n')


def connection(cache, original):
    db = sqlite3.connect(f'file:{cache.resolve()}?mode=ro', uri=True)
    db.execute('ATTACH DATABASE ? AS old', (f'file:{original.resolve()}?mode=ro',))
    return db


class Sentences:
    def __init__(self, cache, original, lang, part, sources, base=True):
        self.args = cache, original, lang, part, sources, base

    def __iter__(self):
        cache, original, lang, part, sources, base = self.args
        db = connection(cache, original)
        try:
            if base:
                for tokens, in db.execute('SELECT tokens FROM old.sentences WHERE lang=? AND part=? ORDER BY digest', (lang, part)):
                    yield json.loads(tokens)
            # Union/dedup across every selected source AND the original corpus.
            if sources:
                marks = ','.join('?' for _ in sources)
                # SQLite's single min() binds bare tokens to the lexical-first source.
                sql = f'''SELECT n.tokens, min(n.source) FROM sentences n WHERE lang=? AND part=? AND source IN ({marks})
                    AND NOT EXISTS(SELECT 1 FROM old.sentences o WHERE o.lang=n.lang AND o.digest=n.digest)
                    GROUP BY digest ORDER BY digest'''
                for tokens, _ in db.execute(sql, (lang, part, *sources)):
                    yield json.loads(tokens)
        finally:
            db.close()


def pairs(sentences):
    return Counter(p for s in sentences for p in API['events'](s) if p[0] != API['BOS'])


def measure(model, counts):
    by_context = {}
    one = three = 0
    for (h, w), n in counts.items():
        if h not in by_context:
            by_context[h] = [r[0] for r in model.suggest(h)]
        top = by_context[h]
        one += n * (w == top[0])
        three += n * (w in top)
    total = sum(counts.values())
    return dict(pairs=total, recall1=one/total if total else 0, recall3=three/total if total else 0)


def build(cache, original, baseline, output):
    output.mkdir(parents=True, exist_ok=True)
    results = []
    for lang in ('de', 'en'):
        # Domain-balanced validation; the test partition is never consulted here.
        dev = {s: pairs(Sentences(cache, original, lang, 'dev', [s], base=False))
               for s in ('news', 'wiki', 'opus')}
        db = connection(cache, original)
        dev['cv'] = pairs(json.loads(t) for t, in db.execute("SELECT tokens FROM old.sentences WHERE lang=? AND part='dev' AND mask&1!=0", (lang,)))
        db.close()
        before = API['Model']((baseline/f'keyboard-{lang}.tbg').read_bytes())
        before_metrics = {s: measure(before, p) for s, p in dev.items()}
        for sources in ([], ['news'], ['wiki'], ['opus'], ['news', 'wiki', 'opus']):
            label = '+'.join(sources) or 'base'
            print('counting', lang, label, flush=True)
            v, d, u, t, rows, stats = API['train_model'](Sentences(cache, original, lang, 'train', sources), 8000, 12, 10)
            for k in (3, 6, 12):
                raw = API['compile_model'](lang, v, d, u, t, [r[:k] for r in rows], 8000, k, 10)
                if len(raw) > 1048576:
                    continue
                model = API['Model'](raw)
                metrics = {s: measure(model, p) for s, p in dev.items()}
                gain = sum(metrics[s]['recall3'] - before_metrics[s]['recall3'] for s in dev)/len(dev)
                name = f'{lang}-{label}-k{k}.tbg'
                (output/name).write_bytes(raw)
                result = dict(language=lang, sources=sources, k=k, file=name, binary=model.meta,
                    selection=stats, dev=metrics, before_dev=before_metrics, balanced_gain=gain,
                    gain_per_byte=gain/len(raw))
                results.append(result)
                print('candidate', name, len(raw), round(gain, 6), flush=True)
        (output/'curve.json').write_text(json.dumps(results, indent=2)+'\n')
    # Global byte cap is unchanged (1 MiB), stricter than the owner's 2 MiB target.
    choices = [(a, b) for a in results if a['language'] == 'de' for b in results if b['language'] == 'en'
               if a['binary']['compiled_bytes'] + b['binary']['compiled_bytes'] <= 1048576
               and a['balanced_gain'] > 0 and b['balanced_gain'] > 0]
    if not choices:
        raise ValueError('no positive-gain pair within existing loader budget')
    a, b = max(choices, key=lambda ab: ((ab[0]['balanced_gain']+ab[1]['balanced_gain']) /
                 (ab[0]['binary']['compiled_bytes']+ab[1]['binary']['compiled_bytes']),
                 ab[0]['file'], ab[1]['file']))
    for c in (a, b):
        (output/f"keyboard-{c['language']}.tbg").write_bytes((output/c['file']).read_bytes())
    (output/'selected.json').write_text(json.dumps([a, b], indent=2)+'\n')


def main():
    p = argparse.ArgumentParser(description=__doc__)
    sub = p.add_subparsers(dest='command', required=True)
    q = sub.add_parser('prepare')
    q.add_argument('spec', type=Path)
    q.add_argument('cache', type=Path)
    q = sub.add_parser('build')
    for name in ('cache', 'original', 'baseline', 'output'):
        q.add_argument(name, type=Path)
    a = p.parse_args()
    if a.command == 'prepare':
        prepare(a.spec, a.cache)
    else:
        build(a.cache, a.original, a.baseline, a.output)


if __name__ == '__main__':
    main()
