#!/usr/bin/env python3
"""Hex+ fix pipeline, step 1: decide whether a failed Hex+ CI run gets an agent fix.

Runs on Linux with GITHUB_TOKEN (actions: write, issues: write) and only calls gh.
It never runs repository code from the failing branch.

Inputs (env): GITHUB_EVENT_NAME, RUN_ID, RESULT, GH_REPO, GITHUB_OUTPUT,
GITHUB_STEP_SUMMARY, RUNNER_TEMP.

One incident = one open issue labelled "fix" whose body carries
<!-- hexplus-fix target=BRANCH -->. Work happens on:
  hex-plus       -> fix/ci-<issue> (a PR with auto-merge, created by the push job)
  sync/upstream  -> sync/upstream itself (the gate promotes it once green)
  feature/*      -> that open PR's branch
  fix/ci-<n>     -> that branch (incident n)
Each pushed or empty agent attempt leaves an attempt comment; after MAX_ATTEMPTS
the incident gets "needs-human" and the pipeline stops for it.
"""
from __future__ import annotations

import datetime as dt
import json
import os
import re
import subprocess
import sys
import time

MAX_ATTEMPTS = 6
MAX_NEW_INCIDENTS_PER_DAY = 4
RETRY_AFTER_MINUTES = 25
CODE_JOBS = {"Linux checks", "Decide", "Simulator tests", "Unsigned archive"}
SIGN_PREFIX = "Sign"
MARKER = re.compile(r"<!-- hexplus-fix target=(\S+) -->")
ATTEMPT = "<!-- hexplus-fix-attempt -->"


def gh(*args: str, check: bool = True) -> str:
    result = subprocess.run(["gh", *args], capture_output=True, text=True)
    if check and result.returncode != 0:
        sys.stderr.write(result.stderr)
        raise SystemExit(f"gh {' '.join(args[:3])} failed")
    return result.stdout


def gh_json(*args: str):
    out = gh(*args)
    return json.loads(out) if out.strip() else None


def output(**values: str) -> None:
    with open(os.environ["GITHUB_OUTPUT"], "a") as fh:
        for key, value in values.items():
            fh.write(f"{key}={value}\n")


def summary(text: str) -> None:
    print(text)
    path = os.environ.get("GITHUB_STEP_SUMMARY")
    if path:
        with open(path, "a") as fh:
            fh.write(text + "\n")


def stop(reason: str) -> None:
    summary(f"No fix: {reason}")
    output(proceed="false")
    raise SystemExit(0)


def incidents() -> list[dict]:
    issues = gh_json("issue", "list", "--label", "fix", "--state", "open", "--limit", "50",
                     "--json", "number,body,labels,createdAt,title") or []
    for issue in issues:
        match = MARKER.search(issue.get("body") or "")
        issue["target"] = match.group(1) if match else ""
        issue["labels"] = [label["name"] for label in issue.get("labels", [])]
    return [issue for issue in issues if issue["target"]]


def incident_for_target(target: str) -> dict | None:
    return next((i for i in incidents() if i["target"] == target), None)


def attempt_comments(issue: int) -> list[dict]:
    comments = gh_json("api", f"repos/{os.environ['GH_REPO']}/issues/{issue}/comments",
                       "--paginate", "--jq", "[.[] | {body, created_at}]") or []
    # --paginate with --jq prints one array per page.
    if comments and isinstance(comments[0], list):
        comments = [c for page in comments for c in page]
    return [c for c in comments if c["body"].startswith(ATTEMPT)]


def failed_jobs(run_id: str) -> list[str]:
    jobs = gh_json("api", f"repos/{os.environ['GH_REPO']}/actions/runs/{run_id}/jobs",
                   "--paginate", "--jq", "[.jobs[] | select(.conclusion == \"failure\") | .name]") or []
    if jobs and isinstance(jobs[0], list):
        jobs = [j for page in jobs for j in page]
    return jobs


def open_pr(branch: str) -> dict | None:
    prs = gh_json("pr", "list", "--head", branch, "--state", "open", "--json", "number,isDraft") or []
    return prs[0] if prs else None


def remote_branch_exists(branch: str) -> bool:
    out = gh("api", f"repos/{os.environ['GH_REPO']}/branches/{branch}", check=False)
    return bool(out.strip()) and '"name"' in out


