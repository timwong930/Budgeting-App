#!/usr/bin/env bash
set -euo pipefail

PROJECT="Budgeting App.xcodeproj"
SCHEME="Budgeting AppTests"

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "error: xcodebuild is required. Run this script on a Mac with Xcode installed." >&2
  exit 1
fi

if ! command -v xcrun >/dev/null 2>&1; then
  echo "error: xcrun is required. Run this script on a Mac with Xcode installed." >&2
  exit 1
fi

SCHEME_LIST="$(xcodebuild -project "${PROJECT}" -list 2>&1)" || {
  echo "error: Xcode could not read ${PROJECT}." >&2
  echo "${SCHEME_LIST}" >&2
  exit 1
}

if ! grep -Fq "${SCHEME}" <<<"${SCHEME_LIST}"; then
  echo "error: shared scheme '${SCHEME}' is not visible to xcodebuild." >&2
  echo "Pull the latest TIM-88 branch, close/reopen Xcode, then retry." >&2
  echo >&2
  echo "xcodebuild currently reports:" >&2
  echo "${SCHEME_LIST}" >&2
  exit 1
fi

DEVICE_ID="$(xcrun simctl list devices available -j | /usr/bin/python3 -c '
import json, sys
payload = json.load(sys.stdin)
for runtime, devices in payload.get("devices", {}).items():
    if "iOS" not in runtime:
        continue
    booted = [d for d in devices if d.get("isAvailable") and d.get("state") == "Booted"]
    available = [d for d in devices if d.get("isAvailable")]
    candidates = booted or available
    if candidates:
        print(candidates[0]["udid"])
        break
')"

if [[ -z "${DEVICE_ID}" ]]; then
  echo "error: no available iOS Simulator was found. Install an iOS simulator runtime in Xcode." >&2
  exit 1
fi

echo "Running ${SCHEME} on simulator ${DEVICE_ID}"
exec xcodebuild \
  -project "${PROJECT}" \
  -scheme "${SCHEME}" \
  -destination "platform=iOS Simulator,id=${DEVICE_ID}" \
  test
