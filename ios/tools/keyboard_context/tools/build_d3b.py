#!/usr/bin/env python3
"""Explicit offline D3b compiler for the approved CV + Tatoeba snapshots.
Stdlib only. No acquisition/network/runtime data collection. Inputs stay outside Git.
"""
import argparse
import bz2
from collections import Counter
import gzip
import hashlib
import json
import math
from pathlib import Path
import runpy
import sqlite3
import time

API = runpy.run_path(str(Path(__file__).with_name('build_bigrams.py')))
ROOT = Path(__file__).resolve().parents[1]
key, tokenize, events = (API[n] for n in ('key','tokenize','events'))
Model, BOS = API['Model'], API['BOS']
WORK, OUT = ROOT/'work-d3b', ROOT/'out'
HASHES = {'de': 'fd31882dc105bd8fa1390e08b48c42f6194ffae89bbf4bb82decf6ef94f6f2a7',
          'en': 'afec98e4c44a72f8fc709ce4d672fd3ab7f9ca731402f5d35e384b0b21b207c5'}
ISO = {'de':'deu', 'en':'eng'}
# Official per-language CC0 subset exports from the same weekly run (license screen only).
CC0_HASHES = {'de': 'df8c16713e5715a0e1343bc1195004463e7facee08863d3cd709cbf123a74587',
              'en': 'c2e2edd063a31cbbc8e416a4858225e934bbb0afff485031821e59f230ccf1ca'}


def cc0_ids(lang):
    path = ROOT/f'raw/tatoeba-licensing/{ISO[lang]}_sentences_CC0.tsv.bz2'
    if hashlib.sha256(path.read_bytes()).hexdigest() != CC0_HASHES[lang]:
        raise ValueError('unreviewed CC0 export hash')
    ids = set()
    with bz2.open(path, mode='rt', encoding='utf-8', errors='strict') as lines:
        for line in lines:
            fields = line.rstrip('\n').split('\t')
            if len(fields) != 4 or fields[1] != ISO[lang] or not fields[0].isdigit():
                raise ValueError('unexpected CC0 export schema')
            ids.add(fields[0])
    return ids


def dump(path, data):
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')


def digest_sentence(sent):
    canonical = json.dumps([key(w) if w else None for w in sent], ensure_ascii=False, separators=(',', ':'))
    return hashlib.sha256(canonical.encode()).digest()


def partition(digest):
    r = int.from_bytes(digest[:8], 'big') % 10
    return 'test' if r == 0 else 'dev' if r == 1 else 'train'


def connect():
    return sqlite3.connect(WORK/'corpus.sqlite')


