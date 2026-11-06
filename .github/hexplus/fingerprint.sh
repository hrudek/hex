#!/usr/bin/env bash
# Print one line per input the iOS build reads, for comparing two commits
# without a full clone. Usage: fingerprint.sh <git-dir> <commit>
set -euo pipefail
for path in ios app/AppIcon.icon tests/fixtures/vocabulary/audio .github/hexplus \
  .github/workflows/hexplus-ci.yml; do
  printf '%s %s\n' "$path" "$(git -C "$1" rev-parse --verify --quiet "$2:$path" || echo missing)"
done
