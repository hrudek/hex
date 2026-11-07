#!/usr/bin/env bash
# Unit tests of ios/ (with Hex+'s identity) on an iOS Simulator. No signing, no secrets.
set -euo pipefail
: "${APP_CONFIG:?}" "${RUNNER_TEMP:?}"
ONLY_TESTING=${ONLY_TESTING:-}
[[ "$ONLY_TESTING" =~ ^[A-Za-z0-9_/,]*$ ]] || { echo 'only_testing: letters, digits, _ / and , only'; exit 1; }
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
scheme=$(python3 -c 'import json,os; print(json.loads(os.environ["APP_CONFIG"])["scheme"])')
project=$(python3 -c 'import json,os; print(json.loads(os.environ["APP_CONFIG"])["project"])')
# HEXPLUS_IDENTITY=keep tests upstream's identity unchanged (the agent's local
# runs), so a rewrite never lands in its commits.
if [[ "${HEXPLUS_IDENTITY:-}" != keep ]]; then
  : "${APPLE_TEAM_ID:?}"
  python3 "$here/identity.py" "$root/ios"
fi
source "$here/cache-args.sh"
cd "$root/ios"
command -v xcodegen >/dev/null || brew install xcodegen
xcodegen generate

# Newest available iOS runtime, first iPhone on it.
udid=$(xcrun simctl list devices available -j | python3 -c '
import json, re, sys
devices = json.load(sys.stdin)["devices"]
def version(runtime):
    match = re.search(r"iOS-(\d+)-(\d+)", runtime)
    return tuple(map(int, match.groups())) if match else None
runtimes = sorted((r for r in devices if version(r)), key=version, reverse=True)
for runtime in runtimes:
    for device in devices[runtime]:
        if device["name"].startswith("iPhone"):
            print(device["udid"]); raise SystemExit
raise SystemExit("no available iPhone simulator")
')
echo "Simulator: $udid"
echo "$udid" > "$RUNNER_TEMP/simulator-udid"   # screenshots.sh reuses this simulator

only=()
if [[ -n "$ONLY_TESTING" ]]; then
  IFS=',' read -r -a selected <<< "$ONLY_TESTING"
  for test in "${selected[@]}"; do
    if [[ -n "$test" ]]; then only+=("-only-testing:$test"); fi
  done
fi

mkdir -p "$RUNNER_TEMP/test-output"
rm -rf "$RUNNER_TEMP/test-output/Tests.xcresult"   # agents run this repeatedly
set +e
xcodebuild test \
  -project "$project" -scheme "$scheme" \
  -destination "id=$udid" \
  -derivedDataPath "$RUNNER_TEMP/DerivedData" \
  ${cache_args[@]+"${cache_args[@]}"} \
  -resultBundlePath "$RUNNER_TEMP/test-output/Tests.xcresult" \
  ${only[@]+"${only[@]}"} \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' \
  2>&1 | tee "$RUNNER_TEMP/test-output/xcodebuild-test.log"
status=${PIPESTATUS[0]}
set -e
cache_report
grep -E "Test Case .*(passed|failed)|error:|Executed [0-9]+ tests" "$RUNNER_TEMP/test-output/xcodebuild-test.log" \
  | tail -200 >> "${GITHUB_STEP_SUMMARY:-/dev/null}" || true
exit "$status"
