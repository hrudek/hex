#!/usr/bin/env bash
# For agents on a macOS runner: build and run the iPhone app's simulator tests
# exactly as CI does, without rewriting the app's identity in the working tree.
# Usage: bash .github/hexplus/agent-test.sh [Target/Class,...]
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
APP_CONFIG=$(python3 "$here/config.py" | tail -1)
export APP_CONFIG HEXPLUS_IDENTITY=keep ONLY_TESTING="${1:-}"
export RUNNER_TEMP="${RUNNER_TEMP:-$(mktemp -d)}"
bash "$here/select-xcode.sh"
bash "$here/test.sh"
