#!/usr/bin/env python3
"""Explicit offline final evaluation; no tuning. Run python3 -I."""
import argparse
from collections import Counter
import json
from pathlib import Path
import runpy
import sqlite3

p = argparse.ArgumentParser()
for n in ('tool', 'cache', 'original', 'baseline', 'output', 'fixture', 'vectors'):
    p.add_argument(n, type=Path)
a = p.parse_args()
api = runpy.run_path(str(a.tool))
API = api['API']
fixture = json.loads(a.fixture.read_text())
results = {}
new_fixture = {'sources': 'Leipzig news 2024, Wikipedia via Leipzig, OPUS OpenSubtitles 2018; see SOURCE', 'sentences': {}}
for lang in ('de', 'en'):
    models = [API['Model']((d/f'keyboard-{lang}.tbg').read_bytes()) for d in (a.baseline, a.output)]
    sets = {'round1_64': api['pairs'](fixture['sentences'][lang])}
    db = api['connection'](a.cache, a.original)
    for source, mask in (('cv', 1), ('tatoeba', 2)):
        sets['round1_full_'+source] = api['pairs'](json.loads(t) for t, in db.execute("SELECT tokens FROM old.sentences WHERE lang=? AND part='test' AND mask&?!=0", (lang, mask)))
    for source in ('news', 'wiki', 'opus'):
        sentences = api['Sentences'](a.cache, a.original, lang, 'test', [source], base=False)
        sets['new_'+source] = api['pairs'](sentences)
        # Identical small public new fixture, no barriers, 5-20 words; sorted digest.
        new_fixture['sentences'][lang+'_'+source] = [s for s in sentences if 5 <= len(s) <= 20 and None not in s][:64]
    for name, counts in sets.items():
        metrics = [api['measure'](m, counts) for m in models]
        results[lang+'_'+name] = dict(before=metrics[0], after=metrics[1])
        print('EVAL R2_9', lang, name, json.dumps(results[lang+'_'+name]), flush=True)
    db.close()
(a.output/'evaluation.json').write_text(json.dumps(results, indent=2)+'\n')
(a.output/'context-heldout-r2.json').write_text(json.dumps(new_fixture, ensure_ascii=False, indent=2)+'\n')
# Recompute existing reference vectors from the emitted bytes, preserving sequences.
spec = json.loads(a.vectors.read_text())
de, en = [API['Model']((a.output/f'keyboard-{lang}.tbg').read_bytes()) for lang in ('de', 'en')]
prev_sequence = None
lm = None
for v in spec['vectors']:
    if v['sequence'] != prev_sequence:
        lm = API['LanguageMixer'](de, en)
        prev_sequence = v['sequence']
    if v['event'] == 'sentence_boundary':
        lm.sentence_boundary()
    else:
        w = v['consumed']
        v['evidence'] = lm.evidence(w)
        lm.consume(w)
    v.update(state=lm.state, weight_de=lm.weight_de(),
        top3=API['mixture_suggest'](de, en, v['context'], lm.weight_de()),
        top3_suppressed=API['mixture_suggest'](de, en, v['context'], lm.weight_de(), suppress=API['SUGGESTION_SUPPRESS']))
spec['union_size'] = API['LanguageMixer'](de,en).union_size
(a.output/'swift-reference-vectors.json').write_text(json.dumps(spec, ensure_ascii=False, indent=2)+'\n')
