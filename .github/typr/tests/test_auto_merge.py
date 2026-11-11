import pathlib
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[3]
SOURCE = (ROOT / '.github/workflows/typr-auto-merge.yml').read_text()


class AutoMergeWorkflowTest(unittest.TestCase):
    def test_trusted_events_and_main_only(self):
        self.assertIn('pull_request_target:', SOURCE)
        self.assertIn('branches: [main]', SOURCE)
        self.assertIn('types: [opened, reopened, ready_for_review]', SOURCE)
        # Preserve an owner's manual opt-out when more commits arrive.
        self.assertNotIn('synchronize', SOURCE)

    def test_excludes_forks_and_drafts(self):
        self.assertIn(
            'github.event.pull_request.head.repo.full_name == github.repository',
            SOURCE)
        self.assertIn('!github.event.pull_request.draft', SOURCE)

    def test_no_pr_code_or_bypass(self):
        self.assertNotIn('uses:', SOURCE)
        self.assertNotIn('--admin', SOURCE)
        self.assertIn('permissions: {}', SOURCE)
        self.assertIn('contents: write', SOURCE)
        self.assertIn('pull-requests: write', SOURCE)
        self.assertIn(
            'gh pr merge "$PR" --auto --squash --match-head-commit "$HEAD_SHA"',
            SOURCE)
        self.assertIn('GH_TOKEN: ${{ github.token }}', SOURCE)


if __name__ == '__main__':
    unittest.main()
