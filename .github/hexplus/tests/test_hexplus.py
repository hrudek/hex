"""Linux-runnable checks for Hex+'s CI scripts: python3 -m unittest discover -s .github/hexplus/tests"""
import importlib.util
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import unittest

HERE = Path(__file__).resolve().parents[1]
REPO = HERE.parents[1]
sys.path.insert(0, str(HERE))


def module(name, filename):
    spec = importlib.util.spec_from_file_location(name, HERE / filename)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


config_module = module('hexplus_config', 'config.py')
identity = module('hexplus_identity', 'identity.py')
signing = module('hexplus_signing', 'signing-entitlements.py')
TEAM = 'TEAM123456'


class ConfigTests(unittest.TestCase):
    def test_bundle_ids(self):
        config = config_module.load()
        self.assertEqual(config['bundle_ids'], ['com.bearylabs.hex', 'com.bearylabs.hex.keyboard',
                                                'com.bearylabs.hex.widgets'])
        self.assertEqual(config['display_name'], 'Hex+')

    def test_entitlements_per_target(self):
        config = config_module.load()
        group = {'com.apple.security.application-groups': ['group.com.bearylabs.hex']}
        self.assertEqual(signing.required_entitlements(config, 'com.bearylabs.hex'), group)
        self.assertEqual(signing.required_entitlements(config, 'com.bearylabs.hex.keyboard'), group)
        self.assertEqual(signing.required_entitlements(config, 'com.bearylabs.hex.widgets'), {})
        with self.assertRaises(ValueError):
            signing.required_entitlements(config, 'com.unreviewed.app')


class IdentityTests(unittest.TestCase):
    """Runs against the real ios/ tree, so an upstream identity change fails here first."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.ios = Path(self.tmp.name) / 'ios'
        shutil.copytree(REPO / 'ios', self.ios)
        self.config = config_module.load()

    def tearDown(self):
        self.tmp.cleanup()

    def test_rewrites_real_checkout(self):
        identity.apply(self.ios, self.config, TEAM)
        project = (self.ios / 'project.yml').read_text()
        self.assertIn(f'DEVELOPMENT_TEAM: {TEAM}', project)
        self.assertIn('bundleIdPrefix: com.bearylabs.hex\n', project)
        for target in ('com.bearylabs.hex', 'com.bearylabs.hex.keyboard', 'com.bearylabs.hex.widgets'):
            self.assertIn(f'PRODUCT_BUNDLE_IDENTIFIER: {target}\n', project)
        self.assertEqual(project.count('CFBundleDisplayName: Hex+\n'), 2)
        self.assertEqual(project.count('CFBundleDisplayName: Hex+ Keyboard\n'), 1)
        self.assertIn('- bearylabs-hex\n', project)
        for name in ('HEXMobile/HEXMobile.entitlements', 'HEXKeyboard/HEXKeyboard.entitlements'):
            entitlements = plistlib.loads((self.ios / name).read_bytes())
            self.assertEqual(entitlements['com.apple.security.application-groups'], ['group.com.bearylabs.hex'])
        bridge = (self.ios / 'HEXShared/KeyboardBridge.swift').read_text()
        self.assertIn('"group.com.bearylabs.hex"', bridge)
        setup = (self.ios / 'HEXMobile/KeyboardSetup.swift').read_text()
        self.assertIn('"com.bearylabs.hex.keyboard"', setup)

    def test_fails_closed_when_upstream_identity_changes(self):
        project = self.ios / 'project.yml'
        project.write_text(project.read_text().replace('QC99C9JE59', 'NEWTEAM123'))
        with self.assertRaises(ValueError):
            identity.apply(self.ios, self.config, TEAM)

    def test_rejects_invalid_team(self):
        with self.assertRaises(ValueError):
            identity.apply(self.ios, self.config, 'bad\nTEAM')


class ScopeTests(unittest.TestCase):
    """scope.sh: feature PRs touch only ios/ and HEXPLUS.md; Hex+ automation needs the infra label."""

    def run_scope(self, files, labels='', head_ref='feature/x'):
        with tempfile.TemporaryDirectory() as tmp:
            git = ['git', '-C', tmp, '-c', 'user.name=t', '-c', 'user.email=t@t']
            subprocess.run(git[:3] + ['init', '-q'], check=True)
            subprocess.run(git + ['commit', '-q', '--allow-empty', '-m', 'base'], check=True)
            for name in files:
                path = Path(tmp, name)
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text('x')
            subprocess.run(git + ['add', '-A'], check=True)
            subprocess.run(git + ['commit', '-q', '-m', 'change'], check=True)
            return subprocess.run(['bash', str(HERE / 'scope.sh'), 'HEAD~1', 'HEAD'], cwd=tmp,
                                  env={'PATH': '/usr/bin:/bin', 'LABELS': labels, 'HEAD_REF': head_ref},
                                  capture_output=True, text=True).returncode

    def test_ios_and_notes_pass(self):
        self.assertEqual(self.run_scope(['ios/HEXShared/A.swift', 'HEXPLUS.md']), 0)

    def test_automation_needs_infra_label(self):
        self.assertEqual(self.run_scope(['.github/hexplus/build.sh']), 1)
        self.assertEqual(self.run_scope(['.github/workflows/hexplus-ci.yml'], 'feature,infra'), 0)

    def test_everything_else_fails(self):
        self.assertEqual(self.run_scope(['src/main.rs']), 1)
        self.assertEqual(self.run_scope(['.github/workflows/release.yml'], 'infra'), 1)

    def test_upstream_pr_may_change_upstream_files_but_not_hexplus_automation(self):
        self.assertEqual(self.run_scope(['src/main.rs', 'ios/A.swift'], head_ref='upstream-pr/12'), 0)
        self.assertEqual(self.run_scope(['src/main.rs', '.github/hexplus/x.sh'], head_ref='upstream-pr/12'), 1)


if __name__ == '__main__':
    unittest.main()
