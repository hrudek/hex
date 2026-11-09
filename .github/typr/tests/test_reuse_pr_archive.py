"""Archive reuse checks, runnable without Xcode, credentials or a live PR."""
import copy
import hashlib
import io
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_typr import config_module, module

reuse = module('typr_reuse', 'reuse-pr-archive.py')
REPO = 'hrudek/typr'
SHA = 'a' * 40


class ReuseTests(unittest.TestCase):
    def setUp(self):
        self.config = config_module.load()
        self.pr = {
            'state': 'open', 'draft': False,
            'base': {'repo': {'full_name': REPO}, 'ref': 'hex-plus'},
            'head': {'repo': {'full_name': REPO}, 'ref': 'feature/example', 'sha': SHA},
        }
        self.run = {
            'id': 123, 'repository': {'full_name': REPO}, 'head_repository': {'full_name': REPO},
            'event': 'pull_request', 'path': '.github/workflows/typr-ci.yml',
            'head_sha': SHA, 'head_branch': 'feature/example',
            'status': 'completed', 'conclusion': 'success',
        }
        self.jobs = [{'name': name, 'conclusion': 'success'} for name in reuse.REQUIRED_JOBS]
        self.artifact = {
            'id': 456, 'name': 'typr-unsigned-123', 'expired': False,
            'workflow_run': {'id': 123, 'head_sha': SHA}, 'digest': 'sha256:' + 'b' * 64,
        }
        self.metadata = {'source_sha': SHA, 'workflow_sha': 'c' * 40,
                         'run': '123', 'app': self.config}

    def test_current_successful_feature_pr(self):
        reuse.validate_pr(self.pr, REPO)
        reuse.validate_run(self.run, self.pr, REPO)
        reuse.validate_jobs(self.jobs)
        self.assertEqual(reuse.validate_artifact([self.artifact], self.run), self.artifact)
        reuse.validate_metadata(self.metadata, self.run, self.config)

    def test_rejects_draft_closed_foreign_wrong_base_and_nonfeature_pr(self):
        for change in (
            {'draft': True}, {'state': 'closed'},
            {'base': {'repo': {'full_name': REPO}, 'ref': 'dev'}},
            {'base': {'repo': {'full_name': 'other/hex'}, 'ref': 'hex-plus'}},
            {'head': {**self.pr['head'], 'repo': {'full_name': 'other/hex'}}},
            {'head': {**self.pr['head'], 'repo': None}},
            {'head': {**self.pr['head'], 'ref': 'infra/x'}},
        ):
            with self.subTest(change=change), self.assertRaises(ValueError):
                reuse.validate_pr({**self.pr, **change}, REPO)

    def test_rejects_wrong_run_stale_commit_and_cancelled_or_queued_ci(self):
        for change in (
            {'event': 'push'}, {'event': 'workflow_dispatch'},
            {'path': '.github/workflows/other.yml'}, {'head_sha': 'd' * 40},
            {'head_branch': 'feature/other'}, {'status': 'queued'},
            {'status': 'waiting'}, {'conclusion': 'cancelled'},
            {'conclusion': 'timed_out'}, {'conclusion': 'action_required'},
            {'head_repository': {'full_name': 'other/hex'}},
            {'repository': {'full_name': 'other/hex'}},
        ):
            with self.subTest(change=change), self.assertRaises(ValueError):
                reuse.validate_run({**self.run, **change}, self.pr, REPO)

    def test_tests_do_not_gate_archive_reuse(self):
        self.assertEqual(reuse.REQUIRED_JOBS, ('Linux checks', 'Decide', 'Unsigned archive'))
        for status, conclusion in (('in_progress', None), ('completed', 'failure'),
                                   ('completed', 'success')):
            for test_result in (None, 'failure', 'cancelled', 'skipped', 'success'):
                with self.subTest(status=status, conclusion=conclusion, tests=test_result):
                    run = {**self.run, 'status': status, 'conclusion': conclusion}
                    reuse.validate_run(run, self.pr, REPO)
                    reuse.validate_jobs(self.jobs + [
                        {'name': 'Simulator tests', 'conclusion': test_result}])
                    reuse.validate_jobs(self.jobs)  # Tests need not have started yet.

    def test_every_required_job_must_run_and_pass(self):
        for index in range(len(self.jobs)):
            for result in ('skipped', 'cancelled', 'failure', None):
                jobs = copy.deepcopy(self.jobs)
                jobs[index]['conclusion'] = result
                with self.subTest(job=index, result=result), self.assertRaises(ValueError):
                    reuse.validate_jobs(jobs)
            with self.assertRaises(ValueError):
                reuse.validate_jobs(self.jobs[:index] + self.jobs[index + 1:])
        with self.assertRaises(ValueError):
            reuse.validate_jobs(self.jobs + self.jobs[:1])

    def test_expired_missing_duplicate_and_unbound_artifacts_fail(self):
        for items in (
            [], [self.artifact, self.artifact],
            [{**self.artifact, 'expired': True}],
            [{**self.artifact, 'digest': None}],
            [{**self.artifact, 'workflow_run': {'id': 999, 'head_sha': SHA}}],
            [{**self.artifact, 'workflow_run': {'id': 123, 'head_sha': 'd' * 40}}],
        ):
            with self.subTest(items=items), self.assertRaises(ValueError):
                reuse.validate_artifact(items, self.run)

    def test_metadata_must_match_run_commit_and_trusted_identity(self):
        for change in ({'source_sha': 'd' * 40}, {'run': '999'},
                       {'app': {}}, {'workflow_sha': None}):
            with self.subTest(change=change), self.assertRaises(ValueError):
                reuse.validate_metadata({**self.metadata, **change}, self.run, self.config)

    def artifact_zip(self, extra=None, metadata=None, symlink=False):
        data = io.BytesIO()
        with zipfile.ZipFile(data, 'w') as archive:
            archive.writestr('build.json', json.dumps(metadata or self.metadata))
            entry = zipfile.ZipInfo('archive.zip.age')
            if symlink:
                entry.create_system = 3
                entry.external_attr = 0o120777 << 16
            archive.writestr(entry, b'encrypted archive')
            if extra:
                archive.writestr(extra, 'unexpected')
        return data.getvalue()

    def unpack(self, data, digest=None):
        artifact = {**self.artifact, 'digest': digest or 'sha256:' + hashlib.sha256(data).hexdigest()}
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp, 'artifact.zip')
            path.write_bytes(data)
            destination = Path(tmp, 'input')
            reuse.unpack_artifact(path, destination, artifact, self.run, self.config)
            return {item.name: item.read_bytes() for item in destination.iterdir()}

    def test_download_is_digest_checked_and_only_exact_files_are_unpacked(self):
        files = self.unpack(self.artifact_zip())
        self.assertEqual(set(files), {'archive.zip.age', 'build.json'})
        self.assertEqual(files['archive.zip.age'], b'encrypted archive')
        with self.assertRaises(ValueError):
            self.unpack(self.artifact_zip(), 'sha256:' + '0' * 64)
        for extra in ('../escape', 'script.sh', '/absolute'):
            with self.subTest(extra=extra), self.assertRaises(ValueError):
                self.unpack(self.artifact_zip(extra=extra))
        with self.assertRaises(ValueError):
            self.unpack(self.artifact_zip(symlink=True))
        with self.assertRaises(ValueError):
            self.unpack(self.artifact_zip(metadata={**self.metadata, 'run': '999'}))

    def run_main(self, args, api_results, page_results, download=None):
        with patch.object(sys, 'argv', ['reuse-pr-archive.py', *args]), \
                patch.dict(os.environ, {'GITHUB_REPOSITORY': REPO}, clear=True), \
                patch.object(reuse, 'api', side_effect=api_results), \
                patch.object(reuse, 'pages', side_effect=page_results), \
                patch.object(reuse, 'unpack_artifact'), \
                patch.object(reuse.subprocess, 'run', side_effect=download), \
                patch('builtins.print'):
            reuse.main()

    def test_select_does_not_fall_back_to_older_successful_run(self):
        failed = {**self.run, 'id': 124, 'conclusion': 'failure'}
        jobs = copy.deepcopy(self.jobs)
        jobs[-1]['conclusion'] = 'failure'
        with self.assertRaisesRegex(ValueError, 'Unsigned archive must be successful'):
            self.run_main(['--pr', '7'], [self.pr], [[self.run, failed], jobs])
        self.run_main(['--pr', '7'], [self.pr], [[self.run], self.jobs, [self.artifact]])

    def test_select_accepts_running_or_test_failed_ci_with_passing_archive(self):
        for status, conclusion in (('in_progress', None), ('completed', 'failure')):
            with self.subTest(status=status):
                run = {**self.run, 'status': status, 'conclusion': conclusion}
                jobs = self.jobs + [{'name': 'Simulator tests', 'conclusion': conclusion}]
                self.run_main(['--pr', '7'], [self.pr], [[run], jobs, [self.artifact]])

    def test_revalidation_rejects_push_while_waiting_for_approval(self):
        moved = {**self.pr, 'head': {**self.pr['head'], 'sha': 'd' * 40}}
        with self.assertRaisesRegex(ValueError, 'PR changed'):
            self.run_main(['--pr', '7', '--run', '123'], [moved, self.run], [])

    def test_revalidation_rejects_push_during_download(self):
        moved = {**self.pr, 'head': {**self.pr['head'], 'sha': 'd' * 40}}
        with tempfile.TemporaryDirectory() as tmp:
            with self.assertRaisesRegex(ValueError, 'PR changed'):
                self.run_main(['--pr', '7', '--run', '123', '--download', tmp],
                              [self.pr, self.run, moved], [self.jobs, [self.artifact]])
            self.assertFalse(Path(tmp, 'github-artifact.zip').exists())

    def test_api_pagination_does_not_drop_later_jobs_or_artifacts(self):
        with patch.object(reuse, 'api', side_effect=[{'jobs': list(range(100))}, {'jobs': [100]}]) as api:
            self.assertEqual(len(reuse.pages(REPO, 'actions/runs/123/jobs?filter=latest', 'jobs')), 101)
            self.assertIn('&per_page=100&page=2', api.call_args.args[1])


if __name__ == '__main__':
    unittest.main()
