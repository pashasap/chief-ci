#!/usr/bin/env bash
# Fail closed: process status, completion and XCTest's executed verdict must agree.
set -euo pipefail
LOG=$1; RC=$2; CUTOFF=$3
fail () { echo "UI TEST FAILED: $*" >&2; exit 1; }
[[ $CUTOFF == 0 ]] || fail 'watchdog cutoff before xcodebuild completed'
[[ $RC == 0 ]] || fail "xcodebuild exited $RC"
[[ -s $LOG ]] || fail 'missing or empty test log'
if grep -Eq 'Test (Case|Suite) .*failed|Executed [0-9]+ tests?, with [1-9][0-9]* failures?|\*\* (TEST.*FAILED|BUILD INTERRUPTED) \*\*' "$LOG"; then
  fail 'XCTest or xcodebuild reported failure'
fi
grep -Eq "Test Case .*testScreens.* passed" "$LOG" || fail 'testScreens did not execute and pass'
grep -Eq 'Executed [1-9][0-9]* tests?, with 0 failures?' "$LOG" || fail 'missing nonzero executed XCTest summary'
grep -Eq '^\*\* TEST( EXECUTE)? SUCCEEDED \*\*' "$LOG" || fail 'missing xcodebuild success completion marker'
echo 'UI TEST PASSED: completed xcodebuild and executed XCTest agree'
