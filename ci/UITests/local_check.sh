#!/usr/bin/env bash
# Pre-push gate for this harness, with no local paths, names or addresses in it (the public scanner rejects them).
#
#   bash ci/UITests/local_check.sh
#
# Checks, in order:
#   1. bash -n on every shell script and on every workflow shell block, plus a PyYAML parse of the workflows.
#   2. Both helper self-tests (pairing verdict, shot inventory).
#   3. Dry-run isolation: a GROUP_DRY=1 run uses private working paths, refuses the shared /tmp ones, and leaves
#      /tmp/kitctl and /tmp/kitshots byte-for-byte as it found them.
#   4. The exact-method propagation replay (episode 20): eight synthetic logs, one verdict each.
#   5. The host-request postconditions (episode 19): six replayed requests with stubbed externals.
#   6. The required-group verdict (episode 15): seven replayed outcome pairs through the same script the workflow
#      runs.
# Exit 0 only when every case matched its expectation.
set -uo pipefail
cd "$(dirname "$0")/../.."
FAIL=0
TMP=$(mktemp -d "${TMPDIR:-/tmp}/groupdry-XXXXXX")

ok () { echo "PASS $*"; }
no () { FAIL=1; echo "FAIL $*"; }

echo "== bash -n (scripts)"
for s in ci/UITests/*.sh ci/stub/*.sh; do
  if bash -n "$s"; then ok "$s"; else no "$s"; fi
done

echo "== workflow parse and shell blocks"
# PyYAML lives in the system interpreter here, not necessarily in whatever python3 is first on PATH.
PY=""
for c in python3 /usr/bin/python3 /usr/bin/python; do
  if command -v "$c" > /dev/null 2>&1 && "$c" -c 'import yaml' 2>/dev/null; then PY=$c; break; fi
done
if [ -z "$PY" ]; then echo "no interpreter with PyYAML; cannot parse the workflows"; exit 1; fi
echo "parser: $PY"
"$PY" - <<'PY' || FAIL=1
import glob, subprocess, sys, tempfile, os
try:
    import yaml
except ImportError:
    print("PyYAML missing; cannot parse the workflows")
    sys.exit(1)
bad = 0
for path in sorted(glob.glob(".github/workflows/*.yml")):
    doc = yaml.safe_load(open(path))
    jobs = doc.get("jobs") or doc.get(True)["jobs"]
    trig = doc.get("on", doc.get(True))
    print("parsed {} jobs={} triggers={}".format(path, sorted(jobs),
                                                 sorted(trig) if isinstance(trig, dict) else trig))
    for job, body in jobs.items():
        for step in body.get("steps", []):
            script = step.get("run")
            if not script:
                continue
            with tempfile.NamedTemporaryFile("w", suffix=".sh", delete=False) as f:
                f.write(script)
                tmp = f.name
            rc = subprocess.run(["bash", "-n", tmp], capture_output=True, text=True)
            os.unlink(tmp)
            label = "{} / {}".format(job, step.get("name", "?"))
            if rc.returncode:
                bad = 1
                print("bash -n FAIL: {} :: {}".format(label, rc.stderr.strip()[:300]))
            else:
                print("bash -n ok: " + label)
sys.exit(bad)
PY

echo "== helper self-tests"
"$PY" ci/UITests/pairing_status.py --self-test || FAIL=1
"$PY" ci/UITests/shot_inventory.py --self-test || FAIL=1

echo "== workflow wiring (the step must run the gate's own scripts, not a copy)"
grep -q 'bash ci/UITests/verdict.sh' .github/workflows/sim-audit.yml \
  && ok "verdict step calls ci/UITests/verdict.sh" || no "verdict step does not call ci/UITests/verdict.sh"
grep -q 'UISupportedInterfaceOrientations~ipad' .github/workflows/sim-audit.yml \
  && ok "build step prints both orientation arrays" || no "build step does not print UISupportedInterfaceOrientations~ipad"
grep -q 'source-manifest.txt' .github/workflows/sim-audit.yml \
  && ok "workflow mentions source-manifest.txt" || no "workflow does not mention source-manifest.txt"
[ "$(grep -c 'ci/artifacts/source-manifest.txt' .github/workflows/sim-audit.yml)" -ge 2 ] \
  && ok "source-manifest.txt is in both artifact uploads" || no "source-manifest.txt is not in both uploads"

echo "== fixture logs for the propagation replay"
mklog () {
  local f=$1 mode=$2
  {
    printf '%s\n' "KIT 1.0 AUDIT begin 01 x" "KIT 1.1 shot dry-01" "KIT 1.2 shot dry-02"
    case "$mode" in
      xl-layout-pass)
        printf '%s\n' "Test Case '-[KitUITests.KitUITests testXLLayout]' passed (1.0 seconds)." \
          "Test Suite 'KitUITests' passed at 2026-11-18 00:00:00.000." \
          "Executed 1 test, with 0 failures (0 unexpected) in 1.0 (1.0) seconds" \
          "** TEST SUCCEEDED **" ;;
      xl-execute-banner)
        # `xcodebuild test-without-building` ends with this banner instead. Run 44218947277's light group was green
        # in its xcresult and still reported FAIL because only the other spelling was accepted (episode 27).
        printf '%s\n' "Test Case '-[KitUITests.KitUITests testXLLayout]' passed (1.0 seconds)." \
          "Test Suite 'KitUITests' passed at 2026-11-18 00:00:00.000." \
          "Executed 1 test, with 0 failures (0 unexpected) in 1.0 (1.0) seconds" \
          "** TEST EXECUTE SUCCEEDED **" ;;
      light-pass)
        printf '%s\n' "Test Case '-[KitUITests.KitUITests testLightActions]' passed (1.0 seconds)." \
          "Test Suite 'KitUITests' passed at 2026-11-18 00:00:00.000." \
          "Executed 1 test, with 0 failures (0 unexpected) in 1.0 (1.0) seconds" \
          "** TEST SUCCEEDED **" ;;
      xl-layout-skipped)
        printf '%s\n' "Test Case '-[KitUITests.KitUITests testXLLayout]' skipped (0.5 seconds)." \
          "Executed 1 test, with 0 failures (0 unexpected) in 0.5 (0.5) seconds" \
          "** TEST SUCCEEDED **" ;;
      aggregate)
        printf '%s\n' "Test Suite 'KitUITests' passed at 2026-11-18 00:00:00.000." \
          "Executed 1 test, with 0 failures (0 unexpected) in 1.0 (1.0) seconds" \
          "** TEST SUCCEEDED **" ;;
      xl-layout-failed)
        printf '%s\n' "Test Case '-[KitUITests.KitUITests testXLLayout]' failed (1.0 seconds)." \
          "Executed 1 test, with 1 failure (0 unexpected) in 1.0 (1.0) seconds" \
          "** TEST FAILED **" ;;
      zero-executed)
        printf '%s\n' "Test Case '-[KitUITests.KitUITests testXLLayout]' passed (1.0 seconds)." \
          "Executed 0 tests, with 0 failures (0 unexpected) in 0.0 (0.0) seconds" \
          "** TEST SUCCEEDED **" ;;
      *) no "mklog: unknown mode $mode" ;;
    esac
  } > "$f"
}

# A dry group run: private artifacts, seeded log, two collected PNGs. Sets RC.
drygroup () { # <dir> <seed> <group>
  RC=0
  GROUP_DRY=1 GROUP_DRY_LOG="$2" GROUP_DRY_DIR="$1" MIN_SHOTS=2 \
    bash ci/UITests/group_runner.sh "$3" > "$1.out" 2>&1 || RC=$?
}

fingerprint () {
  for p in /tmp/kitctl /tmp/kitshots; do
    if [ -e "$p" ]; then echo "== $p"; ls -la "$p" 2>/dev/null; else echo "== $p absent"; fi
  done
}

echo "== dry-run isolation and the propagation replay (episode 20)"
BEFORE=$(fingerprint)
iso=""
for spec in "xl-layout-pass:xl-layout:xl-layout-pass:0" "xl-execute-banner:xl-layout:xl-execute-banner:0" \
            "light-pass:light:light-pass:0" "xl-layout-wrong-method:xl-layout:light-pass:1" \
            "xl-layout-skipped:xl-layout:xl-layout-skipped:1" "xl-layout-aggregate:xl-layout:aggregate:1" \
            "xl-layout-failed:xl-layout:xl-layout-failed:1" "xl-layout-zero-executed:xl-layout:zero-executed:1"; do
  IFS=: read -r label grp mode want <<< "$spec"
  d="$TMP/ep20-$label"
  mkdir -p "$d/shots"
  mklog "$d.seed" "$mode"
  : > "$d/shots/dry-01.png"; : > "$d/shots/dry-02.png"
  drygroup "$d" "$d.seed" "$grp"
  if [ "$RC" -eq "$want" ]; then ok "ep20 $label rc=$RC"; else
    no "ep20 $label rc=$RC want=$want: $(grep -m1 GROUP_REASON "$d.out")"
  fi
  [ -z "$iso" ] && iso=$d
done

# Named stops: the same dry run, once with both names present and once with one never captured.
d="$TMP/ep20-named-present"; mkdir -p "$d/shots"; mklog "$d.seed" xl-layout-pass
: > "$d/shots/dry-01.png"; : > "$d/shots/dry-02.png"
RC=0
GROUP_DRY=1 GROUP_DRY_LOG="$d.seed" GROUP_DRY_DIR="$d" MIN_SHOTS=2 REQUIRE_SHOTS="dry-01,dry-02" \
  bash ci/UITests/group_runner.sh xl-layout > "$d.out" 2>&1 || RC=$?
[ "$RC" -eq 0 ] && ok "ep14 named stops present rc=0" || no "ep14 named stops present rc=$RC want=0: $(grep -m1 GROUP_REASON "$d.out")"

d="$TMP/ep20-named-missing"; mkdir -p "$d/shots"; mklog "$d.seed" xl-layout-pass
: > "$d/shots/dry-01.png"; : > "$d/shots/dry-02.png"
RC=0
GROUP_DRY=1 GROUP_DRY_LOG="$d.seed" GROUP_DRY_DIR="$d" MIN_SHOTS=2 REQUIRE_SHOTS="dry-01,zz-never-shot" \
  bash ci/UITests/group_runner.sh xl-layout > "$d.out" 2>&1 || RC=$?
[ "$RC" -ne 0 ] && ok "ep14 required stop never captured rc=$RC" || no "ep14 required stop never captured rc=0 want!=0"
grep -q 'zz-never-shot' "$d/inventory.txt" 2>/dev/null \
  && ok "ep14 inventory names the missing stop" || no "ep14 inventory does not name the missing stop"

d="$TMP/ep20-lost-shot"; mkdir -p "$d/shots"; mklog "$d.seed" xl-layout-pass
: > "$d/shots/dry-01.png"
drygroup "$d" "$d.seed" xl-layout
[ "$RC" -ne 0 ] && ok "ep20 logged shot missing from disk rc=$RC" || no "ep20 logged shot missing from disk rc=0 want!=0"

# Isolation: the dry runs used private paths and the shared ones were not touched.
grep -q "^paths .*ctl=$TMP/" "$iso.out" 2>/dev/null \
  && ok "dry run kept its ctl dir under the artifact directory" || no "dry run did not use a private ctl dir: $(grep -m1 '^paths' "$iso.out")"
grep -q "^paths .*shots=$TMP/" "$iso.out" 2>/dev/null \
  && ok "dry run kept its shots dir under the artifact directory" || no "dry run did not use a private shots dir"
[ -d "$iso/kitctl" ] && ok "dry run wrote its request markers into its own kitctl" || no "dry run wrote no private kitctl"
RC=0
GROUP_DRY=1 GROUP_DRY_LOG="$iso.seed" GROUP_DRY_DIR="$TMP/ep20-refuse" KIT_CTL_DIR=/tmp/kitctl \
  bash ci/UITests/group_runner.sh xl-layout > "$TMP/refuse.out" 2>&1 || RC=$?
[ "$RC" -eq 65 ] && ok "dry run refuses the shared /tmp/kitctl" || no "dry run did not refuse the shared /tmp/kitctl (rc=$RC)"
AFTER=$(fingerprint)
if [ "$BEFORE" = "$AFTER" ]; then
  ok "shared /tmp/kitctl and /tmp/kitshots are unchanged by the dry runs"
else
  no "the dry runs changed shared /tmp/kitctl or /tmp/kitshots (another process may also have); diff: $(diff <(printf '%s' "$BEFORE") <(printf '%s' "$AFTER") | head -6)"
fi

echo "== host request postconditions (episode 19)"
BIN=$TMP/bin; mkdir -p "$BIN"
cat > "$BIN/xcrun" <<'SHIM'
#!/usr/bin/env bash
case "$*" in
  *" appearance dark"|*" appearance light") exit "${FAKE_UI_RC:-0}" ;;
  *" appearance") echo "${FAKE_UI_VALUE:-dark}"; exit 0 ;;
  *" privacy "*) exit "${FAKE_PRIV_RC:-0}" ;;
  *) exit 0 ;;
esac
SHIM
cat > "$BIN/curl" <<'SHIM'
#!/usr/bin/env bash
if [ -n "${FAKE_HTTP_SEQ:-}" ] && [ -s "${FAKE_HTTP_SEQ}" ]; then
  v=$(head -1 "$FAKE_HTTP_SEQ")
  tail -n +2 "$FAKE_HTTP_SEQ" > "$FAKE_HTTP_SEQ.next"
  mv "$FAKE_HTTP_SEQ.next" "$FAKE_HTTP_SEQ"
  printf '%s' "$v"
  exit 0
fi
printf '%s' "${FAKE_HTTP:-000}"
SHIM
cat > "$BIN/kill" <<'SHIM'
#!/usr/bin/env bash
exit "${FAKE_KILL_RC:-0}"
SHIM
chmod +x "$BIN/xcrun" "$BIN/curl" "$BIN/kill"

# A short-lived real process stands in for the stub, so the wait-for-exit loop is exercised for real.
sleep 0.3 & STUBPID=$!; wait "$STUBPID" 2>/dev/null

hostreq () { # <label> <request> <want result prefix>
  local label=$1 req=$2 want=$3
  local d="$TMP/host-$label"
  rm -rf "$d"; mkdir -p "$d"
  export FAKE_UI_RC FAKE_UI_VALUE FAKE_PRIV_RC FAKE_KILL_RC FAKE_HTTP_SEQ FAKE_HTTP PIDFILE
  PATH="$BIN:$PATH" KIT_XCRUN="$BIN/xcrun" KIT_KILL="$BIN/kill" KIT_CURL="$BIN/curl" \
    bash ci/UITests/host_request.sh "$req" --ctl "$d" --sim FAKE-UDID --pidfile "${PIDFILE:-$TMP/none.pid}" \
      --reqlog "$TMP/requests.jsonl" --url "chief://pair?base=x" \
      --health-url https://localhost:8443/v1/health --cacert "$TMP/ca.pem" --token tok \
      > "$d.out" 2>&1
  local got; got=$(cat "$d/$req-result" 2>/dev/null)
  case "$got" in
    "$want"*) ok "ep19 $label result=[$got]" ;;
    *) no "ep19 $label result=[$got] want=[$want*]" ;;
  esac
  if [ "$want" = "ok" ]; then
    [ -f "$d/$req-ok" ] && ok "ep19 $label wrote the success marker" || no "ep19 $label did not write the success marker"
  else
    [ -f "$d/$req-ok" ] && no "ep19 $label wrote a success marker for a failed request" || ok "ep19 $label wrote no success marker"
  fi
}

: > "$TMP/requests.jsonl"; printf 'a\nb\nc\n' > "$TMP/requests.jsonl"
PIDFILE=""
FAKE_UI_RC=0 FAKE_UI_VALUE=dark hostreq dark-ok dark ok
FAKE_UI_RC=44 FAKE_UI_VALUE=dark hostreq dark-rc44 dark "fail rc=44"
FAKE_PRIV_RC=41 hostreq mic-rc41 revokemic "fail rc=41"

PIDFILE=$TMP/stub.pid; echo "$STUBPID" > "$PIDFILE"
printf '200\n000\n' > "$TMP/seq-ok"
FAKE_KILL_RC=0 FAKE_HTTP_SEQ="$TMP/seq-ok" hostreq stopstub-ok stopstub ok
printf '200\n200\n' > "$TMP/seq-up"
FAKE_KILL_RC=1 FAKE_HTTP_SEQ="$TMP/seq-up" hostreq stopstub-killrc1 stopstub "fail rc=1"
PIDFILE=$TMP/absent.pid
printf '200\n200\n' > "$TMP/seq-up2"
FAKE_KILL_RC=0 FAKE_HTTP_SEQ="$TMP/seq-up2" hostreq stopstub-nopid stopstub "fail rc=98"

# The action checkpoints are the line counts at the moment the test asked for them.
want=$(( $(wc -l < "$TMP/requests.jsonl") ))
FAKE_UI_RC=0 hostreq markpair markpair ok
[ "$(tr -d '[:space:]' < "$TMP/host-markpair/pair-since" 2>/dev/null)" = "$want" ] \
  && ok "ep16 markpair recorded the request-log checkpoint ($want)" || no "ep16 markpair checkpoint is not $want"
FAKE_UI_RC=0 hostreq markopenurl markopenurl ok
[ -f "$TMP/host-markopenurl/openurl-since" ] && ok "ep16 markopenurl recorded its own checkpoint" \
  || no "ep16 markopenurl wrote no checkpoint"

echo "== required-group verdict (episode 15)"
vcase () { # <label> <mode> <xl-layout outcome> <xl-environment outcome> <light outcome> <want rc>
  local label=$1 mode=$2 xl=$3 en=$4 li=$5 want=$6 d="$TMP/v-$1"
  mkdir -p "$d/xl-layout" "$d/xl-environment" "$d/light"
  for g in xl-layout xl-environment light; do
    printf 'GROUP_RESULT group=%s status=PASS executed=1\n' "$g" > "$d/$g/summary.txt"
    printf 'shots logged=30 uploaded=30 unique_logged=30 missing=0 extra=0 required=30 named_required=19\nresult: ok\n' > "$d/$g/inventory.txt"
  done
  local rc=0
  bash ci/UITests/verdict.sh "$mode" "$xl" "$en" "$li" "$d" > "$d.out" 2>&1 || rc=$?
  if [ "$rc" -eq "$want" ]; then ok "ep15 $label rc=$rc"; else
    no "ep15 $label rc=$rc want=$want: $(grep -m1 GROUP_FAILED "$d.out")"
  fi
}
vcase all-both-success all success success success 0
vcase all-light-failed all success success failure 1
vcase all-environment-skipped all success skipped success 1
vcase all-layout-skipped all skipped success success 1
vcase all-both-skipped all skipped skipped skipped 1
vcase xl-layout-only xl-layout success skipped skipped 0
vcase xl-environment-only xl-environment skipped success skipped 0
vcase light-only light skipped skipped success 0

# A group whose evidence did not land cannot be green even with a success outcome.
d="$TMP/v-missing-inventory"; mkdir -p "$d/xl-layout" "$d/xl-environment" "$d/light"
printf 'GROUP_RESULT group=xl-layout status=PASS\n' > "$d/xl-layout/summary.txt"
printf 'GROUP_RESULT group=xl-environment status=PASS\n' > "$d/xl-environment/summary.txt"
printf 'GROUP_RESULT group=light status=PASS\n' > "$d/light/summary.txt"
printf 'result: ok\n' > "$d/light/inventory.txt"
printf 'result: ok\n' > "$d/xl-environment/inventory.txt"
rc=0
bash ci/UITests/verdict.sh all success success success "$d" > "$d.out" 2>&1 || rc=$?
[ "$rc" -eq 1 ] && ok "ep15 missing inventory is red (rc=1)" || no "ep15 missing inventory rc=$rc want=1"

echo "== local check outputs: $TMP"
if [ "$FAIL" -eq 0 ]; then echo "LOCAL CHECK: PASS"; exit 0; fi
echo "LOCAL CHECK: FAIL"; exit 1
