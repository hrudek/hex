"""Read-only sync verification and workflow safety contracts (no GitHub secrets)."""
import copy
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_hexplus import module, REPO as ROOT

verify = module('hexplus_verify_sync', 'verify-sync-run.py')
REPO = 'hrudek/hex'


class VerifySyncTests(unittest.TestCase):
    def setUp(self):
        self.run = {
            'id': 42, 'repository': {'full_name': REPO}, 'head_repository': {'full_name': REPO},
            'event': 'push', 'head_branch': 'sync/upstream', 'head_sha': 'a' * 40,
            'path': '.github/workflows/hexplus-ci.yml', 'status': 'completed', 'conclusion': 'success',
        }
        self.jobs = [{'name': name, 'conclusion': 'success'} for name in
                     ('Linux checks', 'Decide', 'Simulator tests', 'Unsigned archive')]

    def test_current_sync_run_and_successful_jobs(self):
        verify.validate_run(self.run, REPO)
        verify.validate_jobs(self.jobs)
        with patch.object(verify, 'api', side_effect=[self.run, {'jobs': self.jobs}]):
            self.assertEqual(verify.verify(REPO, '42'), self.run)

    def test_only_same_repo_sync_pushes_from_expected_workflow(self):
        for change in (
            {'repository': {'full_name': 'other/hex'}},
            {'head_repository': {'full_name': 'other/hex'}},
            {'event': 'pull_request'}, {'event': 'workflow_dispatch'},
            {'head_branch': 'feature/something'}, {'head_sha': 'not-a-sha'},
            {'path': '.github/workflows/other.yml'},
        ):
            with self.subTest(change=change), self.assertRaises(ValueError):
                verify.validate_run({**self.run, **change}, REPO)

    def test_no_app_changes_can_skip_both_expensive_jobs_only(self):
        jobs = copy.deepcopy(self.jobs)
        jobs[2]['conclusion'] = jobs[3]['conclusion'] = 'skipped'
        verify.validate_jobs(jobs)
        for index in range(4):
            for conclusion in ('failure', 'cancelled', None):
                changed = copy.deepcopy(jobs)
                changed[index]['conclusion'] = conclusion
                with self.subTest(index=index, conclusion=conclusion), self.assertRaises(ValueError):
                    verify.validate_jobs(changed)
        for index in (0, 1, 2, 3):
            changed = copy.deepcopy(self.jobs)
            changed[index]['conclusion'] = 'skipped'
            with self.assertRaises(ValueError):
                verify.validate_jobs(changed)
        with self.assertRaises(ValueError):
            verify.validate_jobs(self.jobs[:-1])
        with self.assertRaises(ValueError):
            verify.validate_jobs(self.jobs + self.jobs[:1])

    def test_failed_cancelled_or_approval_required_runs_do_not_promote(self):
        for result in ('failure', 'cancelled', 'action_required', 'skipped'):
            with patch.object(verify, 'api', return_value={**self.run, 'conclusion': result}), \
                    self.subTest(result=result), self.assertRaises(ValueError):
                verify.verify(REPO, '42')

    def test_dispatch_waits_for_requesting_ci_to_finish(self):
        running = {**self.run, 'status': 'in_progress', 'conclusion': None}
        with patch.object(verify, 'api', side_effect=[running, self.run, {'jobs': self.jobs}]), \
                patch.object(verify.time, 'sleep') as sleep:
            self.assertEqual(verify.verify(REPO, '42'), self.run)
            sleep.assert_called_once_with(10)

    def test_wait_has_a_deadline(self):
        running = {**self.run, 'status': 'in_progress', 'conclusion': None}
        with patch.object(verify, 'api', return_value=running), \
                patch.object(verify.time, 'sleep') as sleep, self.assertRaisesRegex(ValueError, 'five minutes'):
            verify.verify(REPO, '42')
        self.assertEqual(sleep.call_count, 30)

    def test_jobs_are_paginated(self):
        unrelated = [{'name': f'other-{n}', 'conclusion': 'success'} for n in range(100)]
        with patch.object(verify, 'api', side_effect=[self.run, {'jobs': unrelated}, {'jobs': self.jobs}]) as api:
            verify.verify(REPO, '42')
            self.assertIn('page=2', api.call_args.args[1])

    def test_invalid_ids_never_reach_api(self):
        for run_id in ('', '-1', '1; echo bad', 'other/run', '0'):
            with patch.object(verify, 'api') as api, self.assertRaises(ValueError):
                verify.verify(REPO, run_id)
            api.assert_not_called()


class WorkflowContracts(unittest.TestCase):
    def test_sync_pr_creation_uses_owner_token(self):
        source = (ROOT / '.github/workflows/hexplus-sync.yml').read_text()
        step = source.split('      - name: Open or update the sync PR\n', 1)[1].split('      - name:', 1)[0]
        self.assertIn('GH_TOKEN: ${{ secrets.SYNC_TOKEN }}', step)

    def test_gate_only_checks_out_canonical_control_code(self):
        source = (ROOT / '.github/workflows/hexplus-gate.yml').read_text()
        self.assertEqual(source.count('ref: hex-plus'), 2)
        verifier, promotion = source.split('  promote:\n', 1)
        self.assertNotIn('secrets.', verifier)
        self.assertIn('needs: verify', promotion)
        self.assertNotIn('python3', promotion)
        self.assertIn('git merge-base --is-ancestor HEAD "$HEAD_SHA"', promotion)
        self.assertIn('git diff --name-only HEAD "$HEAD_SHA" -- HEXPLUS.md .github/hexplus', promotion)
        self.assertIn('status=current', promotion)

    def test_ci_dispatch_has_no_secrets_or_checkout(self):
        source = (ROOT / '.github/workflows/hexplus-ci.yml').read_text().split('  sync-gate:\n', 1)[1]
        self.assertNotIn('secrets.', source)
        self.assertNotIn('uses: actions/checkout', source)
        self.assertIn("github.ref == 'refs/heads/sync/upstream'", source)
        self.assertIn("needs.test.result == 'success' && needs.build.result == 'success'", source)
        self.assertIn('gh workflow run hexplus-gate.yml --ref hex-plus', source)


if __name__ == '__main__':
    unittest.main()
