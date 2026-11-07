#!/usr/bin/env python3
"""Hex+ status: rewrite the pinned issue "Hex+ status" from GitHub's own data (gh only).

Env: GH_REPO, SYNC_TOKEN_EXPIRY (optional, "YYYY-MM-DD ..." from GitHub's
github-authentication-token-expiration header; otherwise the last known value is kept).
"""
from __future__ import annotations

import datetime as dt
import json
import os
import re
import subprocess
from pathlib import Path

TITLE = "Hex+ status"
MARKER = "<!-- hexplus-status -->"
WARN_DAYS = 30


def gh(*args: str) -> str:
    return subprocess.run(["gh", *args], capture_output=True, text=True, check=True).stdout


def gh_json(*args: str):
    out = gh(*args)
    return json.loads(out) if out.strip() else None


def icon(conclusion: str | None, status: str = "completed") -> str:
    if status != "completed":
        return "🔄"
    return {"success": "✅", "failure": "❌", "cancelled": "⏹️", "skipped": "⏭️"}.get(conclusion or "", "❔")


def ago(stamp: str) -> str:
    then = dt.datetime.fromisoformat(stamp.replace("Z", "+00:00"))
    minutes = int((dt.datetime.now(dt.timezone.utc) - then).total_seconds() // 60)
    if minutes < 60:
        return f"{minutes} min ago"
    if minutes < 48 * 60:
        return f"{minutes // 60} h ago"
    return f"{minutes // 1440} days ago"


def runs(workflow: str, **filters: str) -> list[dict]:
    args = ["run", "list", "--workflow", workflow, "--limit", "30",
            "--json", "databaseId,status,conclusion,createdAt,event,headBranch,url,displayTitle"]
    for key, value in filters.items():
        args += [f"--{key}", value]
    return gh_json(*args) or []


def last_testflight(repo: str) -> str:
    for run in runs("hexplus-ci.yml", branch="hex-plus", event="push"):
        jobs = gh_json("api", f"repos/{repo}/actions/runs/{run['databaseId']}/jobs",
                       "--jq", "[.jobs[] | {name, conclusion}]") or []
        sign = next((j for j in jobs if j["name"].startswith("Sign (testflight")), None)
        if sign and sign["conclusion"] in ("success", "failure"):
            return f"{icon(sign['conclusion'])} [{ago(run['createdAt'])}]({run['url']})"
    return "none in the last 30 pushes"


def main() -> None:
    repo = os.environ["GH_REPO"]
    issue = next((i for i in gh_json("issue", "list", "--state", "open", "--search", f'in:title "{TITLE}"',
                                     "--json", "number,title,body") or [] if i["title"] == TITLE), None)
    token_expiry = (os.environ.get("SYNC_TOKEN_EXPIRY") or "").strip()[:10]
    if not token_expiry and issue:
        m = re.search(r"<!-- sync-token-expiry=(\S*) -->", issue["body"] or "")
        token_expiry = m.group(1) if m else ""

    lines = [MARKER, f"<!-- sync-token-expiry={token_expiry} -->",
             "_Updated by the Hex+ status workflow. Nothing here needs you unless it says so._", ""]

    attention: list[str] = []
    human = gh_json("issue", "list", "--state", "open", "--label", "needs-human", "--json", "number,title,url") or []
    for item in human:
        attention.append(f"- 🙋 [#{item['number']} {item['title']}]({item['url']})")
    if os.environ.get("SYNC_TOKEN_PR_WRITE") == "missing":
        attention.append("- 🔴 **SYNC_TOKEN cannot write pull requests**: GitHub → Settings → Developer settings → "
                         "Fine-grained tokens → the sync token → Pull requests: Read and write")
    today = dt.date.today()
    expiries = json.loads((Path(__file__).parent / "expiry.json").read_text())["items"]
    if token_expiry:
        expiries.append({"name": "GitHub token (SYNC_TOKEN)", "expires": token_expiry,
                         "renew": "new fine-grained token, then set it in environment hexplus-sync"})
    rows = []
    for item in sorted(expiries, key=lambda e: e["expires"]):
        days = (dt.date.fromisoformat(item["expires"]) - today).days
        mark = "🔴" if days <= WARN_DAYS else "🟢"
        approx = " (approx.)" if item.get("approximate") else ""
        rows.append(f"| {mark} {item['name']} | {item['expires']}{approx} | {days} days |")
        if days <= WARN_DAYS:
            attention.append(f"- 🔴 **{item['name']}** expires {item['expires']}: {item['renew']}")

    lines += ["### Needs you", *(attention or ["Nothing. ✅"]), ""]

    ci = runs("hexplus-ci.yml", branch="hex-plus")
    push = next((r for r in ci if r["event"] == "push"), None)
    sync = (runs("hexplus-sync.yml") or [None])[0]
    gate = (runs("hexplus-gate.yml") or [None])[0]
    lines += ["### Pipeline", "| | Last | |", "|---|---|---|"]
    def row(name: str, run: dict | None) -> None:
        if run:
            lines.append(f"| {name} | {icon(run['conclusion'], run['status'])} | [{ago(run['createdAt'])}]({run['url']}) |")
        else:
            lines.append(f"| {name} | – | never |")
    row("hex-plus (last merge)", push)
    row("Upstream sync", sync)
    row("Sync promotion (gate)", gate)
    lines.append(f"| TestFlight upload | {last_testflight(repo)} | |")
    lines.append("")

    incidents = gh_json("issue", "list", "--state", "open", "--label", "fix", "--json", "number,title,url,labels") or []
    lines += ["### Automatic repairs"]
    if incidents:
        for item in incidents:
            labels = [label["name"] for label in item["labels"]]
            state = "🙋 needs you" if "needs-human" in labels else "🔧 in progress"
            lines.append(f"- {state}: [#{item['number']} {item['title']}]({item['url']})")
    else:
        lines.append("None open. ✅")
    closed = gh_json("issue", "list", "--state", "closed", "--label", "fix", "--limit", "5",
                     "--json", "number,title,url,closedAt") or []
    if closed:
        lines.append("")
        lines.append("Recently repaired: " + ", ".join(f"[#{c['number']}]({c['url']}) {ago(c['closedAt'])}" for c in closed))
    lines.append("")

    open_prs = gh_json("pr", "list", "--state", "open", "--json", "number,title,url,labels,isDraft") or []
    lines += ["### Open PRs"]
    lines += [f"- [#{p['number']} {p['title']}]({p['url']})" + (" (draft)" if p["isDraft"] else "") for p in open_prs] or ["None."]
    lines += ["", "### Renewals", "| What | Expires | Left |", "|---|---|---|", *rows, "",
              "<sub>Apple Developer Program membership renews yearly in your Apple account (not tracked here).</sub>"]

    body = "\n".join(lines) + "\n"
    if issue:
        gh("issue", "edit", str(issue["number"]), "--body", body)
    else:
        url = gh("issue", "create", "--title", TITLE, "--body", body).strip()
        print(f"Created {url}; pin it once in the GitHub UI.")
    print(body)


if __name__ == "__main__":
    main()
