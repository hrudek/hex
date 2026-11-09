#!/usr/bin/env bash
# One line per input, for comparing two commits without a full clone.
# Usage: fingerprint.sh <git-dir> <commit> [app|pipeline]
#   app       what changes the app binary that ships (pushes to main → TestFlight)
#   pipeline  app + Typr's CI scripts and workflow (PRs, so pipeline changes get tested)
set -euo pipefail
paths=(ios
  .github/typr/app.json .github/typr/identity.py .github/typr/build.sh
  .github/typr/archive.py .github/typr/package-archive.py)
if [[ "${3:-pipeline}" == pipeline ]]; then
  paths+=(.github/typr .github/workflows/typr-ci.yml)
fi
for path in "${paths[@]}"; do
  printf '%s %s\n' "$path" "$(git -C "$1" rev-parse --verify --quiet "$2:$path" || echo missing)"
done
