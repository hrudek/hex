"""No repair or conflict agent runs in CI: red runs and conflicts are reported and fixed locally."""
import importlib.util
import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[3]
WORKFLOWS = ROOT / '.github/workflows'
spec = importlib.util.spec_from_file_location('status', ROOT / '.github/hexplus/status.py')
status = importlib.util.module_from_spec(spec)
spec.loader.exec_module(status)


def run(conclusion, state='completed'):
    return {'status': state, 'conclusion': conclusion, 'url': 'https://example.test/run', 'displayTitle': 'Merge'}


class StatusReportsRedRuns(unittest.TestCase):
    def test_green_or_running_needs_nothing(self):
        self.assertEqual(status.red_runs(run('success'), run('success'), run('success')), [])
        self.assertEqual(status.red_runs(run(None, 'in_progress'), None, None), [])
        self.assertEqual(status.red_runs(None, None, None), [])

    def test_each_red_run_needs_the_owner(self):
        items = status.red_runs(run('failure'), run('failure'), run('failure'))
        self.assertEqual(len(items), 3)
        self.assertIn('hex-plus CI failed', items[0])
        self.assertIn('fix/<name>', items[0])
        self.assertIn('Upstream sync failed', items[1])
        self.assertIn('sync/upstream CI failed', items[2])

    def test_cancelled_is_not_red(self):
        self.assertEqual(status.red_runs(run('cancelled'), None, None), [])


class NoRepairAgents(unittest.TestCase):
    def test_fix_and_conflict_workflows_are_gone(self):
        for name in ('hexplus-fix.yml', 'hexplus-conflicts.yml', 'hexplus-agent.yml'):
            self.assertFalse((WORKFLOWS / name).exists(), name)
        for name in ('conflicts.py', 'fix-triage.py'):
            self.assertFalse((ROOT / '.github/hexplus' / name).exists(), name)

    def test_only_the_review_uses_claude(self):
        users = sorted(p.name for p in WORKFLOWS.glob('hexplus-*.yml')
                       if 'claude-code-action' in p.read_text())
        self.assertEqual(users, ['hexplus-review.yml'])

    def test_nothing_dispatches_a_removed_workflow(self):
        for path in [*WORKFLOWS.glob('hexplus-*.yml'), *(ROOT / '.github/hexplus').glob('*.py')]:
            text = path.read_text()
            self.assertNotIn('hexplus-fix', text, path.name)
            self.assertNotIn('hexplus-conflicts', text, path.name)

    def test_sync_keeps_a_locally_fixed_branch(self):
        sync = (WORKFLOWS / 'hexplus-sync.yml').read_text()
        self.assertIn("git config user.name 'hexplus-sync'", sync)
        self.assertIn('"$(git log -1 --format=%an FETCH_HEAD)" != hexplus-sync', sync)
        self.assertIn('--label conflict', sync)


if __name__ == '__main__':
    unittest.main()