def prepare():
    WORK.mkdir(exist_ok=True)
    OUT.mkdir(exist_ok=True)
    if (WORK/'corpus.sqlite').exists():
        raise SystemExit('cache exists: reuse build/evaluate or explicitly remove local derived cache')
    db = connect()
    db.execute('PRAGMA journal_mode=OFF')
    db.execute('PRAGMA synchronous=OFF')
    db.execute('CREATE TABLE sentences(lang TEXT, digest BLOB, part TEXT, mask INT, tokens TEXT, PRIMARY KEY(lang,digest)) WITHOUT ROWID')
    authors = Counter()
    authors_by = Counter()
    stats = {}
    with (OUT/'tatoeba-training-attribution.tsv.gz').open('wb') as f, gzip.GzipFile(filename='', fileobj=f, mode='wb', mtime=0) as credit:
        credit.write(b'sentence_id\tlanguage\texported_owner\tsource_url\tlicense\n')
        for lang in ('de','en'):
            for source in ('cv','tatoeba'):
                path = ROOT/(f'raw/common-voice-cd9dbfee/{lang}-sentence-collector.txt' if source == 'cv' else f'raw/tatoeba/{ISO[lang]}_sentences_detailed.tsv.bz2')
                sha = hashlib.sha256(path.read_bytes()).hexdigest()
                if sha != (API['SOURCE_HASHES'][lang] if source == 'cv' else HASHES[lang]):
                    raise ValueError('unreviewed input SHA-256; review release/license before accepting')
                st = Counter()
                mask = 1 if source == 'cv' else 2
                cc0 = cc0_ids(lang) if source == 'tatoeba' else set()
                seen_ids = set()
                opener = path.open if source == 'cv' else lambda **kw: bz2.open(path, **kw)
                with opener(mode='rt', encoding='utf-8', errors='strict') as lines:
                    for line in lines:
                        st['source_lines'] += 1
                        sid, owner = None, None
                        if source == 'tatoeba':
                            fields = line.rstrip('\n').split('\t')
                            if len(fields) != 6 or fields[1] != ISO[lang] or not fields[0].isdigit():
                                raise ValueError('unexpected detailed-export schema/language; review before use')
                            sid, _, text, owner, _, _ = fields
                            seen_ids.add(sid)
                            st['rows_cc0_1_0' if sid in cc0 else 'rows_cc_by_2_0_fr'] += 1
                            if owner in ('', r'\N'):
                                st['excluded_missing_owner_cc0' if sid in cc0 else 'excluded_missing_owner_cc_by'] += 1
                                st['excluded_missing_owner'] += 1
                                continue
                        else:
                            text = line.rstrip('\n')
                        credit_row = False
                        for sent in tokenize(text, lang):
                            st['parsed_sentences'] += 1
                            digest = digest_sentence(sent)
                            part = partition(digest)
                            # Same canonical digest => same partition globally across languages/sources.
                            cursor = db.execute('INSERT OR IGNORE INTO sentences VALUES(?,?,?,?,?)',
                                (lang,digest,part,mask,json.dumps(sent,ensure_ascii=False,separators=(',',':'))))
                            if cursor.rowcount:
                                st['unique_new_sentences'] += 1
                            else:
                                old = db.execute('SELECT mask FROM sentences WHERE lang=? AND digest=?',(lang,digest)).fetchone()[0]
                                st['duplicate_in_source' if old & mask else 'overlap_other_source'] += 1
                                db.execute('UPDATE sentences SET mask=mask|? WHERE lang=? AND digest=?',(mask,lang,digest))
                            credit_row |= part == 'train'
                        if source == 'tatoeba' and credit_row:
                            licence = 'CC0 1.0' if sid in cc0 else 'CC BY 2.0 FR'
                            authors[owner] += 1
                            authors_by[owner] += licence == 'CC BY 2.0 FR'
                            st['credited_training_rows_cc0' if sid in cc0 else 'credited_training_rows_cc_by'] += 1
                            credit.write(f'{sid}\t{lang}\t{owner}\thttps://tatoeba.org/en/sentences/show/{sid}\t{licence}\n'.encode())
                        if st['source_lines'] % 100000 == 0:
                            print(lang,source,dict(st),flush=True)
                db.commit()
                if source == 'tatoeba':
                    # Every CC0-listed ID must be in the detailed (license != '') export.
                    st['cc0_ids_listed'] = len(cc0)
                    st['cc0_ids_missing_from_detailed_export'] = len(cc0 - seen_ids)
                stats[f'{lang}/{source}'] = dict(st, sha256=sha, input_bytes=path.stat().st_size)
    db.execute('CREATE INDEX split_index ON sentences(lang,part)')
    db.commit()
    stats['split_counts'] = [dict(language=l,partition=p,source_mask=m,sentences=n) for l,p,m,n in db.execute('SELECT lang,part,mask,count(*) FROM sentences GROUP BY lang,part,mask')]
    # Cross-language equal sequences share a digest and never straddle partitions.
    assert db.execute('SELECT count(*) FROM (SELECT digest FROM sentences GROUP BY digest HAVING count(DISTINCT part)>1)').fetchone()[0] == 0
    stats['global_partition_overlap'] = 0
    stats['training_export_owner_count'] = len(authors)
    stats['training_export_owner_count_cc_by_rows'] = sum(1 for n in authors_by.values() if n)
    dump(OUT/'corpus-stats.json',stats)
    (OUT/'tatoeba-contributors.tsv').write_text('exported_owner\tcredited_training_export_rows\tof_which_cc_by_2_0_fr\n'+''.join(f'{u}\t{n}\t{authors_by[u]}\n' for u,n in sorted(authors.items(),key=lambda x:x[0].encode())),encoding='utf-8')
    db.close()


class Sentences:
    def __init__(self, lang, part, source=None):
        self.lang,self.part,self.source = lang,part,source
    def __iter__(self):
        db = connect()
        sql = 'SELECT tokens FROM sentences WHERE lang=? AND part=?'
        args = [self.lang,self.part]
        if self.source:
            sql += ' AND mask & ? != 0'
            args.append(1 if self.source == 'cv' else 2)
        # Fixed input-order representative (CV before Tatoeba); digest iteration order.
        for (tokens,) in db.execute(sql+' ORDER BY digest',args):
            yield json.loads(tokens)
        db.close()


PACK_HASHES = {'de': '3efe6edcec45e6a134eaa80ee336e2549d173a432ff57c4b37b8d81c0ad04e79',
               'en': '26bdef6715570b7e7b8890467fc165c586974b417d3cc7f0ae8791a52b3578d9'}


def compile_selected(verify=False):
    """Fixed D3b validation-selected N/K/min-count, never tune on test data.
    Verification recounts the inert cache; preparation independently validates raw hashes.
    """
    total = 0
    for lang in ('de', 'en'):
        v, d, u, t, r, _ = API['train_model'](Sentences(lang, 'train'), 8000, 3, 10)
        raw = API['compile_model'](lang, v, d, u, t, r, 8000, 3, 10)
        Model(raw)
        if hashlib.sha256(raw).hexdigest() != PACK_HASHES[lang]:
            raise ValueError('compiled bytes differ from approved D3b pack')
        path = OUT/f'keyboard-{lang}.tbg'
        if verify:
            if path.read_bytes() != raw:
                raise ValueError('second compilation differed')
        else:
            path.write_bytes(raw)
        total += len(raw)
        print(f'{lang}: bytes={len(raw)} sha256={PACK_HASHES[lang]}', flush=True)
    if total > 1048576:
        raise ValueError('combined pack budget exceeded')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('stage', choices=['prepare', 'compile', 'verify'])
    parser.add_argument('data_directory', type=Path, help='Explicit external raw/work-d3b/out root')
    args = parser.parse_args()
    ROOT = args.data_directory.resolve()
    WORK, OUT = ROOT/'work-d3b', ROOT/'out'
    if args.stage == 'prepare':
        prepare()
    else:
        compile_selected(verify=args.stage == 'verify')
