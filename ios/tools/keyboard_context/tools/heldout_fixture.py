#!/usr/bin/env python3
"""Explicit offline extraction of a small CC0 Common Voice held-out test fixture.
Never reads Typr/runtime data, never fetches. Uses the globally deduplicated D3b
cache, not training sentences. Corpus license/provenance: WordData/ATTRIBUTION.md.
"""
import argparse
import json
from pathlib import Path
import sqlite3


def extract(data_directory):
    db = sqlite3.connect(f'file:{data_directory.resolve()}/work-d3b/corpus.sqlite?mode=ro', uri=True)
    result = {'license': 'CC0 1.0 Universal', 'source': 'Common Voice sentence-collector',
              'revision': 'cd9dbfeeed7f2c377d6e9792f4d7a583c0ad3538',
              'selection': 'First 64 SHA-ordered test sentences per language, CV source mask, 5-20 words, no barriers',
              'sentences': {}}
    for lang in ('de', 'en'):
        selected = []
        for tokens, in db.execute("SELECT tokens FROM sentences WHERE lang=? AND part='test' AND mask&1!=0 ORDER BY digest", (lang,)):
            words = json.loads(tokens)
            if 5 <= len(words) <= 20 and None not in words:
                selected.append(words)
                if len(selected) == 64:
                    break
        if len(selected) != 64:
            raise ValueError('not enough held-out CV sentences')
        result['sentences'][lang] = selected
    db.close()
    return result


if __name__ == '__main__':
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('data_directory', type=Path)
    p.add_argument('output', type=Path)
    a = p.parse_args()
    a.output.write_text(json.dumps(extract(a.data_directory), ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
