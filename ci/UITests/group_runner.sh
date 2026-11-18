#!/usr/bin/env bash
# Host side of one stop group of the Kit simulator audit.
#
#   bash ci/UITests/group_runner.sh <xl|light>
#
# One group = one CI step with its own timeout and its own artifact directory. The step's exit status is the
# group's real status: it is never masked (F-327ab0). A group passes only when the test command exited 0, the log
# carries the XCTest completion marker ("Executed N tests"), the exact method this group selected reported an
# explicit pass, that method was not skipped, the log has no failure line, "** TEST SUCCEEDED **" is present, no
# test writer survived the reap, every shot the test logged exists in the uploaded directory, every required named
# stop is both logged and uploaded, and every host request verified its postcondition.
#
# Environment: SIM_UDID, RUNNER_TEMP (cert dir), GITHUB_WORKSPACE, GROUP_BUDGET_S, MIN_SHOTS, REQUIRE_SHOTS,
# KIT_CTL_DIR, KIT_SHOTS_DIR.
# Local dry run (no simulator, no xcodebuild): GROUP_DRY=1 GROUP_DRY_LOG=<a test.log> GROUP_DRY_DIR=<artifacts dir>.
# A dry run uses private working paths under its artifact directory by default and refuses the shared /tmp ones.
set -uo pipefail

GROUP=${1:-}
case "$GROUP" in
  xl)
    TEST_NAME=testXLOfflineLandscape
    BUDGET=${GROUP_BUDGET_S:-660}
    MIN=${MIN_SHOTS:-40}
    REQUIRED_SHOTS="50-xl-inbox,57-xl-dark-inbox,50b-xxxl-inbox,51b-xxxl-inbox-scrolled,52b-xxxl-today,52b-xxxl-today-seg-2,52b-xxxl-today-seg-3,52b-xxxl-today-seg-4,53b-xxxl-today-scrolled,54b-xxxl-record,54-xl-brief,55-xl-settings,70-offline-inbox,71-offline-approve-tapped,75-offline-settings,80-landscape-inbox,81-landscape-today,82-landscape-brief,83-landscape-settings"
    ;;
  light)
    TEST_NAME=testLightActions
    BUDGET=${GROUP_BUDGET_S:-780}
    MIN=${MIN_SHOTS:-40}
    REQUIRED_SHOTS="05-inbox-top,07-capture-sheet,08-item-detail,15-today-1,22-brief,24-result-sheet,26-share-sheet,27-settings,30-record-prompt,40-dark-inbox,46-dark-settings"
    ;;
  *) echo "usage: group_runner.sh <xl|light>" >&2; exit 64 ;;
esac

DRY=${GROUP_DRY:-0}
SIM=${SIM_UDID:-}
CERT="${RUNNER_TEMP:-/tmp}/cert"
TOKEN=kit-sim-invented-token-0001
LINK="chief://pair?base=https%3A%2F%2Flocalhost%3A8443&token=${TOKEN}"
REQLOG=ci/artifacts/requests.jsonl
A=${GROUP_DRY_DIR:-ci/artifacts/$GROUP}

# Working paths. A real run uses the simulator-shared /tmp directories; a dry run keeps everything under its own
# artifact directory by default, so the gate can never disturb a live group's files, and it refuses the shared
# paths outright.
if [ "$DRY" = "1" ]; then
  CTL=${KIT_CTL_DIR:-$A/kitctl}
  SHOTS=${KIT_SHOTS_DIR:-$A/kitshots}
else
  CTL=${KIT_CTL_DIR:-/tmp/kitctl}
  SHOTS=${KIT_SHOTS_DIR:-/tmp/kitshots}
fi
if [ "$DRY" = "1" ]; then
  case "$CTL" in /tmp/kitctl) echo "refusing shared ctl dir $CTL in dry mode" >&2; exit 65 ;; esac
  case "$SHOTS" in /tmp/kitshots) echo "refusing shared shots dir $SHOTS in dry mode" >&2; exit 65 ;; esac
fi

