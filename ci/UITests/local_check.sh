#!/usr/bin/env bash
# Pre-push gate for this harness, with no local paths, names or addresses in it (the public scanner rejects them).
#
#   bash ci/UITests/local_check.sh
#
# Checks: bash -n every shell script and every workflow shell block, parse the workflows with PyYAML, run both
# helper self-tests, and dry-run both stop groups with a synthetic test.log so the pass/fail plumbing is proven
# before a CI run is spent.
set -uo pipefail
cd "$(dirname "$0")/../.."
FAIL=0

echo "== bash -n (scripts)"
for s in ci/UITests/*.sh ci/stub/*.sh; do
  if bash -n "$s"; then echo "ok $s"; else echo "FAIL $s"; FAIL=1; fi
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

echo "== dry runs of both stop groups (no simulator, no xcodebuild)"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/groupdry-XXXXXX")
{
  echo "KIT 1.0 AUDIT begin 01 launch"
  echo "KIT 1.1 shot dry-01"
  echo "KIT 1.2 shot dry-02"
  echo "Test Case '-[KitUITests.KitUITests testX]' passed (1.0 seconds)."
  echo "Test Suite 'KitUITests' passed at 2026-11-17 22:00:00.000."
  echo "Executed 1 test, with 0 failures (0 unexpected) in 1.0 (1.0) seconds"
  echo "** TEST SUCCEEDED **"
} > "$TMP/clean.log"
mkdir -p "$TMP/xl/shots" "$TMP/light/shots" "$TMP/noshots/shots"
for g in xl light; do : > "$TMP/$g/shots/dry-01.png"; : > "$TMP/$g/shots/dry-02.png"; done

rc=0
GROUP_DRY=1 GROUP_DRY_LOG="$TMP/clean.log" GROUP_DRY_DIR="$TMP/xl" MIN_SHOTS=2 \
  bash ci/UITests/group_runner.sh xl > "$TMP/xl.out" 2>&1 || rc=$?
echo "clean log rc=$rc (want 0)"; grep -E "^GROUP_RESULT" "$TMP/xl.out"
[ "$rc" -eq 0 ] || FAIL=1

rc=0
sed 's/\*\* TEST SUCCEEDED \*\*/** TEST FAILED **/' "$TMP/clean.log" > "$TMP/red.log"
printf "%s\n" "Test Case '-[KitUITests.KitUITests testX]' failed (1.0 seconds)." >> "$TMP/red.log"
GROUP_DRY=1 GROUP_DRY_LOG="$TMP/red.log" GROUP_DRY_DIR="$TMP/light" MIN_SHOTS=2 \
  bash ci/UITests/group_runner.sh light > "$TMP/red.out" 2>&1 || rc=$?
echo "failing assertion rc=$rc (want 1)"; grep -E "GROUP_REASON" "$TMP/red.out" | head -3
[ "$rc" -ne 0 ] || FAIL=1

rc=0
head -3 "$TMP/clean.log" > "$TMP/nomarker.log"
GROUP_DRY=1 GROUP_DRY_LOG="$TMP/nomarker.log" GROUP_DRY_DIR="$TMP/light" MIN_SHOTS=0 \
  bash ci/UITests/group_runner.sh light > "$TMP/nomarker.out" 2>&1 || rc=$?
echo "missing completion marker rc=$rc (want 1)"; grep -E "GROUP_REASON" "$TMP/nomarker.out" | head -3
[ "$rc" -ne 0 ] || FAIL=1

rc=0
rm -f "$TMP/noshots/shots/dry-02.png"
GROUP_DRY=1 GROUP_DRY_LOG="$TMP/clean.log" GROUP_DRY_DIR="$TMP/noshots" MIN_SHOTS=0 \
  bash ci/UITests/group_runner.sh light > "$TMP/lost.out" 2>&1 || rc=$?
echo "logged shot missing from disk rc=$rc (want 1)"; grep -E "GROUP_REASON|^missing:" "$TMP/lost.out" | head -3
[ "$rc" -ne 0 ] || FAIL=1

echo "== local check outputs: $TMP"
if [ "$FAIL" -eq 0 ]; then echo "LOCAL CHECK: PASS"; exit 0; fi
echo "LOCAL CHECK: FAIL"; exit 1
