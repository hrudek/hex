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

    def test_sync_files_and_runtime_references_are_gone(self):
        for name in ('hexplus-sync.yml', 'hexplus-gate.yml', 'hexplus-upstream-pr.yml'):
            self.assertFalse((WORKFLOWS / name).exists(), name)
        scripts = ROOT / '.github/hexplus'
        for name in ('verify-sync-run.py', 'ours.txt'):
            self.assertFalse((scripts / name).exists(), name)
        # Do not scan tests: negative assertions deliberately name removed inputs.
        paths = [*WORKFLOWS.glob('*.yml')]
        for pattern in ('*.py', '*.sh', '*.json'):
            paths.extend(scripts.glob(pattern))
        for path in paths:
            for removed in ('sync/upstream', 'upstream-pr', 'SYNC_TOKEN',
                            'hexplus-gate', 'hexplus-sync', 'verify-sync-run', 'ours.txt'):
                self.assertNotIn(removed, path.read_text(), str(path))


if __name__ == '__main__':
    unittest.main()