mkdir -p "$A/shots" "$A/stall" ci/artifacts "$SHOTS"
rm -rf "$CTL"; mkdir -p "$CTL"
rm -f "$SHOTS"/*.png
LOG=$A/test.log; : > "$LOG"
T0=$(date +%s)
CUTOFF=0; RC=0; WRITERS=0
EXPECT="KitUITests/KitUITests/$TEST_NAME"

RS=""
if [ "$DRY" != "1" ] || [ -n "${REQUIRE_SHOTS:-}" ]; then RS=${REQUIRE_SHOTS:-$REQUIRED_SHOTS}; fi

echo "== group=$GROUP test=$TEST_NAME expected=$EXPECT budget=${BUDGET}s artifacts=$A dry=$DRY"
echo "paths group=$GROUP ctl=$CTL shots=$SHOTS artifacts=$A dry=$DRY"
echo "required_shots=${RS:-none}"

health () {
  curl -s --max-time 5 -o /dev/null -w "stub health http=%{http_code} $1\n" --cacert "$CERT/ca.pem" \
    -H "Authorization: Bearer ***" -H 'Content-Type: application/x-kit-probe' \
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
    for f in "$SHOTS"/*.png; do
      [ -e "$f" ] && cp -f "$f" "$A/shots/" 2>/dev/null
    done
    sleep 1
  done
}

copy_shots () {
  for f in "$SHOTS"/*.png; do
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

# Pairing verdict from the stub request log, from an action-specific checkpoint. Only an explicit checkpersisted
# request may accept a snapshot that predates the request (the intentional persisted-session control); a claim of
# fresh typed-link or fallback pairing must rest on records written after the action started.
pairing () {
  local req=$1 since allow=""
  case "$req" in
    checkpair) since=$(cat "$CTL/pair-since" 2>/dev/null || echo "$BASE") ;;
    checkpairtwo) since=$(cat "$CTL/openurl-since" 2>/dev/null || echo "$BASE") ;;
    checkpersisted) since=$BASE; allow="--allow-earlier-snapshot" ;;
    *) since=$BASE ;;
  esac
  python3 ci/UITests/pairing_status.py --log "$REQLOG" --since "$since" --wait 30 $allow \
    --out "$CTL/$req-status" >> "$A/pairing.txt" 2>&1
  local verdict; verdict=$(cat "$CTL/$req-status" 2>/dev/null)
  {
    echo "pairing $req group_baseline=$BASE action_checkpoint=$since allow_earlier_snapshot=${allow:+yes}"
    echo "pairing $req verdict=${verdict:-missing}"
  } >> "$A/pairing.txt"
  printf '%s' "$verdict"
}

do_request () {
  local req=$1 verdict
  case "$req" in
    checkpair|checkpairtwo|checkpersisted)
      verdict=$(pairing "$req")
      if [ "$verdict" = "paired" ]; then
        printf 'ok\n' > "$CTL/$req-result"; : > "$CTL/$req-ok"
      else
        printf 'fail rc=1 verdict=%s\n' "${verdict:-missing}" > "$CTL/$req-result"
      fi
      echo "host did $req verdict=${verdict:-missing} at t=$(( $(date +%s) - T0 ))s"
      ;;
    *)
      bash ci/UITests/host_request.sh "$req" --ctl "$CTL" --sim "$SIM" \
        --pidfile "${RUNNER_TEMP:-/tmp}/stub.pid" --reqlog "$REQLOG" --url "$LINK" \
        --health-url https://localhost:8443/v1/health --cacert "$CERT/ca.pem" --token "$TOKEN" \
        2>&1 | sed "s/^/host /"
      ;;
  esac
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
XCR_STATE=dry
if [ "$DRY" = "1" ]; then
  [ -n "${GROUP_DRY_LOG:-}" ] && cp "$GROUP_DRY_LOG" "$LOG"
  echo "dry run: no xcodebuild; log seeded from ${GROUP_DRY_LOG:-nothing}"
else
  XTR=$(ls ci/DD/Build/Products/*.xctestrun 2>/dev/null | head -1)
  echo "xctestrun=$XTR"
  RESULT=$A/TestResults.xcresult
  rm -rf "$RESULT"
  NSUnbufferedIO=YES xcodebuild test-without-building -xctestrun "$XTR" \
    -destination "platform=iOS Simulator,id=$SIM" \
    -resultBundlePath "$RESULT" \
    -only-testing:"KitUITests/KitUITests/$TEST_NAME" > "$LOG" 2>&1 &
  PID=$!
  XCR_STATE=absent
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
    if [ "$done_at" -eq 0 ] && grep -qE "Test Case .*(passed|failed|skipped)" "$LOG"; then done_at=$i; fi
    if [ "$done_at" -gt 0 ] && [ $((i - done_at)) -ge 8 ]; then
      echo "test finished; stopping lingering xcodebuild"; break
    fi
    # A checkpoint request must be handled before the request that reads it, so mark* goes first even when both
    # appeared in the same second.
    REQS=$(grep -oE "REQUEST [a-z]+$" "$LOG" | awk '{print $2}' | sort -u)
    for req in $(printf '%s\n' $REQS | grep '^mark' 2>/dev/null) $(printf '%s\n' $REQS | grep -v '^mark' 2>/dev/null); do
      [ -f "$CTL/$req-result" ] && continue
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
echo "writers after reap=$WRITERS shots on disk after final copy=$(ls "$SHOTS"/*.png 2>/dev/null | wc -l | tr -d ' ')"

if [ "$DRY" != "1" ]; then
  if [ -f "$RUNNER_TEMP/stub.pid" ]; then kill "$(cat "$RUNNER_TEMP/stub.pid")" 2>/dev/null; fi
  health end
  if [ -d "$A/TestResults.xcresult" ]; then
    XCR_STATE=present
    {
      echo "== xcresulttool test-results summary"
      xcrun xcresulttool get test-results summary --path "$A/TestResults.xcresult" 2>&1 \
        || xcrun xcresulttool get --path "$A/TestResults.xcresult" --format json 2>&1
    } > "$A/xcresult-summary.txt"
    echo "xcresult bundle present; $(wc -c < "$A/xcresult-summary.txt" | tr -d ' ') bytes summarised into $A/xcresult-summary.txt"
    head -c 1200 "$A/xcresult-summary.txt"
  else
    echo "no xcresult bundle at $A/TestResults.xcresult"
  fi
fi

# ---- result propagation -------------------------------------------------------------------------------
EXECUTED=$(grep -oE "Executed [0-9]+ tests?" "$LOG" | tail -1 | grep -oE "[0-9]+")
EXECUTED=${EXECUTED:-0}
SUCCEEDED=0; grep -qE "\*\* TEST SUCCEEDED \*\*" "$LOG" && SUCCEEDED=1
FAIL_LINES=$(grep -E "Test Case .* failed|\*\* TEST FAILED \*\*| error: " "$LOG" | head -20)

# The method this group selected must report its own outcome: an aggregate green, or another method's pass, is not
# evidence that this stop ran (episode 20). A skipped or absent method is UNSEEN, never a pass. The log spells the
# method as "-[KitUITests.KitUITests <method>]"; the slash form is only how the runner selects it.
EXPECT_CASE="KitUITests.KitUITests $TEST_NAME"
OBSERVED=absent
grep -qF "Test Case '-[$EXPECT_CASE]' passed" "$LOG" && OBSERVED=passed
grep -qF "Test Case '-[$EXPECT_CASE]' failed" "$LOG" && OBSERVED=failed
grep -qE "Test Case '-\[$EXPECT_CASE\]'.*(skipped)" "$LOG" && OBSERVED=skipped
echo "expected=$EXPECT_CASE observed=$OBSERVED executed=${EXECUTED} testSucceededLine=${SUCCEEDED} failureLines=$(printf '%s' "$FAIL_LINES" | grep -c . )"

STATUS=PASS
REASONS=()
if [ "$CUTOFF" = "1" ]; then STATUS=FAIL; REASONS+=("group cutoff at ${BUDGET}s: the traverse did not finish"); fi
if [ "$RC" -ne 0 ]; then STATUS=FAIL; REASONS+=("test command exited rc=$RC"); fi
if [ "$EXECUTED" -lt 1 ]; then STATUS=FAIL; REASONS+=("no XCTest completion marker 'Executed N tests' in test.log"); fi
if [ "$SUCCEEDED" = "0" ]; then STATUS=FAIL; REASONS+=("no '** TEST SUCCEEDED **' line in test.log"); fi
if [ -n "$FAIL_LINES" ]; then STATUS=FAIL; REASONS+=("failure lines in test.log (first: $(printf '%s' "$FAIL_LINES" | head -1 | cut -c1-160))"); fi
if [ "$WRITERS" != "0" ]; then STATUS=FAIL; REASONS+=("$WRITERS test writer(s) survived the reap"); fi
if [ "$OBSERVED" != "passed" ]; then
  STATUS=FAIL; REASONS+=("expected an explicit pass for $EXPECT_CASE, observed $OBSERVED")
fi

INVARGS=(--log "$LOG" --dir "$A/shots" --out "$A/inventory.txt" --require "$MIN")
[ -n "$RS" ] && INVARGS+=(--require-shots "$RS")
python3 ci/UITests/shot_inventory.py "${INVARGS[@]}"
INV=$?
if [ "$INV" -ne 0 ]; then STATUS=FAIL; REASONS+=("shot inventory mismatch: see $A/inventory.txt"); fi

# Host requests: every request the test asked for must have answered with a verified postcondition.
REQ_LINES=""
for f in "$CTL"/*-result; do
  [ -e "$f" ] || continue
  n=$(basename "$f" -result); v=$(tr -d '\n' < "$f")
  REQ_LINES="$REQ_LINES $n=[$v]"
  case "$v" in
    ok) ;;
    *) STATUS=FAIL; REASONS+=("host request $n did not verify: $v") ;;
  esac
done
for req in $(grep -oE "REQUEST [a-z]+$" "$LOG" | awk '{print $2}' | sort -u); do
  [ -f "$CTL/$req-result" ] || { STATUS=FAIL; REASONS+=("host request $req was asked for and never answered"); }
done
echo "host requests:${REQ_LINES:- none}"
[ -f "$A/pairing.txt" ] && sed 's/^/pairing-log /' "$A/pairing.txt"

echo "---- group $GROUP summary"
echo "GROUP_RESULT group=$GROUP test=$TEST_NAME expected=$EXPECT_CASE observed=$OBSERVED status=$STATUS executed=$EXECUTED rc=$RC cutoff=$CUTOFF writers=$WRITERS shots_logged=$(grep -cE '^KIT [0-9.]+ shot ' "$LOG") shots_uploaded=$(ls "$A/shots" 2>/dev/null | wc -l | tr -d ' ') named_required=$([ -n "$RS" ] && echo yes || echo no) xcresult=$XCR_STATE elapsed=$(( $(date +%s) - T0 ))s"
for r in ${REASONS[@]+"${REASONS[@]}"}; do echo "GROUP_REASON $r"; done
{ echo "GROUP_RESULT group=$GROUP test=$TEST_NAME expected=$EXPECT_CASE observed=$OBSERVED status=$STATUS executed=$EXECUTED rc=$RC cutoff=$CUTOFF writers=$WRITERS shots_uploaded=$(ls "$A/shots" 2>/dev/null | wc -l | tr -d ' ') named_required=$([ -n "$RS" ] && echo yes || echo no) xcresult=$XCR_STATE"
  for r in ${REASONS[@]+"${REASONS[@]}"}; do echo "GROUP_REASON $r"; done
  [ -f "$A/pairing.txt" ] && cat "$A/pairing.txt"; } > "$A/summary.txt"
grep "KIT " "$LOG" | grep -v " shot " | cut -c1-300 | tail -60

if [ "$STATUS" = "PASS" ]; then echo "group $GROUP: PASS"; exit 0; fi
echo "group $GROUP: FAIL"; exit 1
