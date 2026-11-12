#!/usr/bin/env python3
"""Offline, deterministic TBG1 tokenizer/compiler and Python scoring reference.
Run with python3 -I. Stdlib only; never executes or fetches input content.
No Typr/FrequencyWords data is used to select vocabulary or supply counts.
"""
import argparse
from collections import Counter, defaultdict
import hashlib
import json
import math
from pathlib import Path
import struct
import unicodedata as ud
import zlib

PIN = 'cd9dbfeeed7f2c377d6e9792f4d7a583c0ad3538'
SOURCE_HASHES = {
    'de': 'de6bd33fc5742350690fa4be6197aafd9be2c6c9fe4b70b8c5c8670971acc117',
    'en': '31ac8e200449ebd7aee4a8c6bd16d4dafd076cf11f7c3efe1035f0283712d136',
}
BOS = '<s>'
HEADER = struct.Struct('<4sHH2sHIIIIIIQfIHHII')
WORD = struct.Struct('<IIIII')
EDGE = struct.Struct('<HHI')
DISCOUNT = 0.5
ALPHA = 0.5


def key(s):
    # Deliberately not casefold: German ß must not become ss.
    return ud.normalize('NFC', s.lower())


def tokenize(text, lang):
    """Return sentences of original-case words; None is a number/invalid barrier.
    .!?… end a sentence; other punctuation separates words. Internal English
    apostrophes (ASCII/right-curly) are retained, mapped to ASCII. No EOS token.
    Unicode letter categories only, not digits/underscores. No accent stripping.
    """
    text = ud.normalize('NFC', text).replace('\u2019', "'")
    result, sent, i = [], [], 0
    while i < len(text):
        c = text[i]
        if c.isalpha():
            start = i
            i += 1
            while i < len(text):
                if text[i].isalpha():
                    i += 1
                elif (lang == 'en' and text[i] == "'" and i + 1 < len(text)
                      and text[i - 1].isalpha() and text[i + 1].isalpha()):
                    i += 1
                else:
                    break
            token = text[start:i]
            sent.append(token if len(token) <= 32 and len(token.encode('utf-8')) <= 128 else None)
            continue
        if c in '.!?\u2026':
            if sent:
                result.append(sent)
                sent = []
        elif c.isnumeric() or ud.category(c) in ('Cc', 'Cf') and not c.isspace():
            if not sent or sent[-1] is not None:
                sent.append(None)
        i += 1
    if sent:
        result.append(sent)
    return [s for s in result if any(t is not None for t in s)]


def events(sent):
    prev = BOS
    for surface in sent:
        if surface is None:
            prev = None
            continue
        w = key(surface)
        if prev is not None:
            yield prev, w
        prev = w


def load_corpus(path, lang):
    raw = path.read_bytes()
    sha = hashlib.sha256(raw).hexdigest()
    if sha != SOURCE_HASHES[lang]:
        raise ValueError('input differs from reviewed, pinned CC0 sentence-collector file')
    train, test, seen = [], [], set()
    duplicates, empty, parsed = 0, 0, 0
    lines = raw.decode('utf-8', errors='strict').splitlines()
    for line in lines:
        sentences = tokenize(line, lang)
        if not sentences:
            empty += 1
        for sentence in sentences:
            parsed += 1
            # Sentence-level dedup/split groups case/punctuation-equivalent token
            # sequences; exact normalized sentences cannot cross the split.
            canonical = json.dumps([key(t) if t else None for t in sentence],
                                   ensure_ascii=False, separators=(',', ':')).encode('utf-8')
            digest = hashlib.sha256(canonical).digest()
            if digest in seen:
                duplicates += 1
                continue
            seen.add(digest)
            (test if int.from_bytes(digest[:8], 'big') % 10 == 0 else train).append(sentence)
    return train, test, dict(input_sha256=sha, input_bytes=len(raw), source_lines=len(lines),
                            parsed_sentences=parsed, duplicate_sentences_removed=duplicates,
                            empty_lines_removed=empty,
                            train_sentences=len(train), test_sentences=len(test))


