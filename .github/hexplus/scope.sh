#!/usr/bin/env bash
# Feature PRs may change only the iPhone app and Hex+'s notes. Changes to the
# fork's automation (.github/) need the "infra" label, so an agent cannot widen
# its own permissions unnoticed. Usage: scope.sh <base-sha> <head-sha>
set -euo pipefail
: "${LABELS:=}"
outside=$(git diff --name-only "$1" "$2" | grep -Ev '^(ios/|HEXPLUS\.md$)' || true)
if [[ -z "$outside" ]]; then
  echo 'Scope: only ios/ and HEXPLUS.md changed.'
  exit 0
fi
infra=$(grep -Ev '^\.github/(hexplus/|workflows/hexplus-[^/]+\.yml$)' <<<"$outside" || true)
if [[ -n "$infra" ]]; then
  echo 'Feature PRs must not change files outside ios/, HEXPLUS.md and Hex+ automation:'
  echo "$infra"
  exit 1
fi
if [[ ",$LABELS," == *",infra,"* ]]; then
  echo 'Scope: Hex+ automation changed (label infra present):'
  echo "$outside"
  exit 0
fi
echo 'Hex+ automation changed; add the "infra" label if that is intended:'
echo "$outside"
exit 1
