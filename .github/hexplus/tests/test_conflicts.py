"""Automatic conflict routing and real local Git merges, without an agent/token."""
import copy
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_hexplus import module, REPO as ROOT

conflicts = module('hexplus_conflicts', 'conflicts.py')
triage = module('hexplus_conflict_triage', 'fix-triage.py')
REPO = 'hrudek/hex'


def pr_fixture():
    return {'number': 7, 'state': 'open', 'draft': False, 'mergeable': False,
            'labels': [], 'html_url': 'https://example/pr/7',
            'head': {'ref': 'feature/example', 'sha': 'a' * 40, 'repo': {'full_name': REPO}},
            'base': {'ref': 'hex-plus', 'sha': 'b' * 40, 'repo': {'full_name': REPO}}}


class PolicyTests(unittest.TestCase):
    def test_only_owned_eligible_prs_and_conflict_drafts(self):
        pr = pr_fixture()
        self.assertTrue(conflicts.eligible(pr, REPO))
        for change in ({'state': 'closed'}, {'draft': True},
                       {'labels': [{'name': 'needs-human'}]}, {'labels': [{'name': 'infra'}]},
                       {'head': {**pr['head'], 'repo': None}},
                       {'head': {**pr['head'], 'repo': {'full_name': 'other/repo'}}},
                       {'head': {**pr['head'], 'ref': 'production'}},
                       {'base': {**pr['base'], 'ref': 'dev'}}):
            with self.subTest(change=change):
                self.assertFalse(conflicts.eligible({**pr, **change}, REPO))
        self.assertTrue(conflicts.eligible({**pr, 'draft': True,
                                           'labels': [{'name': 'conflict'}]}, REPO))

    def test_conflict_dispatch_uses_linux_and_exhausted_budget_stops(self):
        pr = pr_fixture()
        pr['labels'] = [{'name': 'conflict'}]
        issue = {'number': 8, 'labels': []}
        for exhausted in (False, True):
            outputs = []
            with self.subTest(exhausted=exhausted), tempfile.TemporaryDirectory() as tmp, \
                    patch.dict(os.environ, {'GH_REPO': REPO, 'GITHUB_EVENT_NAME': 'workflow_dispatch',
                                            'CONFLICT_PR': '7', 'RUN_ID': '', 'RUNNER_TEMP': tmp}), \
                    patch.object(triage, 'gh_json', return_value=pr), \
                    patch.object(triage, 'ensure_incident', return_value=issue), \
                    patch.object(triage, 'attempt_comments', side_effect=[
                        [1, 2, 3] if exhausted else [], []]), \
                    patch.object(triage, 'gh') as gh, patch.object(triage, 'summary'), \
                    patch.object(triage, 'output', side_effect=lambda **kw: outputs.append(kw)):
                if exhausted:
                    with self.assertRaises(SystemExit):
                        triage.main()
                    self.assertTrue(any('needs-human' in call.args for call in gh.call_args_list))
                else:
                    triage.main()
                    self.assertEqual(outputs[-1]['conflict'], 'true')
                    self.assertEqual(outputs[-1]['model'], 'opus')
                    self.assertEqual(outputs[-1]['work'], 'feature/example')

    def test_foreign_conflict_dispatch_is_rejected_before_agent_or_incident(self):
        pr = pr_fixture()
        pr['labels'] = [{'name': 'conflict'}]
        pr['head']['repo'] = {'full_name': 'other/repo'}
        with patch.dict(os.environ, {'GH_REPO': REPO, 'GITHUB_EVENT_NAME': 'workflow_dispatch',
                                    'CONFLICT_PR': '7', 'RUN_ID': ''}), \
                patch.object(triage, 'gh_json', return_value=pr), \
                patch.object(triage, 'ensure_incident') as incident, \
                patch.object(triage, 'output'), patch.object(triage, 'summary'), \
                self.assertRaises(SystemExit):
            triage.main()
        incident.assert_not_called()

    def test_workflow_keeps_agent_and_owner_token_separate(self):
        monitor = (ROOT / '.github/workflows/hexplus-conflicts.yml').read_text()
        self.assertIn('ref: hex-plus', monitor)
        self.assertIn('runs-on: ubuntu-latest', monitor)
        self.assertNotIn('claude-code-action', monitor)
        self.assertNotIn('claude_code_oauth_token', monitor)
        resolver = (ROOT / '.github/workflows/hexplus-fix.yml').read_text()
        agent = resolver.split('  fix:\n', 1)[1].split('  push:\n', 1)[0]
        self.assertNotIn('secrets.SYNC_TOKEN', agent)
        self.assertIn("needs.triage.outputs.conflict == 'true' && 'ubuntu-latest'", agent)
        self.assertIn('git add -A -- ios/', agent)
        self.assertIn('Conflict markers remain; refusing patch.', agent)


class MergeTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.old_cwd = Path.cwd()
        root = Path(self.tmp.name)
        self.remote = root / 'remote.git'
        self.work = root / 'work'
        self.work.mkdir()
        os.chdir(self.work)
        self.git('init', '-q', '--initial-branch=hex-plus')
        self.git('config', 'user.name', 'test')
        self.git('config', 'user.email', 'test@example.invalid')
        self.write('ios/File.swift', 'let value = 0\n')
        self.git('add', '.')
        self.git('commit', '-qm', 'initial')
        self.git('branch', 'feature/example')
        self.env = patch.dict(os.environ, {'GH_REPO': REPO})
        self.env.start()
        self.addCleanup(self.cleanup)

    def cleanup(self):
        self.env.stop()
        os.chdir(self.old_cwd)
        self.tmp.cleanup()

    def git(self, *args):
        return subprocess.check_output(['git', *args], text=True, stderr=subprocess.DEVNULL).strip()

    def write(self, path, text):
        target = Path(path)
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(text)

    def setup_divergence(self, path='ios/File.swift'):
        self.write(path, 'upstream\n')
        self.git('add', '.')
        self.git('commit', '-qm', 'base changed')
        base = self.git('rev-parse', 'HEAD')
        self.git('checkout', '-q', 'feature/example')
        self.write(path, 'feature\n')
        self.git('add', '.')
        self.git('commit', '-qm', 'feature changed')
        head = self.git('rev-parse', 'HEAD')
        self.git('clone', '-q', '--bare', '.', str(self.remote))
        self.git('remote', 'add', 'origin', str(self.remote))
        pr = pr_fixture()
        pr['head']['sha'], pr['base']['sha'] = head, base
        return pr

    def run_process(self, pr, updated=None, busy=False):
        def gh(*args):
            if args[:2] == ('run', 'list'):
                return json.dumps([{'displayTitle': 'Hex+ fix · feature/example · conflict',
                                    'status': 'in_progress'}] if busy else [])
            return ''
        with patch.object(conflicts, 'api', side_effect=[pr, updated or pr]), \
                patch.object(conflicts, 'gh', side_effect=gh) as mock:
            conflicts.process(pr)
        return mock

    def test_text_conflict_is_committed_and_dispatched_without_losing_ancestry(self):
        pr = self.setup_divergence()
        gh = self.run_process(pr)
        self.assertIn('<<<<<<<', Path('ios/File.swift').read_text())
        parents = self.git('show', '-s', '--format=%P', 'HEAD').split()
        self.assertEqual(parents, [pr['head']['sha'], pr['base']['sha']])
        self.assertTrue(any(call.args[:2] == ('workflow', 'run') for call in gh.call_args_list))
        self.assertEqual(self.git('--git-dir=' + str(self.remote), 'rev-parse', 'feature/example'),
                         self.git('rev-parse', 'HEAD'))

    def test_control_conflicts_escalate_without_pushing_or_agent(self):
        pr = self.setup_divergence('.github/workflows/hexplus-example.yml')
        gh = self.run_process(pr)
        self.assertTrue(any('needs-human' in call.args for call in gh.call_args_list))
        self.assertFalse(any(call.args[:2] == ('workflow', 'run') for call in gh.call_args_list))
        self.assertEqual(self.git('--git-dir=' + str(self.remote), 'rev-parse', 'feature/example'),
                         pr['head']['sha'])

    def test_modify_delete_conflict_escalates_without_choosing_a_side(self):
        pr = self.setup_divergence()
        self.git('rm', '-q', 'ios/File.swift')
        self.git('commit', '-qm', 'delete on feature')
        self.git('push', '-q', 'origin', 'feature/example')
        pr['head']['sha'] = self.git('rev-parse', 'HEAD')
        gh = self.run_process(pr)
        self.assertTrue(any('needs-human' in call.args for call in gh.call_args_list))
        self.assertFalse(any(call.args[:2] == ('workflow', 'run') for call in gh.call_args_list))
        self.assertEqual(self.git('--git-dir=' + str(self.remote), 'rev-parse', 'feature/example'),
                         pr['head']['sha'])

    def test_concurrent_push_prevents_publication(self):
        pr = self.setup_divergence()
        moved = copy.deepcopy(pr)
        moved['head']['sha'] = 'c' * 40
        gh = self.run_process(pr, moved)
        self.assertFalse(any(call.args[:2] == ('workflow', 'run') for call in gh.call_args_list))
        self.assertEqual(self.git('--git-dir=' + str(self.remote), 'rev-parse', 'feature/example'),
                         pr['head']['sha'])

    def test_existing_resolver_is_not_queued_twice(self):
        pr = self.setup_divergence()
        gh = self.run_process(pr, busy=True)
        self.assertFalse(any(call.args[:2] == ('workflow', 'run') for call in gh.call_args_list))

    def test_resolved_conflict_label_is_removed_and_draft_readied(self):
        pr = self.setup_divergence()
        # A previous manual/agent resolution already includes the base.
        self.git('merge', '-s', 'ours', '--no-ff', '-m', 'resolved', pr['base']['sha'])
        pr['head']['sha'] = self.git('rev-parse', 'HEAD')
        self.git('push', '-q', 'origin', 'feature/example')
        pr.update(draft=True, labels=[{'name': 'conflict'}], mergeable=True)
        gh = self.run_process(pr)
        self.assertIn(('pr', 'ready', '7'), [call.args for call in gh.call_args_list])
        self.assertIn(('pr', 'edit', '7', '--remove-label', 'conflict'),
                      [call.args for call in gh.call_args_list])


if __name__ == '__main__':
    unittest.main()