def close_incidents(target: str, why: str) -> None:
    for issue in incidents():
        if issue["target"] == target:
            gh("issue", "close", str(issue["number"]), "--comment", f"Fixed: {why}")
            summary(f"Closed incident #{issue['number']} ({target}): {why}")


def classify(branch: str) -> tuple[str, str] | None:
    """(target, work_branch) for a failing branch, or None when Hex+ does not auto-fix it."""
    if branch in ("hex-plus", "sync/upstream"):
        return branch, branch  # work branch for hex-plus is decided once the incident exists
    if m := re.fullmatch(r"fix/ci-(\d+)", branch):
        issue = gh_json("issue", "view", m.group(1), "--json", "body,state") or {}
        target = MARKER.search(issue.get("body") or "")
        if issue.get("state") != "OPEN" or not target:
            return None
        return target.group(1), branch
    if branch.startswith("feature/"):
        return (branch, branch) if open_pr(branch) else None
    return None


def ensure_incident(target: str, run_url: str) -> dict | None:
    existing = incident_for_target(target)
    if existing:
        return existing
    since = dt.datetime.now(dt.timezone.utc) - dt.timedelta(days=1)
    recent = gh_json("issue", "list", "--label", "fix", "--state", "all", "--limit", "50",
                     "--json", "createdAt") or []
    recent = [i for i in recent if dt.datetime.fromisoformat(i["createdAt"].replace("Z", "+00:00")) > since]
    labels = ["fix"]
    if len(recent) >= MAX_NEW_INCIDENTS_PER_DAY:
        labels.append("needs-human")
    body = (f"<!-- hexplus-fix target={target} -->\n"
            f"Hex+ CI failed on `{target}`: {run_url}\n\n"
            "The fix pipeline repairs this automatically (agent attempt, CI check, next attempt "
            f"right away), up to {MAX_ATTEMPTS} attempts. Nothing to do unless this issue gets "
            "the label `needs-human`.")
    args = ["issue", "create", "--title", f"CI broken: {target}", "--body", body]
    for label in labels:
        args += ["--label", label]
    url = gh(*args).strip()
    number = int(url.rsplit("/", 1)[-1])
    summary(f"Opened incident #{number} for {target}")
    if "needs-human" in labels:
        gh("issue", "comment", str(number), "--body",
           f"More than {MAX_NEW_INCIDENTS_PER_DAY} incidents in 24 hours: the pipeline stops "
           "fixing on its own so it cannot loop. Please have a look.")
        return None
    return {"number": number, "target": target, "labels": labels}


def pick_scheduled() -> tuple[dict, str, str] | None:
    """Resume an open incident whose latest CI run is red and whose last attempt is old."""
    now = dt.datetime.now(dt.timezone.utc)
    for issue in incidents():
        if "needs-human" in issue["labels"]:
            continue
        work = issue["target"]
        if work == "hex-plus" and remote_branch_exists(f"fix/ci-{issue['number']}"):
            work = f"fix/ci-{issue['number']}"
        runs = gh_json("run", "list", "--workflow", "hexplus-ci.yml", "--branch", work, "--limit", "1",
                       "--json", "databaseId,status,conclusion") or []
        if not runs or runs[0]["status"] != "completed" or runs[0]["conclusion"] != "failure":
            continue
        attempts = attempt_comments(issue["number"])
        if attempts:
            last = dt.datetime.fromisoformat(attempts[-1]["created_at"].replace("Z", "+00:00"))
            if now - last < dt.timedelta(minutes=RETRY_AFTER_MINUTES):
                continue
        return issue, work, str(runs[0]["databaseId"])
    return None


