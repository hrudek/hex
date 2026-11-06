"""Workflow scheduling contracts: no macOS simulator in PRs, manual previews remain."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[3]
SOURCE = (ROOT / '.github/workflows/hexplus-ci.yml').read_text()


def job(name):
    return re.split(r'\n  \S', SOURCE.split(f'\n  {name}:\n', 1)[1], maxsplit=1)[0]


def condition(name, event, distribution='', changed='true', only_testing='', draft=False):
    # Evaluate the actual single-line scheduling expression, not a copied policy.
    expression = re.search(r'^    if: (.+)$', job(name), re.M).group(1)
    values = {
        'github.event_name': event,
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

    def test_post_merge_and_sync_keep_tests_and_device_builds(self):
        # Both hex-plus and sync/upstream use push events; the gate stays strict.
        self.assertTrue(condition('test', 'push'))
        self.assertTrue(condition('build', 'push'))
        self.assertFalse(condition('test', 'push', changed='false'))
        self.assertFalse(condition('build', 'push', changed='false'))
        self.assertIn("needs.test.result == 'success' && needs.build.result == 'success'",
                      job('sync-gate'))
        self.assertIn('needs: [decide, build]', job('sign'))

    def test_nightly_and_manual_preview_do_not_build_device_archive(self):
        self.assertTrue(condition('test', 'schedule'))
        self.assertFalse(condition('build', 'schedule'))
        self.assertTrue(condition('test', 'workflow_dispatch', 'simulator'))
        self.assertFalse(condition('build', 'workflow_dispatch', 'simulator'))
        self.assertFalse(condition('test', 'workflow_dispatch', 'simulator', only_testing='none'))
        self.assertIn('unsigned|simulator) ;;', job('decide'))

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
        self.assertIn("contains(needs.*.result, 'cancelled') && 'cancelled'", job('notify-fix'))


if __name__ == '__main__':
    unittest.main()
