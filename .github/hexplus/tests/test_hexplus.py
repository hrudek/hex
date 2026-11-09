"""Linux-runnable checks for Hex+'s CI scripts: python3 -m unittest discover -s .github/hexplus/tests"""
import importlib.util
from pathlib import Path
import plistlib
import re
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
    """Check identity rewrites against the real committed ios/ tree."""

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
    """All paths may change; every .github/ change needs the infra label."""

    def run_scope(self, files, labels=''):
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
                                  env={'PATH': '/usr/bin:/bin', 'LABELS': labels},
                                  capture_output=True, text=True).returncode

    def test_non_automation_paths_pass(self):
        for path in ('ios/HEXShared/A.swift', 'HEXPLUS.md', 'README.md', 'src/main.rs'):
            with self.subTest(path=path):
                self.assertEqual(self.run_scope([path]), 0)

    def test_all_automation_needs_infra_label(self):
        for path in ('.github/hexplus/x.sh', '.github/workflows/x.yml',
                     '.github/ISSUE_TEMPLATE/x.yml', '.github/other.txt'):
            with self.subTest(path=path):
                self.assertEqual(self.run_scope([path]), 1)
                self.assertEqual(self.run_scope([path], 'feature,infra'), 0)

    def test_no_changes_pass(self):
        with tempfile.TemporaryDirectory() as tmp:
            subprocess.run(['git', 'init', '-q', tmp], check=True)
            subprocess.run(['git', '-C', tmp, '-c', 'user.name=t', '-c', 'user.email=t@t',
                            'commit', '-q', '--allow-empty', '-m', 'base'], check=True)
            result = subprocess.run(['bash', str(HERE / 'scope.sh'), 'HEAD', 'HEAD'], cwd=tmp,
                                    capture_output=True, text=True, check=True)
            self.assertIn('Scope OK (0 files)', result.stdout)


class ProjectPathsTests(unittest.TestCase):
    def test_project_paths_are_self_contained_and_exist(self):
        # Parse path keys anywhere, plus bare list entries in each sources block.
        # Keep this Linux check independent of PyYAML / XcodeGen.
        ios = REPO / 'ios'
        paths = []
        sources_indent = None
        for line in (ios / 'project.yml').read_text().splitlines():
            indent = len(line) - len(line.lstrip())
            stripped = line.strip()
            if not stripped or stripped.startswith('#'):
                continue
            if sources_indent is not None and indent <= sources_indent:
                sources_indent = None
            if stripped == 'sources:':
                sources_indent = indent
            match = re.match(r'(?:-\s+)?path:\s*(.+)$', stripped)
            if match:
                paths.append(match.group(1))
            elif sources_indent is not None:
                match = re.match(r'-\s+([^:]+)$', stripped)
                if match:
                    paths.append(match.group(1))
        self.assertGreater(len(paths), 0)
        self.assertIn('AppIcon.icon', paths)
        self.assertIn('TestFixtures/term-hex-1.wav', paths)
        for raw in paths:
            value = raw.strip('"\'')
            with self.subTest(path=value):
                self.assertNotIn('..', value)
                self.assertFalse(Path(value).is_absolute())
                self.assertTrue((ios / value).exists(), value)


class InfraLabelTests(unittest.TestCase):
    """Adding "infra" must approve without a manual close/reopen or a label-triggered macOS run."""
    WORKFLOWS = HERE.parent / 'workflows'

    def test_scope_reads_live_labels_not_the_event_payload(self):
        ci = (self.WORKFLOWS / 'hexplus-ci.yml').read_text()
        self.assertNotIn('github.event.pull_request.labels', ci)
        self.assertIn('gh api "repos/$GH_REPO/pulls/$PR"', ci)
        self.assertIn('pull-requests: read', ci)
        self.assertIn('types: [opened, synchronize, reopened, ready_for_review]', ci)

    def test_infra_label_reruns_failed_ci_without_running_pr_code(self):
        recheck = (self.WORKFLOWS / 'hexplus-recheck.yml').read_text()
        self.assertIn('types: [labeled]', recheck)
        self.assertIn("if: github.event.label.name == 'infra'", recheck)
        self.assertIn('gh run rerun "$id" --failed', recheck)
        self.assertNotIn('actions/checkout', recheck)


if __name__ == '__main__':
    unittest.main()
