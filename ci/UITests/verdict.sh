#!/usr/bin/env bash
# Decides the job's colour from the requested stop group and the observed step outcomes.
#
#   bash ci/UITests/verdict.sh <all|xl|light> <xl outcome> <light outcome> <artifacts dir>
#
# The required groups follow the request: all -> xl and light, xl -> xl, light -> light. A required group passes only
# when its step outcome is exactly "success" AND the evidence it must archive is present: summary.txt with a
# status=PASS line, inventory.txt with a "result: ok" line. A skipped, blank or failed outcome fails, so a mode can
# never be satisfied by a group that never ran, and a group that lost its evidence cannot look green.
#
# Exit 0 when every required group passed, 1 otherwise.
set -uo pipefail

MODE=${1:-}
XL=${2:-}
LI=${3:-}
A=${4:-ci/artifacts}
FAIL=0

case "$MODE" in
  all)   REQUIRED="xl light" ;;
  xl)    REQUIRED="xl" ;;
  light) REQUIRED="light" ;;
  *)     echo "VERDICT unknown audit group '${MODE}'"; REQUIRED="xl light"; FAIL=1 ;;
esac
echo "verdict: group=$MODE required=$REQUIRED xl=${XL:-<blank>} light=${LI:-<blank>}"

for g in xl light; do
  case " $REQUIRED " in *" $g "*) continue ;; esac
  case "$g" in xl) O=$XL ;; light) O=$LI ;; esac
  echo "GROUP_NOT_REQUIRED $g outcome=${O:-<blank>}"
done

for g in $REQUIRED; do
  case "$g" in xl) O=$XL ;; light) O=$LI ;; esac
  echo "GROUP_REQUIRED $g outcome=${O:-<blank>}"
  if [ "$O" != "success" ]; then
    echo "GROUP_FAILED $g outcome=${O:-<blank>} (required by group=$MODE)"
    FAIL=1
  fi
  if [ -f "$A/$g/summary.txt" ]; then
    cat "$A/$g/summary.txt"
    grep -q 'status=PASS' "$A/$g/summary.txt" || { echo "GROUP_FAILED $g summary has no status=PASS"; FAIL=1; }
  else
    echo "GROUP_FAILED $g missing $A/$g/summary.txt"; FAIL=1
  fi
  if [ -f "$A/$g/inventory.txt" ]; then
    cat "$A/$g/inventory.txt"
    grep -qE '^result: ok$' "$A/$g/inventory.txt" || { echo "GROUP_FAILED $g inventory has no 'result: ok'"; FAIL=1; }
  else
    echo "GROUP_FAILED $g missing $A/$g/inventory.txt"; FAIL=1
  fi
done

if [ "$FAIL" -eq 0 ]; then echo "VERDICT: PASS (group=$MODE)"; exit 0; fi
echo "VERDICT: FAIL (group=$MODE)"; exit 1
