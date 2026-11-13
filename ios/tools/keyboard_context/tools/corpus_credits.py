#!/usr/bin/env python3
"""Preserve Wikipedia article URL/date attribution from Leipzig archives.
Only source-link metadata, not corpus sentence text. Run python3 -I.
"""
import argparse
import gzip
import io
import tarfile


def collect(path, output):
    found = False
    with output.open('xb') as raw, gzip.GzipFile(filename='', fileobj=raw, mode='wb', mtime=0) as out:
        with tarfile.open(path, 'r:gz') as archive:
            for member in archive:
                if member.isfile() and member.name.endswith('-sources.txt'):
                    if found:
                        raise ValueError('multiple source lists')
                    found = True
                    with io.TextIOWrapper(archive.extractfile(member), encoding='utf-8') as source:
                        for line in source:
                            fields = line.rstrip('\n').split('\t')
                            if len(fields) != 3 or not fields[0].isdigit() or '.wikipedia.org/wiki/' not in fields[1]:
                                raise ValueError('unexpected Wikipedia source metadata')
                            # Source IDs and dates are those supplied by Leipzig,
                            # not claimed to be immutable Wikipedia revision IDs.
                            out.write(line.encode('utf-8'))
    if not found:
        raise ValueError('missing source list')


if __name__ == '__main__':
    from pathlib import Path
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('archive', type=Path)
    p.add_argument('output', type=Path)
    a = p.parse_args()
    collect(a.archive, a.output)
