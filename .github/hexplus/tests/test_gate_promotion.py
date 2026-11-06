"""Exercise the actual privileged inline gate against disposable local Git repos."""
import os
from pathlib import Path
import subprocess
import tempfile
import textwrap
import unittest

ROOT = Path(__file__).resolve().parents[3]
SOURCE = (ROOT / '.github/workflows/hexplus-gate.yml').read_text()
PROMOTE = textwrap.dedent(SOURCE.split('      - name: Fast-forward hex-plus\n', 1)[1]
                         .split('        run: |\n', 1)[1].split('      - name:', 1)[0])


class PromotionTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.repo = self.root / 'repo'
        self.repo.mkdir()
        self.git('init', '-q', '-b', 'hex-plus')
        self.git('config', 'user.name', 'test')
        self.git('config', 'user.email', 'test@example.invalid')
        self.commit('base.txt', 'base')
        self.base = self.git('rev-parse', 'HEAD')
        self.remote = self.root / 'origin.git'
        subprocess.run(['git', 'init', '--bare', '-q', str(self.remote)], check=True)
        self.git('remote', 'add', 'origin', str(self.remote))
        self.git('push', '-q', 'origin', 'HEAD:refs/heads/hex-plus')
        self.commit('ios/example.swift', 'upstream change')
        self.sha = self.git('rev-parse', 'HEAD')
        self.git('push', '-q', 'origin', 'HEAD:refs/heads/sync/upstream')
        self.git('reset', '--hard', self.base)
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        gh = self.bin / 'gh'
        gh.write_text('#!/bin/sh\nprintf "%s\\n" "$TEST_PR"\n')
        gh.chmod(0o755)

    def tearDown(self):
        self.tmp.cleanup()

    def git(self, *args):
        return subprocess.check_output(['git', '-C', str(self.repo), *args], text=True,
                                       stderr=subprocess.PIPE).strip()

    def commit(self, name, content):
        path = self.repo / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)
        self.git('add', '--', name)
        self.git('commit', '-q', '-m', content)

    def promote(self, pr='15'):
        output = self.root / 'output'
        env = {**os.environ, 'PATH': f'{self.bin}:' + os.environ['PATH'], 'HEAD_SHA': self.sha,
               'TEST_PR': pr, 'GITHUB_OUTPUT': str(output),
               'GITHUB_STEP_SUMMARY': str(self.root / 'summary')}
        result = subprocess.run(['bash', '-c', PROMOTE], cwd=self.repo, env=env,
                                capture_output=True, text=True)
        return result, output.read_text()

    def remote_head(self):
        return self.git('ls-remote', 'origin', 'refs/heads/hex-plus').split()[0]

    def test_green_current_sync_fast_forwards(self):
        result, output = self.promote()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('status=promoted', output)
        self.assertEqual(self.remote_head(), self.sha)

    def test_already_promoted_is_a_noop_even_after_pr_closes(self):
        self.git('reset', '--hard', self.sha)
        self.git('push', '-q', 'origin', 'HEAD:refs/heads/hex-plus')
        result, output = self.promote(pr='')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('status=current', output)
        self.assertEqual(self.remote_head(), self.sha)

    def test_no_open_pr_cannot_promote(self):
        result, _ = self.promote(pr='')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.remote_head(), self.base)

    def test_moved_sync_branch_cannot_promote_old_commit(self):
        self.git('push', '-q', '--force', 'origin', f'{self.base}:refs/heads/sync/upstream')
        result, output = self.promote()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('status=stale', output)
        self.assertEqual(self.remote_head(), self.base)

    def test_new_canonical_commit_is_not_overwritten(self):
        self.commit('new.txt', 'new Hex+ commit')
        canonical = self.git('rev-parse', 'HEAD')
        self.git('push', '-q', 'origin', 'HEAD:refs/heads/hex-plus')
        result, output = self.promote()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('status=diverged', output)
        self.assertEqual(self.remote_head(), canonical)

    def test_protected_control_files_cannot_be_promoted(self):
        for name in ('HEXPLUS.md', '.github/hexplus/x.py', '.github/workflows/hexplus-x.yml',
                     '.github/ISSUE_TEMPLATE/hexplus-x.yml'):
            with self.subTest(name=name):
                self.git('reset', '--hard', self.base)
                self.commit(name, 'changed control file')
                self.sha = self.git('rev-parse', 'HEAD')
                self.git('push', '-q', '--force', 'origin', 'HEAD:refs/heads/sync/upstream')
                self.git('reset', '--hard', self.base)
                result, output = self.promote()
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('status=protected', output)
                self.assertEqual(self.remote_head(), self.base)


if __name__ == '__main__':
    unittest.main()
