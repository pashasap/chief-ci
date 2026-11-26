#!/bin/bash
# The journeys job (D-20261126-p-66, issue #86): one xcodebuild run per journey, so a hung journey costs only itself.
# `ci/journeys.txt` holds one line per journey: <test method> <journey id> <1 when it starts from a fresh install>.
# Before a fresh journey the app is uninstalled; xcodebuild installs it again, so the journey starts the way a new
# user starts. Nothing else is set: no launch argument, no file, no state. The runner tells the player that the
# install is fresh through TEST_RUNNER_JOURNEY_FRESH (xcodebuild hands TEST_RUNNER_* to the test runner), and names
# the app whose development event log the player reads through TEST_RUNNER_JOURNEY_APP_ID (issue #88). After each
# journey the whole event log of the app is kept as events/<journey>.log.
#   $1 = no journey starts later than this many seconds after JOB_T0; PER_JOURNEY_S bounds one journey's run.
set +e
CUTOFF=$1; PER_JOURNEY_S=${PER_JOURNEY_S:-300}
A=ci/journey-artifacts; mkdir -p $A/logs /tmp/journeys
XTR=$(ls ci/DD/Build/Products/*.xctestrun | head -1)
APP=$(ls -d ci/*.xcodeproj | head -1); APP=$(basename "$APP" .xcodeproj)
xcrun simctl boot "$SIM_UDID" > /dev/null 2>&1 < /dev/null
xcrun simctl bootstatus "$SIM_UDID" -b > /dev/null < /dev/null
echo "TIMING booted at $(( $(date +%s) - JOB_T0 ))s" | tee -a $A/timing.txt
xcrun simctl ui "$SIM_UDID" appearance "${AUDIT_APPEARANCE:-light}" < /dev/null
while read -r METHOD ID FRESH <&3; do
  [ -z "$METHOD" ] && continue
  now=$(( $(date +%s) - JOB_T0 ))
  if [ $now -gt $CUTOFF ]; then
    echo "OUTCOME cutoff at $CUTOFF s: journey $ID and the ones after it did not start" | tee -a $A/outcome.txt
    break
  fi
  if [ "$FRESH" = "1" ] && ! xcrun simctl uninstall "$SIM_UDID" "com.example.$APP" >/dev/null 2>&1 </dev/null; then
    C=$(xcrun simctl get_app_container "$SIM_UDID" "com.example.$APP" data 2>/dev/null </dev/null)
    if [ -n "$C" ]; then
      echo "OUTCOME journey $ID did not start: the old app is still installed" | tee -a $A/outcome.txt
      continue
    fi
  fi
  echo "JOURNEY $ID begin at ${now}s fresh=$FRESH" | tee -a $A/timing.txt
  TEST_RUNNER_JOURNEY_FRESH=$FRESH TEST_RUNNER_JOURNEY_APP_ID="com.example.$APP" NSUnbufferedIO=YES xcodebuild test-without-building -xctestrun "$XTR" \
    -destination "platform=iOS Simulator,id=$SIM_UDID" \
    -test-timeouts-enabled YES -default-test-execution-time-allowance 180 -maximum-test-execution-time-allowance 180 \
    -parallel-testing-enabled NO -resultBundlePath "$A/$ID.xcresult" \
    "-only-testing:AuditStopsUITests/JourneyPlayerUITests/$METHOD" > "$A/logs/$ID.log" 2>&1 < /dev/null &
  pid=$!; waited=0
  while kill -0 $pid 2>/dev/null; do
    sleep 1; waited=$((waited+1))
    if [ $waited -ge $PER_JOURNEY_S ]; then
      echo "OUTCOME journey $ID was stopped after $PER_JOURNEY_S s" | tee -a $A/outcome.txt
      kill $pid 2>/dev/null; sleep 5; kill -9 $pid 2>/dev/null; break
    fi
  done
  wait $pid 2>/dev/null
  rm -rf "$A/$ID.xcresult"
  C=$(xcrun simctl get_app_container "$SIM_UDID" "com.example.$APP" data 2>/dev/null < /dev/null)
  if [ -n "$C" ] && [ -f "$C/Library/Caches/factory-events/events.log" ]; then
    mkdir -p $A/events; cp "$C/Library/Caches/factory-events/events.log" "$A/events/$ID.log"
  fi
  echo "JOURNEY $ID end at $(( $(date +%s) - JOB_T0 ))s" | tee -a $A/timing.txt
done 3< ci/journeys.txt
pkill -x AuditStopsUITests-Runner 2>/dev/null
xcrun simctl shutdown "$SIM_UDID" > /dev/null 2>&1 < /dev/null & p=$!
for _ in $(seq 1 15); do kill -0 $p 2>/dev/null || break; sleep 1; done
echo "TIMING journeys done at $(( $(date +%s) - JOB_T0 ))s" | tee -a $A/timing.txt
true
