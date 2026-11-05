#!/usr/bin/env bash
# Pinned release + platform digests; no unverified brew/curl-pipe-shell install.
set -euo pipefail
: "${RUNNER_TEMP:?}"
case "$(uname -s)-$(uname -m)" in
  Darwin-arm64)
    platform=darwin-arm64
    digest=e2020b073c44f692685a24d6abc378817eb81ffaaf49fd0531ef8565f767f2f5 ;;
  Darwin-x86_64)
    platform=darwin-amd64
    digest=1d1e4bc66e1427edad7739ae7616157de0e79db8b6d2a1497d7d9925fb06a539 ;;
  Linux-x86_64)
    platform=linux-amd64
    digest=cbe24006683f8eb669266162894b9a522a1af52f2665fbc63a4bb032ed26ac10 ;;
  *) echo 'Unsupported age tool platform' >&2; exit 1 ;;
esac
mkdir -p "$RUNNER_TEMP/age-tools"
archive="$RUNNER_TEMP/age-tools/age.tar.gz"
curl --fail --silent --show-error --location --retry 3 \
  "https://github.com/FiloSottile/age/releases/download/v1.3.2/age-v1.3.2-$platform.tar.gz" \
  --output "$archive"
ACTUAL_ARCHIVE="$archive" EXPECTED_DIGEST="$digest" python3 - <<'PY'
import hashlib, os
from pathlib import Path
if hashlib.sha256(Path(os.environ['ACTUAL_ARCHIVE']).read_bytes()).hexdigest() != os.environ['EXPECTED_DIGEST']:
    raise SystemExit('age release checksum mismatch')
PY
tar -xzf "$archive" -C "$RUNNER_TEMP/age-tools" age/age age/age-keygen
if [[ -n "${GITHUB_PATH:-}" ]]; then
  echo "$RUNNER_TEMP/age-tools/age" >> "$GITHUB_PATH"
fi
