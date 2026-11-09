#!/usr/bin/env python3
"""Validate Typr's committed build identity without rewriting the checkout.

Local builds, simulator tests and device archives all use the same identity.
Fail closed on source/config drift before an archive can reach signing.
"""
import json
import os
from pathlib import Path
import plistlib
import re
import sys

BUNDLE_ID = 'dev.rudek.typr'
TEAM_ID = '2ZNGF24932'


def validate(directory, config, team):
    if team != TEAM_ID:
        raise ValueError('APPLE_TEAM_ID must match Typr\'s committed team')
    expected = {'app': 'typr', 'directory': 'ios', 'bundle_id': BUNDLE_ID,
                'display_name': 'Typr', 'url_scheme': 'typr',
                'extension_suffixes': ['keyboard', 'widgets']}
    if any(config.get(key) != value for key, value in expected.items()):
        raise ValueError('app.json must match Typr\'s committed identity')
    directory = Path(directory)
    project = (directory / 'project.yml').read_text()
    markers = (f'DEVELOPMENT_TEAM: {team}', f'bundleIdPrefix: {BUNDLE_ID}',
               f'name: {config["scheme"]}')
    lines = {line.strip() for line in project.splitlines()}
    if any(marker not in lines for marker in markers):
        raise ValueError('Project identity changed; review identity.py and app.json')
    if config['project'] != config['scheme'] + '.xcodeproj':
        raise ValueError('Project and scheme must match')
    actual_ids = re.findall(r'^\s+PRODUCT_BUNDLE_IDENTIFIER: (\S+)$', project, re.MULTILINE)
    if sorted(actual_ids) != sorted([BUNDLE_ID, BUNDLE_ID + '.keyboard',
                                      BUNDLE_ID + '.widgets', BUNDLE_ID + '.tests']):
        raise ValueError('Unexpected project bundle IDs')
    if re.findall(r'^\s+CFBundleDisplayName: (.+)$', project, re.MULTILINE) != ['Typr'] * 3:
        raise ValueError('Expected three Typr display names')
    if re.findall(r'^\s+- typr$', project, re.MULTILINE) == []:
        raise ValueError('Missing Typr URL scheme')
    for raw in re.findall(r'^\s+path: (.+/Info\.plist)$', project, re.MULTILINE):
        info = plistlib.loads((directory / raw).read_bytes())
        if info['CFBundleDisplayName'] != 'Typr':
            raise ValueError('Unexpected display name in ' + raw)
        for url_type in info.get('CFBundleURLTypes', []):
            if url_type['CFBundleURLSchemes'] != ['typr']:
                raise ValueError('Unexpected URL scheme in ' + raw)
    for raw in re.findall(r'^\s+CODE_SIGN_ENTITLEMENTS: (.+)$', project, re.MULTILINE):
        entitlements = plistlib.loads((directory / raw).read_bytes())
        if entitlements.get('com.apple.security.application-groups') != ['group.' + BUNDLE_ID]:
            raise ValueError('Unexpected App Group in ' + raw)


if __name__ == '__main__':
    validate(sys.argv[1], json.loads(os.environ['APP_CONFIG']), os.environ['APPLE_TEAM_ID'])