def train_model(sentences, top_n, top_k, min_count, exclude=frozenset()):
    """exclude: lowercase keys never selected into the vocabulary (their events
    still count in context totals C(h), i.e. become OOV continuation mass)."""
    uni, interior, anycase = Counter(), defaultdict(Counter), defaultdict(Counter)
    for sent in sentences:
        for i, surface in enumerate(sent):
            if surface is not None:
                w = key(surface)
                uni[w] += 1
                anycase[w][surface] += 1
                if i > 0 and sent[i - 1] is not None:
                    interior[w][surface] += 1
    selected = [w for w in sorted(uni, key=lambda w: (-uni[w], w.encode('utf-8'))) if w not in exclude][:top_n]
    vocab = [BOS] + sorted(selected, key=lambda w: w.encode('utf-8'))
    ids = {w: i for i, w in enumerate(vocab)}
    counts, totals = defaultdict(Counter), Counter()
    for sent in sentences:
        for h, w in events(sent):
            if h in ids:
                totals[h] += 1  # includes followers outside vocabulary
                if w in ids:
                    counts[h][w] += 1
    rows, displays = [], []
    for w in vocab:
        row = [(ids[f], c) for f, c in counts[w].items() if c >= min_count]
        row.sort(key=lambda x: (-x[1], x[0]))
        rows.append(row[:top_k])
        votes = interior[w] or anycase[w]
        displays.append(BOS if w == BOS else min(votes, key=lambda s: (-votes[s], s.encode('utf-8'))))
    return vocab, displays, [uni[w] for w in vocab], [totals[w] for w in vocab], rows, {
        'train_tokens': sum(uni.values()), 'train_word_types': len(uni),
        'selected_types': len(selected), 'retained_train_tokens': sum(uni[w] for w in selected),
        'selection': 'training-only top-N; existing Typr tries NOT used',
    }


