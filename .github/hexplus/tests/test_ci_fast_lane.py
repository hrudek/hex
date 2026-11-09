"""Workflow scheduling contracts: no macOS simulator in PRs, manual previews remain."""
import importlib.util
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[3]
SOURCE = (ROOT / '.github/workflows/hexplus-ci.yml').read_text()


def job(name):
    return re.split(r'\n  \S', SOURCE.split(f'\n  {name}:\n', 1)[1], maxsplit=1)[0]


def condition(name, event, distribution='', changed='true', only_testing='', draft=False,
              ref='refs/heads/hex-plus'):
    # Evaluate the actual single-line scheduling expression, not a copied policy.
    expression = re.search(r'^    if: (.+)$', job(name), re.M).group(1)
    values = {
        'github.event_name': event,
        'github.ref': ref,
        'inputs.distribution': distribution,
        'needs.decide.outputs.run': changed,
        'inputs.only_testing': only_testing,
        'github.event.pull_request.draft': draft,
    }
    for key, value in values.items():
        expression = expression.replace(key, repr(value))
    expression = expression.replace('&&', ' and ').replace('||', ' or ')
    expression = re.sub(r'!(?!=)', ' not ', expression)
    return eval(expression.strip(), {'__builtins__': {}}, {})


class FastLaneContracts(unittest.TestCase):
    def test_prs_only_build_device_archive(self):
        self.assertFalse(condition('test', 'pull_request'))
        self.assertTrue(condition('build', 'pull_request'))
        self.assertFalse(condition('build', 'pull_request', draft=True))
        self.assertFalse(condition('build', 'pull_request', changed='false'))

    def test_post_merge_keeps_tests_and_device_builds(self):
        self.assertTrue(condition('test', 'push'))
        self.assertTrue(condition('build', 'push'))
        self.assertFalse(condition('test', 'push', changed='false'))
        self.assertFalse(condition('build', 'push', changed='false'))
        self.assertIn('needs: [decide, build]', job('sign'))

    def test_only_status_is_scheduled_and_manual_preview_has_no_device_archive(self):
        workflows = ROOT / '.github/workflows'
        scheduled = sorted(p.name for p in workflows.glob('*.yml')
                           if re.search(r'^  schedule:', p.read_text(), re.M))
        self.assertEqual(scheduled, ['hexplus-status.yml'])
        status = (workflows / 'hexplus-status.yml').read_text()
        self.assertIn("cron: '17 6 * * 1'", status)
        self.assertIn("if: github.event_name == 'workflow_dispatch' || github.event_name == 'schedule'", status)
        self.assertTrue(condition('test', 'workflow_dispatch', 'simulator'))
        self.assertFalse(condition('build', 'workflow_dispatch', 'simulator'))
        self.assertFalse(condition('test', 'workflow_dispatch', 'simulator', only_testing='none'))
        self.assertIn('unsigned|simulator) ;;', job('decide'))

    def test_only_hex_plus_pushes_and_required_job_names_stay_stable(self):
        push = re.search(r'^  push:\n(.*?)(?=^  \S)', SOURCE, re.M | re.S).group(1)
        self.assertEqual(push.strip(), 'branches: [hex-plus]')
        spec = importlib.util.spec_from_file_location(
            'reuse', ROOT / '.github/hexplus/reuse-pr-archive.py')
        reuse = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(reuse)
        names = set()
        for key, expected in (('linux', 'Linux checks'), ('decide', 'Decide'),
                              ('build', 'Unsigned archive')):
            self.assertEqual(re.search(r'^    name: (.+)$', job(key), re.M).group(1), expected)
            names.add(expected)
        self.assertEqual(names, set(reuse.REQUIRED_JOBS))
        self.assertNotRegex(job('linux'), re.compile(r'^    if:', re.M))
        self.assertNotRegex(job('decide'), re.compile(r'^    if:', re.M))
        self.assertIn('python3 -m unittest discover -s ios/tools/dictation_log/tests -v', job('linux'))

    def test_manual_device_distributions_still_build(self):
        for distribution in ('unsigned', 'ad-hoc', 'testflight'):
            with self.subTest(distribution=distribution):
                self.assertTrue(condition('build', 'workflow_dispatch', distribution))

    def test_screenshots_are_manual_artifacts_not_pr_comments(self):
        simulator = job('test')
        self.assertIn("inputs.distribution == 'simulator' && !cancelled()", simulator)
        self.assertIn('SCENES: ${{ inputs.scenes }}', simulator)
        self.assertIn('name: hexplus-screenshots-${{ github.run_id }}', simulator)
        self.assertNotIn('\n  screenshots:\n', SOURCE)
        self.assertNotIn('contents: write', SOURCE)

    def test_tests_never_hold_up_testflight_and_no_repair_agent_runs(self):
        # TestFlight follows the archive alone; red tests are fixed locally afterwards.
        self.assertIn("if: needs.decide.outputs.sign != '' && needs.build.result == 'success'", job('sign'))
        self.assertNotIn('hexplus-fix', SOURCE)
        status = job('status')
        self.assertIn("&& github.ref == 'refs/heads/hex-plus'", status)
        self.assertIn('gh workflow run hexplus-status.yml --ref hex-plus', status)


if __name__ == '__main__':
    unittest.main()
