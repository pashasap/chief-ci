#!/bin/bash
# The stand-in part of the journeys job (issue #94, D-20261126-p-66), rendered only for a product that declares a
# stand-in. It makes the run's certificates, adds the run's CA to the simulator's trust store (`simctl keychain
# add-root-cert`, which is what a user does when he installs a profile and trusts it), starts ci/stand_in.py on
# https://localhost:8443 and waits until it answers over TLS with that CA. Nothing is written into the app or its
# container: the app reaches the server only when a journey pairs it through its own pairing screen.
# The request log and the server's output go to ci/journey-artifacts/stand-in/, which the job uploads.
# A failure here stops the job before the journeys play, so they are `not run`, never failed by the harness.
set -euo pipefail
A=ci/journey-artifacts/stand-in; mkdir -p "$A"
D="$RUNNER_TEMP/stand-in"; mkdir -p "$D"
PORT=8443
if ! bash ci/stand_in_cert.sh "$D" > "$A/cert.log" 2>&1; then
  echo "OUTCOME stand-in certificates could not be made" | tee -a ci/journey-artifacts/outcome.txt; exit 1
fi
cp "$D/ca.crt" "$A/ca.crt"
mark () { echo "TIMING stand-in $1 at $(( $(date +%s) - JOB_T0 ))s" | tee -a ci/journey-artifacts/timing.txt; }
mark "certificates made"
xcrun simctl boot "$SIM_UDID" > /dev/null 2>&1 < /dev/null || true
xcrun simctl bootstatus "$SIM_UDID" -b > /dev/null < /dev/null
mark "simulator booted"
if ! xcrun simctl keychain "$SIM_UDID" add-root-cert "$D/ca.crt" > "$A/trust.log" 2>&1 < /dev/null; then
  echo "OUTCOME the simulator did not accept the stand-in CA" | tee -a ci/journey-artifacts/outcome.txt; exit 1
fi
mark "CA trusted"
nohup python3 ci/stand_in.py --data ci/stand_in.json --cert "$D/server.crt" --key "$D/server.key" \
  --log "$A/requests.jsonl" --port "$PORT" > "$A/server.log" 2>&1 < /dev/null &
echo "$!" > "$D/pid"
for _ in $(seq 1 30); do grep -q '^ready ' "$A/server.log" 2>/dev/null && break; sleep 1; done
if ! grep -q '^ready ' "$A/server.log"; then
  echo "OUTCOME the stand-in did not start" | tee -a ci/journey-artifacts/outcome.txt; cat "$A/server.log"; exit 1
fi
CODE=$(curl -sS --cacert "$D/ca.crt" -o "$A/probe.json" -w '%{http_code}' "https://localhost:$PORT/v1/health" || true)
echo "probe without a token over TLS with the run CA: HTTP $CODE" | tee "$A/probe.txt"
if [ "$CODE" != "401" ]; then
  echo "OUTCOME the stand-in did not answer over TLS (HTTP $CODE)" | tee -a ci/journey-artifacts/outcome.txt; exit 1
fi
echo "TIMING stand-in ready at $(( $(date +%s) - JOB_T0 ))s" | tee -a ci/journey-artifacts/timing.txt
