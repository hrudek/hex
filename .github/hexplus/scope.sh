#!/usr/bin/env bash
# All repository paths may change. Usage: scope.sh <base-sha> <head-sha>
# Changes under .github/ need the "infra" label, so an agent cannot widen
# automation permissions unnoticed. Env: LABELS (comma-separated).
set -euo pipefail
: "${LABELS:=}"
changed=$(git diff --name-only "$1" "$2")
automation=$(grep -E '^\.github/' <<<"$changed" || true)
status=0
if [[ -n "$automation" ]]; then
  if [[ ",$LABELS," == *",infra,"* ]]; then
    echo 'Automation changed (label infra present):'
  else
    echo 'Automation changed; add the "infra" label if that is intended:'
    status=1
  fi
  echo "$automation"
fi
count=$(printf '%s\n' "$changed" | grep -c . || true)
[[ "$status" != 0 ]] || echo "Scope OK ($count files)."
exit "$status"
