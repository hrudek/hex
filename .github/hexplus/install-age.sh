#!/usr/bin/env bash
# Pinned release + platform digests; no unverified brew/curl-pipe-shell install.
# If GitHub's release downloads fail (they returned HTTP 504 for hours on
# 2026-11-08 while everything else worked), build the same pinned version from
# the Go module proxy instead: the module zip must match the pinned h1 hash
# (the one sum.golang.org records), and its own go.sum pins every dependency.
set -euo pipefail
: "${RUNNER_TEMP:?}"
version=v1.3.2
# h1 module hash of filippo.io/age@v1.3.2, as recorded by sum.golang.org.
module_h1='h1:r6RSZLFSMm6rzKepZ7ZAYkKCu14f3/Me8c7uKYh7C8c='
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
tools="$RUNNER_TEMP/age-tools"
mkdir -p "$tools"

install_release() {
  local archive="$tools/age.tar.gz"
  curl --fail --silent --show-error --location --retry 5 --retry-all-errors --retry-delay 5 \
    "https://github.com/FiloSottile/age/releases/download/$version/age-$version-$platform.tar.gz" \
    --output "$archive" || return 1
  ACTUAL_ARCHIVE="$archive" EXPECTED_DIGEST="$digest" python3 -I - <<'PY'
import hashlib, os
from pathlib import Path
if hashlib.sha256(Path(os.environ['ACTUAL_ARCHIVE']).read_bytes()).hexdigest() != os.environ['EXPECTED_DIGEST']:
    raise SystemExit('age release checksum mismatch')
PY
  tar -xzf "$archive" -C "$tools" age/age age/age-keygen
}

install_from_module_proxy() {
  command -v go >/dev/null || { echo 'age fallback needs Go on the runner' >&2; return 1; }
  local zip="$tools/age-module.zip" src="$tools/src"
  curl --fail --silent --show-error --location --retry 5 --retry-all-errors --retry-delay 5 \
    "https://proxy.golang.org/filippo.io/age/@v/$version.zip" --output "$zip"
  # Go's dirhash Hash1 over the module zip; a mismatch stops before any build.
  ACTUAL_ZIP="$zip" EXPECTED_H1="$module_h1" python3 -I - <<'PY'
import base64, hashlib, os, zipfile
with zipfile.ZipFile(os.environ['ACTUAL_ZIP']) as z:
    names = sorted(n for n in z.namelist() if not n.endswith('/'))
    lines = ''.join(f"{hashlib.sha256(z.read(n)).hexdigest()}  {n}\n" for n in names)
actual = 'h1:' + base64.b64encode(hashlib.sha256(lines.encode()).digest()).decode()
if actual != os.environ['EXPECTED_H1']:
    raise SystemExit(f'age module hash mismatch: {actual}')
PY
  rm -rf "$src" && mkdir -p "$src" "$tools/age"
  (cd "$src" && unzip -q "$zip")
  # -mod=readonly: dependencies only as the verified go.sum pins them.
  (cd "$src/filippo.io/age@$version" &&
    GOFLAGS=-mod=readonly GOPROXY=https://proxy.golang.org GOSUMDB=sum.golang.org \
      CGO_ENABLED=0 go build -trimpath -o "$tools/age/" ./cmd/age ./cmd/age-keygen)
}

if ! install_release; then
  echo "::warning::age $version release download failed; building the pinned module from proxy.golang.org" >&2
  install_from_module_proxy
fi
"$tools/age/age" --version >/dev/null
if [[ -n "${GITHUB_PATH:-}" ]]; then
  echo "$tools/age" >> "$GITHUB_PATH"
fi
