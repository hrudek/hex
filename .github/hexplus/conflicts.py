#!/usr/bin/env python3
"""Trusted Linux conflict coordinator: git/gh only, no branch code is executed."""
import json
import os
import re
import subprocess
import time

MARKERS = r'^(<<<<<<< |=======$|>>>>>>> )'


def command(*args, check=True):
    return subprocess.run(args, check=check, text=True, capture_output=True)


def gh(*args):
    return command('gh', *args).stdout


def api(endpoint):
    return json.loads(gh('api', f'repos/{os.environ["GH_REPO"]}/{endpoint}'))


def eligible(pr, repo):
    branch = pr['head']['ref']
    labels = {label['name'] for label in pr['labels']}
    return (pr['state'] == 'open' and pr['base']['ref'] == 'hex-plus'
            and pr['base']['repo']['full_name'] == repo
            and (pr['head'].get('repo') or {}).get('full_name') == repo
            and 'needs-human' not in labels and 'infra' not in labels
            and (not pr['draft'] or 'conflict' in labels)
            and (branch == 'sync/upstream'
                 or branch.startswith(('feature/', 'upstream-pr/', 'fix/ci-'))))


def markers():
    result = command('git', 'grep', '-I', '-l', '-E', MARKERS, '--', '.', check=False)
    if result.returncode not in (0, 1):
        raise RuntimeError(result.stderr)
    return result.stdout.splitlines()


def settled(pr, attempts=12, delay=5):
    """GitHub computes mergeability after a push to hex-plus; wait for it (no schedule rescans)."""
    for _ in range(attempts):
        if pr['mergeable'] is not None:
            break
        time.sleep(delay)
        pr = api(f'pulls/{pr["number"]}')
    return pr


def needs_human(pr, paths):
    gh('pr', 'edit', str(pr['number']), '--add-label', 'needs-human')
    gh('pr', 'comment', str(pr['number']), '--body',
       'Automatic Linux conflict repair stopped: protected/non-iOS or non-text conflicts require review.\n\n'
       + '\n'.join(f'- `{path}`' for path in paths))


def process(pr):
    repo = os.environ['GH_REPO']
    number = str(pr['number'])
    if not eligible(pr, repo):
        return
    labels = {label['name'] for label in pr['labels']}
    if 'conflict' not in labels:
        pr = settled(pr)
    if pr['mergeable'] is not False and 'conflict' not in labels:
        if pr['mergeable'] is None:
            print(f'PR #{number}: GitHub has not computed mergeability; the next push or PR event checks again.')
        return
    # Refresh exact SHAs immediately before preparing the branch.
    pr = api(f'pulls/{number}')
    if not eligible(pr, repo):
        return
    head, base = pr['head']['sha'], pr['base']['sha']
    for sha in (head, base):
        if not re.fullmatch(r'[0-9a-f]{40}', sha):
            raise ValueError('Invalid commit')
        command('git', 'fetch', '-q', 'origin', sha)
    command('git', 'checkout', '-q', '--detach', head)
    command('git', 'config', 'user.name', 'hexplus-conflicts')
    command('git', 'config', 'user.email', '41898282+github-actions[bot]@users.noreply.github.com')
    before = markers()
    # Do not commit/ask an agent to repair protected or non-iOS conflicts.
    outside = [path for path in before if not path.startswith('ios/')]
    if outside:
        needs_human(pr, outside)
        return
    merged = command('git', '-c', 'core.hooksPath=/dev/null', 'merge', '--no-ff', '--no-commit', base,
                     check=False)
    unmerged = command('git', 'diff', '--name-only', '--diff-filter=U').stdout.splitlines()
    if merged.returncode and not unmerged:
        raise RuntimeError(merged.stderr)
    outside = [path for path in unmerged if not path.startswith('ios/')]
    if outside:
        command('git', 'merge', '--abort')
        needs_human(pr, outside)
        return
    # Delete/modify and binary conflicts cannot be represented by text markers.
    # Leave those for a person rather than silently accepting one side.
    pending_markers = markers()
    nontext = [path for path in unmerged if path not in pending_markers]
    if nontext:
        command('git', 'merge', '--abort')
        needs_human(pr, nontext)
        return
    merge_head = command('git', 'rev-parse', '-q', '--verify', 'MERGE_HEAD', check=False).returncode == 0
    if merge_head:
        command('git', 'add', '-A')
        command('git', '-c', 'core.hooksPath=/dev/null', 'commit', '-q', '-m',
                f'Merge hex-plus into PR #{number}' + (' (CONFLICTS)' if pending_markers else ''))
        current = api(f'pulls/{number}')
        if (not eligible(current, repo) or current['head']['sha'] != head
                or current['base']['sha'] != base):
            print(f'PR #{number} changed during preparation; its push triggers the next check.')
            return
        # No force push: another writer always wins.
        command('git', 'push', '-q', 'origin', f'HEAD:refs/heads/{pr["head"]["ref"]}')
    remaining = markers()
    if remaining:
        if 'conflict' not in labels:
            gh('pr', 'edit', number, '--add-label', 'conflict')
        # Only conflict-labelled drafts are auto-readied later.
        if not pr['draft']:
            gh('pr', 'ready', number, '--undo')
        title = f'Hex+ fix · {pr["head"]["ref"]} · conflict'
        runs = json.loads(gh('run', 'list', '--workflow', 'hexplus-fix.yml', '--limit', '100',
                             '--json', 'displayTitle,status'))
        if any(run['displayTitle'] == title and run['status'] != 'completed' for run in runs):
            print(f'PR #{number}: Linux resolver already queued or running.')
            return
        gh('workflow', 'run', 'hexplus-fix.yml', '--ref', 'hex-plus', '-f', f'conflict_pr={number}',
           '-f', f'branch={pr["head"]["ref"]}', '-f', 'result=conflict')
        print(f'PR #{number}: automatic Linux conflict repair requested.')
    else:
        if 'conflict' in labels:
            gh('pr', 'edit', number, '--remove-label', 'conflict')
            if pr['draft']:
                gh('pr', 'ready', number)
        if pr['head']['ref'].startswith('upstream-pr/'):
            gh('pr', 'merge', number, '--auto', '--merge')
        print(f'PR #{number}: no conflict markers remain; CI checks the branch.')


def main():
    repo = os.environ['GH_REPO']
    if not re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', repo):
        raise ValueError('Invalid repository')
    # Bounded, paginated enumeration (at most 300 open PRs).
    for page in range(1, 4):
        prs = api(f'pulls?state=open&base=hex-plus&per_page=100&page={page}')
        for item in prs:
            if eligible(item, repo):
                process(api(f'pulls/{item["number"]}'))
        if len(prs) < 100:
            break


if __name__ == '__main__':
    main()
