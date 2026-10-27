#!/usr/bin/env bash
set -euo pipefail

ORBIT_REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ORBIT_TEST_SCOPE="${IOS_TEST_SCOPE:-smoke}"
ORBIT_TEST_FILTERS=()
case "$ORBIT_TEST_SCOPE" in
  full) ;;
  unit) ORBIT_TEST_FILTERS+=("-only-testing:OrbitTests") ;;
  smoke)
    ORBIT_TEST_FILTERS+=(
      "-only-testing:OrbitTests"
      "-only-testing:OrbitUITests/ChecklistUITests/testBottomCaptureStaysReachableAndKeepsDraftWhenKeyboardCloses"
      "-only-testing:OrbitUITests/ChecklistUITests/testNotesHaveSectionsAndPages"
      "-only-testing:OrbitUITests/ChecklistUITests/testCalendarMakesAddingToAnotherDayExplicit"
      "-only-testing:OrbitUITests/ChecklistUITests/testNativeThemeMenusAndHabitHistory"
    ) ;;
  focused)
    if [[ ! "${IOS_TEST_FILTER:-}" =~ ^(OrbitTests|OrbitUITests)(/[A-Za-z_][A-Za-z0-9_]*){1,2}$ ]]; then
      echo "Use a test class or method, e.g. OrbitUITests/ChecklistUITests/testNotesHaveSectionsAndPages" >&2
      exit 2
    fi
    ORBIT_TEST_FILTERS+=("-only-testing:$IOS_TEST_FILTER") ;;
  *) echo "Unknown iOS test scope: $ORBIT_TEST_SCOPE" >&2; exit 2 ;;
esac

case "${1:-all}" in
  build) ORBIT_XCODE_ACTION=build-for-testing; ORBIT_RESULTS=BuildResults.xcresult ;;
  test) ORBIT_XCODE_ACTION=test-without-building; ORBIT_RESULTS=TestResults.xcresult ;;
  all) ORBIT_XCODE_ACTION=test; ORBIT_RESULTS=TestResults.xcresult ;;
  *) echo "Use build, test, or all" >&2; exit 2 ;;
esac
cd "$ORBIT_REPO_ROOT/ios"
# macOS ships Bash 3.2, which treats an empty array as unset with `set -u`.
# Keep the command array nonempty and append filters only for filtered scopes.
ORBIT_XCODE_ARGS=(
  "$ORBIT_XCODE_ACTION"
  -parallel-testing-enabled NO
  -project Orbit.xcodeproj -scheme Orbit
  -destination "platform=iOS Simulator,id=${DEVICE_ID:?Choose a simulator first}"
  -derivedDataPath "${RUNNER_TEMP:?}/OrbitDerivedData"
  -resultBundlePath "$ORBIT_REPO_ROOT/$ORBIT_RESULTS"
  CODE_SIGNING_ALLOWED=NO COMPILER_INDEX_STORE_ENABLE=NO
)
if [[ "$ORBIT_TEST_SCOPE" != full ]]; then
  ORBIT_XCODE_ARGS+=("${ORBIT_TEST_FILTERS[@]}")
fi
xcodebuild "${ORBIT_XCODE_ARGS[@]}"