def compile_model(lang, vocab, display, uni, totals, rows, top_n, top_k, min_count):
    pool, offsets = bytearray(), {}
    def string_offset(s):
        if s not in offsets:
            offsets[s] = len(pool)
            pool.extend(s.encode('utf-8') + b'\0')
        return offsets[s]
    words, edges = bytearray(), bytearray()
    for w, d, u, total, row in zip(vocab, display, uni, totals, rows):
        words.extend(WORD.pack(string_offset(w), string_offset(d), u, len(edges) // EDGE.size, total))
        for follower, count in row:
            edges.extend(EDGE.pack(follower, 0, count))
    vo = HEADER.size
    eo = vo + len(words)
    so = eo + len(edges)
    payload = words + edges + pool
    header = HEADER.pack(b'TBG1', 1, HEADER.size, lang.encode('ascii'), 0, len(vocab),
                         len(edges) // EDGE.size, vo, eo, so, HEADER.size + len(payload),
                         sum(uni), DISCOUNT, top_n, top_k, min_count, zlib.crc32(payload), 0)
    return header + payload


class Model:
    """Independent binary reader/scorer; evaluation uses emitted bytes, not trainer."""
    def __init__(self, data):
        if len(data) < HEADER.size:
            raise ValueError('short header')
        (magic, version, hs, lang, flags, v, e, vo, eo, so, size, total, discount,
         top_n, top_k, min_count, crc, reserved) = HEADER.unpack_from(data)
        if not (magic == b'TBG1' and version == 1 and hs == 64 and lang in (b'de', b'en')
                and flags == reserved == 0 and 1 <= v <= 65535 and 1 <= top_k <= 16
                and min_count >= 1 and discount == DISCOUNT and vo == 64
                and eo == vo + v * 20 and so == eo + e * 8 and so < size == len(data)
                and size <= 1048576 and zlib.crc32(data[64:]) == crc):
            raise ValueError('invalid header/offsets/checksum')
        self.lang = lang.decode()
        self.vocab, self.display, self.uni, self.rows, self.totals = [], [], [], [], []
        def string(off):
            start = so + off
            if not so <= start < size:
                raise ValueError('string offset out of range')
            end = data.find(b'\0', start, min(size, start + 129))
            if end == -1:
                raise ValueError('unterminated string')
            return data[start:end].decode('utf-8', errors='strict')
        records = [WORD.unpack_from(data, vo + i * 20) for i in range(v)]
        if records[0][3] != 0:
            raise ValueError('invalid first row')
        for i, (ko, do, u, first, context_total) in enumerate(records):
            end = records[i + 1][3] if i + 1 < v else e
            if not 0 <= first <= end <= e or end - first > top_k:
                raise ValueError('invalid row extent')
            row = {}
            previous = None
            for j in range(first, end):
                f, zero, count = EDGE.unpack_from(data, eo + 8 * j)
                order = (-count, f)
                if not (0 < f < v and zero == 0 and count >= min_count and f not in row
                        and (previous is None or previous < order)):
                    raise ValueError('invalid edge')
                previous = order
                row[f] = count
            if sum(row.values()) > context_total:
                raise ValueError('row exceeds context total')
            self.vocab.append(string(ko))
            self.display.append(string(do))
            self.uni.append(u)
            self.totals.append(context_total)
            self.rows.append(row)
        if (self.vocab[0] != BOS or self.uni[0] != 0 or sum(self.uni) != total
                or len(set(self.vocab)) != v or any(u == 0 for u in self.uni[1:])
                or self.vocab[1:] != sorted(self.vocab[1:], key=lambda w: w.encode('utf-8'))
                or any(w != key(w) for w in self.vocab[1:])):
            raise ValueError('invalid vocabulary')
        self.ids = {w: i for i, w in enumerate(self.vocab)}
        self.p0 = [0.0] + [(u + ALPHA) / (total + ALPHA * (v - 1)) for u in self.uni[1:]]
        self.base = sorted(range(1, v), key=lambda i: (-self.p0[i], i))
        self.pos = {wid: rank for rank, wid in enumerate(self.base)}
        self.discount = discount
        self.top_k = top_k
        self.meta = dict(vocabulary_records=v, edges=e, compiled_bytes=len(data),
                         sha256=hashlib.sha256(data).hexdigest(), string_bytes=size-so,
                         vocabulary_bytes=v*20, edge_bytes=e*8, header_bytes=64)

    def distribution(self, h):
        i = self.ids.get(h)
        if i is None or self.totals[i] == 0:
            return 1.0, {}
        c = self.totals[i]
        boost = {w: (n - self.discount) / c for w, n in self.rows[i].items()}
        return 1.0 - sum(boost.values()), boost

    def prob(self, h, w):
        i = self.ids.get(w)
        if i is None or i == 0:
            return 0.0
        lam, boost = self.distribution(h)
        return lam * self.p0[i] + boost.get(i, 0.0)

    def suggest(self, h, n=3):
        lam, boost = self.distribution(h)
        pool = set(self.base[:n]) | set(boost)
        ranking = sorted(pool, key=lambda i: (-(lam * self.p0[i] + boost.get(i, 0.0)), i))
        return [(self.vocab[i], self.display[i], lam * self.p0[i] + boost.get(i, 0.0))
                for i in ranking[:n]]

    def rank(self, h, w):
        target = self.ids.get(w)
        if target is None or target == 0:
            return None
        lam, boost = self.distribution(h)
        score = lam * self.p0[target] + boost.get(target, 0.0)
        target_order = (-score, target)
        # Binary-search the unchanged background order, then adjust <=K boosts.
        lo, hi = 0, len(self.base)
        while lo < hi:
            mid = (lo + hi) // 2
            i = self.base[mid]
            if (-lam * self.p0[i], i) < target_order:
                lo = mid + 1
            else:
                hi = mid
        ahead = lo - int(self.pos[target] < lo)
        for i, b in boost.items():
            if i != target:
                ahead -= int((-lam * self.p0[i], i) < target_order)
                ahead += int((-(lam * self.p0[i] + b), i) < target_order)
        return ahead + 1


class LanguageMixer:
    """D3b reference: ephemeral DE/EN evidence, no labels or persistent history.
    Consume each completed word before suggesting its follower. sentence_boundary
    halves evidence without inventing a cross-sentence bigram; reset on field change.
    """
    DEFAULTS = dict(decay=0.75, evidence_clip=3.0, state_clip=6.0, floor=0.05, boundary_decay=0.5)
    WRONG_RATIO = 4.0  # evaluation-only fixed language label threshold

    def __init__(self, de, en, **params):
        unknown = set(params) - set(self.DEFAULTS)
        if unknown:
            raise TypeError(f'unknown parameters {unknown}')
        p = dict(self.DEFAULTS, **params)
        self.decay, self.evidence_clip, self.state_clip = p['decay'], p['evidence_clip'], p['state_clip']
        self.floor, self.boundary_decay = p['floor'], p['boundary_decay']
        self.models = (de, en)
        self.union_size = len(set(de.vocab[1:]) | set(en.vocab[1:]))
        self.denoms = [sum(m.uni) + 0.5 * (self.union_size + 1) for m in self.models]
        # Label log-ratios use fixed default smoothing, independent of tuned params.
        self.state = 0.0

    def reset(self):
        self.state = 0.0

    def sentence_boundary(self):
        self.state *= self.boundary_decay

    def q(self, lang_index, word):
        m = self.models[lang_index]
        i = m.ids.get(word, 0)
        return (m.uni[i] + 0.5) / self.denoms[lang_index]

    def log_ratio(self, word):
        word = key(word)
        if word == BOS or not any(word in m.ids for m in self.models):
            return 0.0  # both OOV: do not infer from corpus-size imbalance
        return math.log(self.q(0, word) / self.q(1, word))

    def evidence(self, word):
        c = self.evidence_clip
        return max(-c, min(c, self.log_ratio(word)))

    def consume(self, word):
        c = self.state_clip
        self.state = max(-c, min(c, self.decay * self.state + self.evidence(word)))
        return self.weight_de()

    def weight_de(self):
        return self.floor + (1.0 - 2.0 * self.floor) / (1.0 + math.exp(-self.state))

    def suggestion_language(self, word):
        # Fixed metric label, independent of posterior/params/which model proposed it.
        r = self.log_ratio(word)
        t = math.log(self.WRONG_RATIO)
        return 'de' if r >= t else 'en' if r <= -t else None


# Tatoeba stock character names (D3b): never offered as suggestions, still valid contexts.
SUGGESTION_SUPPRESS = frozenset({'tom', 'mary', 'maria', 'john'})


def mixture_suggest(de, en, context, weight_de=0.5, n=3, suppress=frozenset()):
    """Exact union-vocabulary mixture top-n with a sorted-background bound.
    Unlike a fixed per-language top-16 pool this cannot miss shared-word mass.
    Ties: ascending UTF-8 key; display from larger weighted component (DE on tie).
    suppress: keys excluded from the result (top-n among the remaining words).
    """
    models, weights = (de, en), (weight_de, 1.0 - weight_de)
    distributions = [m.distribution(context) for m in models]
    factors = [w * d[0] for w, d in zip(weights, distributions)]
    pool = {m.vocab[i] for m, (_, boost) in zip(models, distributions) for i in boost} - suppress

    def score(word):
        return sum(w * (lam * m.p0[m.ids[word]] + boost.get(m.ids[word], 0.0))
                   for m, w, (lam, boost) in zip(models, weights, distributions) if word in m.ids)

    scored = {w: score(w) for w in pool}
    pos = 0
    while True:
        for m in models:
            if pos < len(m.base):
                w = m.vocab[m.base[pos]]
                if w not in scored and w not in suppress:
                    scored[w] = score(w)
        pos += 1
        best = sorted(scored, key=lambda w: (-scored[w], w.encode('utf-8')))[:n]
        bound = sum(f * m.p0[m.base[pos]] for m, f in zip(models, factors) if pos < len(m.base))
        if (len(best) >= n and scored[best[-1]] > bound) or all(pos >= len(m.base) for m in models):
            return [(w, scored[w]) for w in best]


def evaluate(model, sentences):
    pairs = Counter(pair for sent in sentences for pair in events(sent))
    def metrics(subset):
        n = sum(subset.values())
        hit, rr3, rr, baseline, base_rr, covered, known_context = 0, 0.0, 0.0, 0, 0.0, 0, 0
        for (h, w), count in sorted(subset.items()):
            r = model.rank(h, w)
            if r is not None:
                covered += count
                rr += count / r
                if r <= 3:
                    hit += count
                    rr3 += count / r
                b = model.pos[model.ids[w]] + 1
                baseline += count * (b <= 3)
                base_rr += count / b
            known_context += count * (h in model.ids)
        return dict(tokens=n, recall_at_3=hit/n if n else 0, mrr=rr/n if n else 0,
                    mrr_at_3=rr3/n if n else 0, unigram_recall_at_3=baseline/n if n else 0,
                    unigram_mrr=base_rr/n if n else 0,
                    follower_vocabulary_coverage=covered/n if n else 0,
                    context_vocabulary_coverage=known_context/n if n else 0)
    return {'lexical_bigrams': metrics(Counter({p:c for p,c in pairs.items() if p[0] != BOS})),
            'with_sentence_start': metrics(pairs),
            'sentence_start_only': metrics(Counter({p:c for p,c in pairs.items() if p[0] == BOS}))}

