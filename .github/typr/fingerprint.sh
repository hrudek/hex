#!/usr/bin/env bash
# Compare committed inputs without reading blobs or requiring a full clone.
# Usage: fingerprint.sh <git-dir> <commit> [app|pipeline]
# app: iOS source/resources/project and committed identity; no CI-only changes.
# pipeline: also include CI scripts/workflows (available for explicit comparisons).
set -euo pipefail
paths=(ios .github/typr/app.json)
if [[ "${3:-pipeline}" == pipeline ]]; then
  paths+=(.github/typr .github/workflows)
fi
# Documentation and offline tools do not enter Xcode builds. Keep tests/fixtures
# included so test-only app changes still get a post-merge simulator run.
git -C "$1" ls-tree -rz "$2" -- "${paths[@]}" \
  | while IFS= read -r -d '' entry; do
      path=${entry#*$'\t'}
      case "$path" in ios/tools/*|ios/*.md) continue ;; esac
      printf '%s\0' "$entry"
    done \
  | git -C "$1" hash-object --stdin
