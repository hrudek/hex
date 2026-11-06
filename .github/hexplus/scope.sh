#!/usr/bin/env bash
# What a PR into hex-plus may change. Usage: scope.sh <base-sha> <head-sha>
#   feature/* and others: only ios/ and HEXPLUS.md
#   upstream-pr/*:        whatever the upstream PR changes
# Hex+'s own automation (.github/hexplus/, hexplus-* workflows, issue templates) always needs the
# "infra" label, so an agent cannot widen its own permissions unnoticed.
# Env: LABELS (comma-separated), HEAD_REF (the PR's branch).
set -euo pipefail
: "${LABELS:=}" "${HEAD_REF:=}"
changed=$(git diff --name-only "$1" "$2")
owned_re='^\.github/(hexplus/|workflows/hexplus-[^/]+\.yml$|ISSUE_TEMPLATE/)'
owned=$(grep -E "$owned_re" <<<"$changed" || true)
others=$(grep -Ev "$owned_re" <<<"$changed" || true)
status=0
if [[ "$HEAD_REF" != upstream-pr/* ]]; then
  outside=$(grep -Ev '^(ios/|HEXPLUS\.md$)' <<<"$others" || true)
  if [[ -n "$outside" ]]; then
    echo 'Feature PRs must not change files outside ios/, HEXPLUS.md and Hex+ automation:'
    echo "$outside"
    status=1
  fi
fi
if [[ -n "$owned" ]]; then
  if [[ ",$LABELS," == *",infra,"* ]]; then
    echo 'Hex+ automation changed (label infra present):'
  else
    echo 'Hex+ automation changed; add the "infra" label if that is intended:'
    status=1
  fi
  echo "$owned"
fi
[[ "$status" != 0 ]] || echo "Scope OK ($(wc -l <<<"$changed" | tr -d ' ') files)."
exit "$status"
