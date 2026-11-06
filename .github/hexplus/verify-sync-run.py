#!/usr/bin/env python3
"""Verify a completed sync push run through GitHub before granting promotion.

No sync-branch code or signing/push secrets are used here. The direct CI dispatch
can arrive before the requesting run finishes, so wait for it for at most 5 min.
"""
import json
import os
import re
import subprocess
import sys
import time


def require(condition, message):
    if not condition:
        raise ValueError(message)


def api(repo, endpoint):
    return json.loads(subprocess.check_output(['gh', 'api', f'repos/{repo}/{endpoint}'], text=True))


def validate_run(run, repo):
    require(run['repository']['full_name'] == repo
            and run['head_repository']['full_name'] == repo, 'Expected a run from this repository')
    require(run['event'] == 'push' and run['head_branch'] == 'sync/upstream',
            'Only sync/upstream push runs may promote')
    require(run['path'] == '.github/workflows/hexplus-ci.yml', 'Expected Hex+ CI workflow')
    require(re.fullmatch(r'[0-9a-f]{40}', run['head_sha']), 'Invalid source commit')


def validate_jobs(jobs):
    results = {}
    for name in ('Linux checks', 'Decide', 'Simulator tests', 'Unsigned archive'):
        matches = [job for job in jobs if job['name'] == name]
        require(len(matches) == 1, f'Missing or duplicate job: {name}')
        results[name] = matches[0]['conclusion']
    require(results['Linux checks'] == results['Decide'] == 'success', 'Linux checks and Decide must pass')
    # A sync that changes no app inputs skips both expensive jobs. Mixed outcomes
    # are never accepted; nor are failed/cancelled tests or archives.
    require((results['Simulator tests'], results['Unsigned archive']) in
            (('success', 'success'), ('skipped', 'skipped')), 'Required app checks did not pass')


def verify(repo, run_id):
    require(re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', repo), 'Invalid repository')
    require(re.fullmatch(r'[1-9][0-9]*', run_id), 'Expected a numeric CI run ID')
    for attempt in range(31):
        run = api(repo, f'actions/runs/{run_id}')
        validate_run(run, repo)
        if run['status'] == 'completed':
            break
        require(attempt < 30, 'CI did not complete within five minutes')
        time.sleep(10)
    require(run['conclusion'] == 'success', 'Sync CI must finish successfully before promotion')
    jobs = []
    for page in range(1, 101):
        batch = api(repo, f'actions/runs/{run_id}/jobs?filter=latest&per_page=100&page={page}')['jobs']
        jobs.extend(batch)
        if len(batch) < 100:
            break
    else:
        raise ValueError('Too many CI jobs')
    validate_jobs(jobs)
    return run


def main():
    repo = os.environ['GITHUB_REPOSITORY']
    run = verify(repo, sys.argv[1])
    with open(os.environ['GITHUB_OUTPUT'], 'a') as output:
        output.write(f'head_sha={run["head_sha"]}\n')
        output.write(f'ci_url=https://github.com/{repo}/actions/runs/{run["id"]}\n')
    print(f'Verified green sync CI {run["id"]} at {run["head_sha"]}')


if __name__ == '__main__':
    main()
