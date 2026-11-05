#!/usr/bin/env python3
"""Give the CI checkout of ios/ Hex+'s own identity.

Upstream's identity (Kit's team, com.kitlangton.hex.mobile, its App Group and
URL scheme) is spread over Swift, plist, entitlement and XcodeGen files that
upstream keeps changing. Rewriting them here, on the disposable CI checkout,
keeps hex-plus free of identity commits that would conflict on every sync.
Fails closed when upstream's identity no longer looks as reviewed.
"""
import json
import os
from pathlib import Path
import re
import sys

UPSTREAM_ID = 'com.kitlangton.hex.mobile'
UPSTREAM_TEAM_ID = 'QC99C9JE59'
UPSTREAM_TEAM = 'DEVELOPMENT_TEAM: ' + UPSTREAM_TEAM_ID
UPSTREAM_PREFIX = 'bundleIdPrefix: com.kitlangton.hex'
UPSTREAM_SCHEME = 'hex-dictation'
SUFFIXES = ('.swift', '.plist', '.entitlements', '.yml')
DISPLAY_NAME = re.compile(r'^(\s*CFBundleDisplayName: )Hex( Keyboard)?$', re.MULTILINE)


def apply(directory, config, team):
    if not re.fullmatch(r'[A-Z0-9]{10}', team):
        raise ValueError('Configure a valid APPLE_TEAM_ID')
    directory = Path(directory)
    project = directory / 'project.yml'
    text = project.read_text()
    for marker in (UPSTREAM_ID, UPSTREAM_TEAM, UPSTREAM_PREFIX):
        if marker not in text:
            raise ValueError(f'Upstream identity changed ({marker!r} missing); review identity.py')
    if len(DISPLAY_NAME.findall(text)) != 3:
        raise ValueError('Expected three Hex display names in project.yml; review identity.py')
    name = config['display_name']
    for path in sorted(directory.rglob('*')):
        if not path.is_file() or path.suffix not in SUFFIXES:
            continue
        original = path.read_text()
        text = original.replace(UPSTREAM_ID, config['bundle_id'])
        text = text.replace(UPSTREAM_SCHEME, config['url_scheme'])
        text = text.replace(UPSTREAM_TEAM_ID, team)
        if path == project:
            text = text.replace(UPSTREAM_PREFIX, 'bundleIdPrefix: ' + config['bundle_id'])
            text = DISPLAY_NAME.sub(lambda m: m.group(1) + name + (m.group(2) or ''), text)
        if text != original:
            path.write_text(text)
    leftovers = [str(p) for p in directory.rglob('*')
                 if p.is_file() and p.suffix in SUFFIXES
                 and any(old in p.read_text() for old in ('com.kitlangton', UPSTREAM_TEAM_ID))]
    if leftovers:
        raise ValueError(f'Upstream identity left in: {leftovers}')


if __name__ == '__main__':
    apply(sys.argv[1], json.loads(os.environ['APP_CONFIG']), os.environ['APPLE_TEAM_ID'])
