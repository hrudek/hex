#!/usr/bin/env bash
# Unsigned device archive of ios/ with Hex+'s identity. No signing secrets here.
set -euo pipefail
: "${APP_CONFIG:?}" "${APPLE_TEAM_ID:?}" "${SOURCE_SHA:?}" "${RUNNER_TEMP:?}" "${ARTIFACT_AGE_RECIPIENT:?}"
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
scheme=$(python3 -c 'import json,os; print(json.loads(os.environ["APP_CONFIG"])["scheme"])')
project=$(python3 -c 'import json,os; print(json.loads(os.environ["APP_CONFIG"])["project"])')
python3 "$here/identity.py" "$root/ios"
source "$here/cache-args.sh"
cd "$root/ios"
command -v xcodegen >/dev/null || brew install xcodegen
xcodegen --version
xcodegen generate
mkdir -p "$RUNNER_TEMP/output"
xcodebuild archive \
  -project "$project" -scheme "$scheme" -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$RUNNER_TEMP/output/App.xcarchive" \
  -derivedDataPath "$RUNNER_TEMP/DerivedData" \
  ${cache_args[@]+"${cache_args[@]}"} \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' \
  CURRENT_PROJECT_VERSION="${GITHUB_RUN_NUMBER}.${GITHUB_RUN_ATTEMPT}" \
  | tee "$RUNNER_TEMP/output/xcodebuild.log"
cache_report
python3 "$here/package-archive.py"
