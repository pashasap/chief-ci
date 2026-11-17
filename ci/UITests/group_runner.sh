#!/usr/bin/env bash
# Host side of one stop group of the Kit simulator audit.
#
#   bash ci/UITests/group_runner.sh <xl|light>
#
# One group = one CI step with its own timeout and its own artifact directory. The step's exit status is the
# group's real status: it is never masked (F-327ab0). A group passes only when the test command exited 0, the log
# carries the XCTest completion marker ("Executed N tests"), the log has no failure line, "** TEST SUCCEEDED **" is
# present, no test writer survived the reap, and every shot the test logged exists in the uploaded directory
# (F-61f096 and the lost-shot fault).
#
# Environment: SIM_UDID, RUNNER_TEMP (cert dir), GITHUB_WORKSPACE, GROUP_BUDGET_S, MIN_SHOTS.
# Local dry run (no simulator, no xcodebuild): GROUP_DRY=1 GROUP_DRY_LOG=<a test.log> GROUP_DRY_DIR=<artifacts dir>.
set -uo pipefail

GROUP=${1:-}
case "$GROUP" in
  xl)    TEST_NAME=testXLOfflineLandscape; BUDGET=${GROUP_BUDGET_S:-660}; MIN=${MIN_SHOTS:-40} ;;
  light) TEST_NAME=testLightActions;       BUDGET=${GROUP_BUDGET_S:-780}; MIN=${MIN_SHOTS:-40} ;;
  *) echo "usage: group_runner.sh <xl|light>" >&2; exit 64 ;;
esac

