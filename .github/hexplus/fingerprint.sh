#!/usr/bin/env bash
# One line per input, for comparing two commits without a full clone.
# Usage: fingerprint.sh <git-dir> <commit> [app|pipeline]
#   app       what changes the app binary that ships (pushes to hex-plus → TestFlight)
#   pipeline  app + Hex+'s CI scripts and workflow (PRs, so pipeline changes get tested)
set -euo pipefail
paths=(ios app/AppIcon.icon tests/fixtures/vocabulary/audio
  .github/hexplus/app.json .github/hexplus/identity.py .github/hexplus/build.sh
  .github/hexplus/archive.py .github/hexplus/package-archive.py)
if [[ "${3:-pipeline}" == pipeline ]]; then
  paths+=(.github/hexplus .github/workflows/hexplus-ci.yml)
fi
for path in "${paths[@]}"; do
  printf '%s %s\n' "$path" "$(git -C "$1" rev-parse --verify --quiet "$2:$path" || echo missing)"
done
