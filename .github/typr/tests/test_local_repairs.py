"""No repair or conflict agent runs in CI: red runs and conflicts are reported and fixed locally."""
import importlib.util
import pathlib
import unittest
from unittest.mock import patch

ROOT = pathlib.Path(__file__).resolve().parents[3]
WORKFLOWS = ROOT / '.github/workflows'
spec = importlib.util.spec_from_file_location('status', ROOT / '.github/typr/status.py')
status = importlib.util.module_from_spec(spec)
spec.loader.exec_module(status)


def run(conclusion, state='completed'):
    return {'status': state, 'conclusion': conclusion, 'url': 'https://example.test/run', 'displayTitle': 'Merge'}


class StatusReportsRedRuns(unittest.TestCase):
    def test_green_or_running_needs_nothing(self):
        self.assertEqual(status.red_runs(run('success')), [])
        self.assertEqual(status.red_runs(run(None, 'in_progress')), [])
        self.assertEqual(status.red_runs(None), [])

    def test_each_red_run_needs_the_owner(self):
        items = status.red_runs(run('failure'))
        self.assertEqual(len(items), 1)
        self.assertIn('hex-plus CI failed', items[0])
        self.assertIn('fix/<name>', items[0])

    def test_cancelled_is_not_red(self):
        self.assertEqual(status.red_runs(run('cancelled')), [])


class StatusIssueMigration(unittest.TestCase):
    def test_reuses_legacy_issue_only_when_typr_issue_is_missing(self):
        legacy = {'number': 20, 'title': 'Hex+ status'}
        current = {'number': 21, 'title': 'Typr status'}
        for responses, expected in (([[current]], current), ([[], [legacy]], legacy),
                                    ([[], []], None)):
            with self.subTest(expected=expected), patch.object(status, 'gh_json', side_effect=responses):
                self.assertEqual(status.find_issue(), expected)

    def test_existing_issue_is_renamed_not_duplicated(self):
        with patch.dict(status.os.environ, {'GH_REPO': 'hrudek/typr'}), \
                patch.object(status, 'find_issue', return_value={'number': 20}), \
                patch.object(status, 'gh_json', return_value=[]), \
                patch.object(status, 'runs', return_value=[]), \
                patch.object(status, 'last_testflight', return_value='none'), \
                patch.object(status, 'gh') as gh, patch('builtins.print'):
            status.main()
            self.assertEqual(gh.call_count, 1)
            self.assertEqual(gh.call_args.args[:6],
                             ('issue', 'edit', '20', '--title', 'Typr status', '--body'))


class NoRepairAgents(unittest.TestCase):
    def test_fix_and_conflict_workflows_are_gone(self):
        for name in ('typr-fix.yml', 'typr-conflicts.yml', 'typr-agent.yml'):
            self.assertFalse((WORKFLOWS / name).exists(), name)
        for name in ('conflicts.py', 'fix-triage.py'):
            self.assertFalse((ROOT / '.github/typr' / name).exists(), name)

    def test_only_the_review_uses_claude(self):
        users = sorted(p.name for p in WORKFLOWS.glob('typr-*.yml')
                       if 'claude-code-action' in p.read_text())
        self.assertEqual(users, ['typr-review.yml'])

    def test_nothing_dispatches_a_removed_workflow(self):
        for path in [*WORKFLOWS.glob('typr-*.yml'), *(ROOT / '.github/typr').glob('*.py')]:
            text = path.read_text()
            self.assertNotIn('typr-fix', text, path.name)
            self.assertNotIn('typr-conflicts', text, path.name)

    def test_sync_files_and_runtime_references_are_gone(self):
        for name in ('typr-sync.yml', 'typr-gate.yml', 'typr-upstream-pr.yml'):
            self.assertFalse((WORKFLOWS / name).exists(), name)
        scripts = ROOT / '.github/typr'
        for name in ('verify-sync-run.py', 'ours.txt'):
            self.assertFalse((scripts / name).exists(), name)
        # Do not scan tests: negative assertions deliberately name removed inputs.
        paths = [*WORKFLOWS.glob('*.yml')]
        for pattern in ('*.py', '*.sh', '*.json'):
            paths.extend(scripts.glob(pattern))
        for path in paths:
            for removed in ('sync/upstream', 'upstream-pr', 'SYNC_TOKEN',
                            'typr-gate', 'typr-sync', 'verify-sync-run', 'ours.txt'):
                self.assertNotIn(removed, path.read_text(), str(path))


if __name__ == '__main__':
    unittest.main()