DRY=${GROUP_DRY:-0}
SIM=${SIM_UDID:-}
CERT="${RUNNER_TEMP:-/tmp}/cert"
TOKEN=kit-sim-invented-token-0001
LINK="chief://pair?base=https%3A%2F%2Flocalhost%3A8443&token=${TOKEN}"
REQLOG=ci/artifacts/requests.jsonl
A=${GROUP_DRY_DIR:-ci/artifacts/$GROUP}
mkdir -p "$A/shots" "$A/stall" ci/artifacts /tmp/kitctl /tmp/kitshots
rm -f /tmp/kitctl/* /tmp/kitshots/*.png
LOG=$A/test.log; : > "$LOG"
T0=$(date +%s)
CUTOFF=0; RC=0; WRITERS=0
echo "== group=$GROUP test=$TEST_NAME budget=${BUDGET}s artifacts=$A dry=$DRY"

health () {
  curl -s --max-time 5 -o /dev/null -w "stub health http=%{http_code} $1\n" --cacert "$CERT/ca.pem" \
    -H "Authorization: Bearer ${TOKEN}" -H 'Content-Type: application/x-kit-probe' \
    https://localhost:8443/v1/health
}

start_stub () {
  [ "$DRY" = "1" ] && return 0
  if [ -f "$RUNNER_TEMP/stub.pid" ]; then kill "$(cat "$RUNNER_TEMP/stub.pid")" 2>/dev/null; sleep 1; fi
  nohup python3 -I ci/stub/stub_server.py --fixtures ci/stub/fixtures --cert "$CERT/chain.pem" \
    --key "$CERT/server.key" --token "$TOKEN" --port 8443 \
    --log "${GITHUB_WORKSPACE:-$PWD}/$REQLOG" > "$A/stub.out" 2>&1 &
  echo $! > "$RUNNER_TEMP/stub.pid"
  for _ in $(seq 1 20); do
    curl -s --max-time 3 --cacert "$CERT/ca.pem" -o /dev/null https://localhost:8443/ && break
    sleep 0.5
  done
}

# Mirrors each shot into the upload directory as it is written, so a later timeout cannot lose the inventory.
mirror_loop () {
  while :; do
    for f in /tmp/kitshots/*.png; do
      [ -e "$f" ] && cp -f "$f" "$A/shots/" 2>/dev/null
    done
    sleep 1
  done
}

copy_shots () {
  for f in /tmp/kitshots/*.png; do
    [ -e "$f" ] && cp -f "$f" "$A/shots/" 2>/dev/null
  done
}

# Kills a process and every descendant it still owns (xcodebuild -> XCTest runner -> app under test).
reap_tree () {
  local root=$1 k
  [ -z "$root" ] && return 0
  for k in $(pgrep -P "$root" 2>/dev/null); do reap_tree "$k"; done
  kill -TERM "$root" 2>/dev/null
  return 0
}

pairing () {
  python3 ci/UITests/pairing_status.py --log "$REQLOG" --since "$BASE" --wait 30 \
    --allow-earlier-snapshot --out "/tmp/kitctl/$1-status" | sed "s/^/pairing $1: /"
}

do_request () {
  local req=$1 rc=0
  case "$req" in
    openurl) xcrun simctl openurl "$SIM" "$LINK" ;;
    dark) xcrun simctl ui "$SIM" appearance dark ;;
    light) xcrun simctl ui "$SIM" appearance light ;;
    stopstub) [ -f "$RUNNER_TEMP/stub.pid" ] && kill "$(cat "$RUNNER_TEMP/stub.pid")" 2>/dev/null ;;
    revokemic) xcrun simctl privacy "$SIM" revoke microphone com.example.Chief ;;
    checkpair|checkpairtwo) pairing "$req" ;;
    *) echo "unknown host request $req"; rc=2 ;;
  esac
  rc=$?
  echo "host did $req rc=$rc at t=$(( $(date +%s) - T0 ))s"
  touch "/tmp/kitctl/$req-ok"
  health "after $req"
}

if [ "$DRY" != "1" ]; then
  # Group light needs the microphone granted again: the XL group revokes it to prove the denied path.
  [ "$GROUP" = "light" ] && xcrun simctl privacy "$SIM" grant microphone com.example.Chief 2>/dev/null
  start_stub
  health start
fi

BASE=$( [ -f "$REQLOG" ] && wc -l < "$REQLOG" || echo 0 )
echo "request-log lines before this group: $BASE"

mirror_loop & MIRROR=$!

PID=""
if [ "$DRY" = "1" ]; then
  [ -n "${GROUP_DRY_LOG:-}" ] && cp "$GROUP_DRY_LOG" "$LOG"
  echo "dry run: no xcodebuild; log seeded from ${GROUP_DRY_LOG:-nothing}"
else
  XTR=$(ls ci/DD/Build/Products/*.xctestrun 2>/dev/null | head -1)
  echo "xctestrun=$XTR"
  NSUnbufferedIO=YES xcodebuild test-without-building -xctestrun "$XTR" \
    -destination "platform=iOS Simulator,id=$SIM" \
    -only-testing:"KitUITests/KitUITests/$TEST_NAME" > "$LOG" 2>&1 &
  PID=$!
fi

if [ -n "$PID" ]; then
  last=""; same=0; done_at=0; i=0
  while kill -0 "$PID" 2>/dev/null; do
    sleep 1; i=$((i+1))
    if [ $(( $(date +%s) - T0 )) -gt "$BUDGET" ]; then
      echo "GROUP CUTOFF at t=${i}s (budget ${BUDGET}s)"
      CUTOFF=1
      xcrun simctl io "$SIM" screenshot "$A/stall/cutoff.png" > /dev/null 2>&1
      break
    fi
    if [ "$done_at" -eq 0 ] && grep -qE "Test Case .*(passed|failed)" "$LOG"; then done_at=$i; fi
    if [ "$done_at" -gt 0 ] && [ $((i - done_at)) -ge 8 ]; then
      echo "test finished; stopping lingering xcodebuild"; break
    fi
    for req in $(grep -oE "REQUEST [a-z]+$" "$LOG" | awk '{print $2}' | sort -u); do
      [ -f "/tmp/kitctl/$req-ok" ] && continue
      do_request "$req"
    done
    cur=$(grep -c "KIT \|t = " "$LOG")
    if [ "$cur" = "${last:-x}" ]; then same=$((same+1)); else same=0; last=$cur; fi
    if [ "$same" -eq 30 ]; then
      APP=$(pgrep -f "Kit.app/Kit" | head -1)
      echo "STALL? t=$i app=${APP:-none} last=$(grep 'KIT ' "$LOG" | tail -1 | cut -c1-200)" | tee -a "$A/stall/watch.txt"
      xcrun simctl io "$SIM" screenshot "$A/stall/t$i.png" > /dev/null 2>&1
      [ -n "$APP" ] && sample "$APP" 2 -file "$A/stall/t$i-sample.txt" > /dev/null 2>&1
    fi
  done

  # Collection ownership: no writer may survive into the copy.
  echo "reaping test tree root=$PID"
  reap_tree "$PID"; sleep 2
  reap_tree "$PID"; sleep 1
  kill -KILL "$PID" 2>/dev/null
  for _ in $(seq 1 10); do
    pgrep -f "xcodebuild test-without-building" > /dev/null 2>&1 || break
    pkill -TERM -f "xcodebuild test-without-building" 2>/dev/null
    sleep 1
  done
  pkill -KILL -f "xcodebuild test-without-building" 2>/dev/null
  wait "$PID" 2>/dev/null; RC=$?
  echo "test command rc=$RC after reap"
fi

kill "$MIRROR" 2>/dev/null; wait "$MIRROR" 2>/dev/null
copy_shots
WRITERS=$(pgrep -f "xcodebuild test-without-building" | wc -l | tr -d ' ')
echo "writers after reap=$WRITERS shots on disk after final copy=$(ls /tmp/kitshots/*.png 2>/dev/null | wc -l | tr -d ' ')"

if [ "$DRY" != "1" ]; then
  if [ -f "$RUNNER_TEMP/stub.pid" ]; then kill "$(cat "$RUNNER_TEMP/stub.pid")" 2>/dev/null; fi
  health end
fi

# ---- result propagation -------------------------------------------------------------------------------
EXECUTED=$(grep -oE "Executed [0-9]+ tests?" "$LOG" | tail -1 | grep -oE "[0-9]+")
EXECUTED=${EXECUTED:-0}
SUCCEEDED=0; grep -qE "\*\* TEST SUCCEEDED \*\*" "$LOG" && SUCCEEDED=1
FAIL_LINES=$(grep -E "Test Case .* failed|\*\* TEST FAILED \*\*| error: " "$LOG" | head -20)
echo "executed=${EXECUTED} testSucceededLine=${SUCCEEDED} failureLines=$(printf '%s' "$FAIL_LINES" | grep -c . )"

STATUS=PASS
REASONS=()
if [ "$CUTOFF" = "1" ]; then STATUS=FAIL; REASONS+=("group cutoff at ${BUDGET}s: the traverse did not finish"); fi
if [ "$RC" -ne 0 ]; then STATUS=FAIL; REASONS+=("test command exited rc=$RC"); fi
if [ "$EXECUTED" -lt 1 ]; then STATUS=FAIL; REASONS+=("no XCTest completion marker 'Executed N tests' in test.log"); fi
if [ "$SUCCEEDED" = "0" ]; then STATUS=FAIL; REASONS+=("no '** TEST SUCCEEDED **' line in test.log"); fi
if [ -n "$FAIL_LINES" ]; then STATUS=FAIL; REASONS+=("failure lines in test.log (first: $(printf '%s' "$FAIL_LINES" | head -1 | cut -c1-160))"); fi
if [ "$WRITERS" != "0" ]; then STATUS=FAIL; REASONS+=("$WRITERS test writer(s) survived the reap"); fi

python3 ci/UITests/shot_inventory.py --log "$LOG" --dir "$A/shots" --out "$A/inventory.txt" --require "$MIN"
INV=$?
if [ "$INV" -ne 0 ]; then STATUS=FAIL; REASONS+=("shot inventory mismatch: see $A/inventory.txt"); fi

echo "---- group $GROUP summary"
echo "GROUP_RESULT group=$GROUP test=$TEST_NAME status=$STATUS executed=$EXECUTED rc=$RC cutoff=$CUTOFF writers=$WRITERS shots_logged=$(grep -cE '^KIT [0-9.]+ shot ' "$LOG") shots_uploaded=$(ls "$A/shots" 2>/dev/null | wc -l | tr -d ' ') elapsed=$(( $(date +%s) - T0 ))s"
for r in ${REASONS[@]+"${REASONS[@]}"}; do echo "GROUP_REASON $r"; done
{ echo "GROUP_RESULT group=$GROUP test=$TEST_NAME status=$STATUS executed=$EXECUTED rc=$RC cutoff=$CUTOFF writers=$WRITERS shots_uploaded=$(ls "$A/shots" 2>/dev/null | wc -l | tr -d ' ') elapsed=$(( $(date +%s) - T0 ))s"
  for r in ${REASONS[@]+"${REASONS[@]}"}; do echo "GROUP_REASON $r"; done; } > "$A/summary.txt"
grep "KIT " "$LOG" | grep -v " shot " | cut -c1-300 | tail -60

if [ "$STATUS" = "PASS" ]; then echo "group $GROUP: PASS"; exit 0; fi
echo "group $GROUP: FAIL"; exit 1
