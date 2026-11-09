#!/usr/bin/env python3
"""Load Typr's fixed iOS identity (app.json) and publish it as APP_CONFIG."""
import json
import os
from pathlib import Path
import re

HERE = Path(__file__).resolve().parent


def load():
    config = json.loads((HERE / 'app.json').read_text())
    if config['app'] != 'typr' or config['directory'] != 'ios':
        raise ValueError('app.json describes the Typr iOS app only')
    if not re.fullmatch(r'[A-Za-z0-9_-]+\.xcodeproj', config['project']):
        raise ValueError('Invalid Xcode project')
    if not re.fullmatch(r'[A-Za-z0-9_. -]+', config['scheme']):
        raise ValueError('Invalid Xcode scheme')
    if not re.fullmatch(r'[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+', config['bundle_id']):
        raise ValueError('Invalid bundle ID')
    if not re.fullmatch(r'[a-z][a-z0-9+.-]{0,63}', config['url_scheme']):
        raise ValueError('Invalid URL scheme')
    if not re.fullmatch(r'[A-Za-z0-9+ ._-]{1,30}', config['display_name']):
        raise ValueError('Invalid display name')
    for suffix in config['extension_suffixes']:
        if not re.fullmatch(r'[A-Za-z0-9-]+', suffix):
            raise ValueError('Invalid extension suffix')
    config['bundle_ids'] = [config['bundle_id']] + [
        f'{config["bundle_id"]}.{suffix}' for suffix in config['extension_suffixes']
    ]
    return config


if __name__ == '__main__':
    serialized = json.dumps(load(), separators=(',', ':'))
    print(serialized)
    if os.getenv('GITHUB_OUTPUT'):
        with open(os.environ['GITHUB_OUTPUT'], 'a') as output:
            output.write(f'config={serialized}\n')
