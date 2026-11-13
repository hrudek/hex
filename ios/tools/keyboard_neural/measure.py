#!/usr/bin/env python3
"""Measure one explicitly requested standalone process; Linux RSS, not iPhone.
Use a fresh wrapper per measurement: resource children high-water is cumulative.
"""
import resource
import subprocess
import sys

if len(sys.argv) < 2:
    raise SystemExit('usage: python3 -I measure.py executable [args...]')
result = subprocess.run(sys.argv[1:], check=False)
print('EVAL R2_10_process peak_rss_kib=' + str(resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss), flush=True)
raise SystemExit(result.returncode)
