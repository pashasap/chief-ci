#!/usr/bin/env bash
# Decides the job's colour from the requested stop group and the observed step outcomes.
#
#   bash ci/UITests/verdict.sh <all|xl-layout|xl-environment|light> \
#        <xl-layout outcome> <xl-environment outcome> <light outcome> <artifacts dir>
#
# The required groups follow the request: all -> xl-layout, xl-environment and light; a single group -> only that
# group. A required group passes only when its step outcome is exactly "success" AND the evidence it must archive is
# present: summary.txt with a status=PASS line, inventory.txt with a "result: ok" line. A skipped, blank or failed
# outcome fails, so a mode can never be satisfied by a group that never ran, and a group that lost its evidence
# cannot look green.
#
# Exit 0 when every required group passed, 1 otherwise.
# NB: the group list lives in ALL_GROUPS because bash reserves GROUPS for the caller's group ids and ignores
# an assignment to it, which made every required group resolve to the numeric gid.
set -uo pipefail

MODE=${1:-}
XL_LAYOUT=${2:-}
XL_ENV=${3:-}
LI=${4:-}
A=${5:-ci/artifacts}
ALL_GROUPS="xl-layout xl-environment light"
FAIL=0

case "$MODE" in
  all)          REQUIRED=$ALL_GROUPS ;;
  xl-layout)    REQUIRED="xl-layout" ;;
  xl-environment) REQUIRED="xl-environment" ;;
  light)        REQUIRED="light" ;;
  *)            echo "VERDICT unknown audit group '${MODE}'"; REQUIRED=$ALL_GROUPS; FAIL=1 ;;
esac
echo "verdict: group=$MODE required=$REQUIRED xl-layout=${XL_LAYOUT:-<blank>} xl-environment=${XL_ENV:-<blank>} light=${LI:-<blank>}"

outcome () {
  case "$1" in
    xl-layout) printf '%s' "$XL_LAYOUT" ;;
    xl-environment) printf '%s' "$XL_ENV" ;;
    light) printf '%s' "$LI" ;;
  esac
}

for g in $ALL_GROUPS; do
  case " $REQUIRED " in
    *" $g "*) continue ;;
    *) echo "GROUP_NOT_REQUIRED $g outcome=$(outcome "$g" || true)" ;;
  esac
done

for g in $REQUIRED; do
  O=$(outcome "$g")
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
