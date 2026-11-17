#!/usr/bin/env bash
# Local regression proof for the test verdict gate; no simulator required.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
GATE="$ROOT/ci/check-test-result.sh"
PASS=0
check () {
  local name=$1 want=$2 rc=$3 cutoff=$4
  local got=0
  bash "$GATE" "$W/test.log" "$rc" "$cutoff" > "$W/verdict" 2>&1 || got=$?
  if [[ $want == pass && $got == 0 || $want == fail && $got != 0 ]]; then
    echo "PASS $name"; PASS=$((PASS+1))
  else
    echo "FAIL $name (exit=$got)"; cat "$W/verdict"; exit 1
  fi
}
printf "%s\n" "Test Case '-[KitUITests.KitUITests testScreens]' passed (1 seconds)." \
  'Executed 1 test, with 0 failures (0 unexpected)' '** TEST EXECUTE SUCCEEDED **' > "$W/pass.log"
cp "$W/pass.log" "$W/test.log"
check successful-test pass 0 0
check process-failure fail 65 0
check cutoff fail 0 1
printf "%s\n" "Test Case '-[KitUITests.KitUITests testScreens]' failed (1 seconds)." \
  'Executed 1 test, with 1 failure (0 unexpected)' '** BUILD INTERRUPTED **' > "$W/test.log"
check xctest-failure-even-with-zero-status fail 0 0
cat "$W/pass.log" >> "$W/test.log"
check earlier-failure-not-hidden-by-later-success fail 0 0
printf "%s\n" "Test Case '-[KitUITests.KitUITests testScreens]' passed (1 seconds)." \
  'Executed 1 test, with 0 failures (0 unexpected)' > "$W/test.log"
check incomplete-xcodebuild fail 0 0
printf '%s\n' 'Executed 0 tests, with 0 failures' '** TEST EXECUTE SUCCEEDED **' > "$W/test.log"
check zero-tests fail 0 0
: > "$W/test.log"
check empty-log fail 0 0
rm "$W/test.log"
check missing-log fail 0 0
echo "TEST RESULT SELFTEST OK ($PASS cases)"