def main() -> None:
    repo = os.environ["GH_REPO"]
    event_name = os.environ["GITHUB_EVENT_NAME"]
    run_id = os.environ.get("RUN_ID", "").strip()
    if run_id:
        if not run_id.isdigit():
            stop("run_id must be a number")
        run = gh_json("api", f"repos/{repo}/actions/runs/{run_id}") or {}
        if run.get("path", "").split("@")[0] != ".github/workflows/hexplus-ci.yml":
            stop("not a Hex+ CI run")
        if (run.get("head_repository") or {}).get("full_name") != repo:
            stop("run from another repository")
        # CI dispatches this from its own last job, so the run itself is still in progress.
        branch = run["head_branch"]
        conclusion = os.environ.get("RESULT") or run.get("conclusion") or ""
        if conclusion not in ("failure", "success"):
            stop(f"result {conclusion or 'unknown'}")
        if conclusion == "success":
            if branch in ("hex-plus", "sync/upstream") or branch.startswith("feature/"):
                close_incidents(branch, f"Hex+ CI is green again ({run['html_url']}).")
            stop("CI is green")
        if conclusion != "failure":
            stop(f"CI {conclusion}")
        failed = failed_jobs(run_id)
        code = [j for j in failed if j in CODE_JOBS]
        signing = [j for j in failed if j.startswith(SIGN_PREFIX)]
        if not code:
            if signing and branch == "hex-plus" and run.get("run_attempt", 1) == 1:
                # The dispatching CI job must finish before its run can be re-run.
                for _ in range(40):
                    if gh_json("api", f"repos/{repo}/actions/runs/{run_id}", "--jq", "{status}")["status"] == "completed":
                        break
                    time.sleep(15)
                gh("run", "rerun", run_id, "--failed")
                stop("signing/upload failed once; re-running it")
            if signing and branch == "hex-plus":
                ensure = ensure_incident("hex-plus-signing", run["html_url"])
                if ensure:
                    gh("issue", "edit", str(ensure["number"]), "--add-label", "needs-human")
                    gh("issue", "comment", str(ensure["number"]), "--body",
                       f"Signing or the TestFlight upload failed twice ({run['html_url']}). "
                       "This is Apple's side (certificate, profile, agreement), not code.")
                stop("signing needs a human")
            stop(f"no code job failed ({', '.join(failed) or 'none'})")
        classified = classify(branch)
        if not classified:
            stop(f"branch {branch} is not auto-fixed")
        target, work = classified
        issue = ensure_incident(target, run["html_url"])
        if not issue:
            stop("incident needs a human")
    elif event_name in ("schedule", "workflow_dispatch"):  # resume waiting incidents
        picked = pick_scheduled()
        if not picked:
            stop("no incident waiting for another attempt")
        issue, work, run_id = picked
        target = issue["target"]
        failed = [j for j in failed_jobs(run_id) if j in CODE_JOBS]
    else:
        stop(f"event {event_name}")

    if "needs-human" in issue["labels"]:
        stop(f"incident #{issue['number']} needs a human")
    attempts = len(attempt_comments(issue["number"]))
    if attempts >= MAX_ATTEMPTS:
        gh("issue", "edit", str(issue["number"]), "--add-label", "needs-human")
        gh("issue", "comment", str(issue["number"]), "--body",
           f"{MAX_ATTEMPTS} agent attempts did not make CI green. Stopping here; please have a look.")
        stop("attempt limit reached")
    if target == "hex-plus":
        work = f"fix/ci-{issue['number']}"
    base = "hex-plus" if work.startswith("fix/ci-") and not remote_branch_exists(work) else work

    log_path = os.path.join(os.environ["RUNNER_TEMP"], "failure", "failure.log")
    os.makedirs(os.path.dirname(log_path), exist_ok=True)
    log = subprocess.run(["gh", "run", "view", run_id, "--log-failed"], capture_output=True, text=True).stdout
    lines = [re.sub(r"^[^\t]*\t[^\t]*\t\S+Z ", "", line) for line in log.splitlines()]
    with open(log_path, "w") as fh:
        fh.write("\n".join(lines[-4000:]) + "\n")

    attempt = attempts + 1
    model = "sonnet" if attempt == 1 and target != "sync/upstream" else "opus"
    summary(f"Fix attempt {attempt}/{MAX_ATTEMPTS} for #{issue['number']} on `{work}` "
            f"(from `{base}`, model {model}); failed jobs: {', '.join(failed)}")
    output(proceed="true", issue=str(issue["number"]), target=target, work=work, base=base,
           run_id=run_id, attempt=str(attempt), model=model,
           run_url=f"https://github.com/{repo}/actions/runs/{run_id}")


if __name__ == "__main__":
    main()
