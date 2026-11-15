#!/usr/bin/env bash
# Exercises the stub over HTTPS with curl, trusting only the throwaway CA. Usage: selftest.sh <stub dir> <work dir>
set -uo pipefail
T0=$(date +%s); S=$1; W=$2; mkdir -p "$W"; TOKEN=kit-sim-invented-token-0001; PORT=${PORT:-18443}
bash "$S/make_cert.sh" "$W/cert" > /dev/null
rm -f "$W/requests.jsonl"
python3 -I "$S/stub_server.py" --fixtures "$S/fixtures" --cert "$W/cert/chain.pem" --key "$W/cert/server.key" \
  --token $TOKEN --port $PORT --log "$W/requests.jsonl" > "$W/stub.out" 2>&1 &
PID=$!; trap 'kill $PID 2>/dev/null' EXIT
echo "cert made t=$(( $(date +%s) - T0 ))s"
for i in $(seq 1 30); do curl -s --max-time 2 --cacert "$W/cert/ca.pem" https://localhost:$PORT/ -o /dev/null && break; sleep 0.2; done
fail=0
check () { # name expected-status curl-args...
  local name=$1 want=$2; shift 2
  local got; got=$(curl -s --max-time 5 -o "$W/last.body" -w '%{http_code}' --cacert "$W/cert/ca.pem" "$@")
  if [ "$got" = "$want" ]; then echo "PASS $name ($got) t=$(( $(date +%s) - T0 ))s"; else echo "FAIL $name: want $want got $got: $(head -c 200 "$W/last.body")"; fail=1; fi
}
A=(-H "Authorization: Bearer $TOKEN")
check health-noauth 401 https://localhost:$PORT/v1/health
check health-wrong 401 -H "Authorization: Bearer nope" https://localhost:$PORT/v1/health
check health 200 "${A[@]}" https://localhost:$PORT/v1/health
check health-ipv4 200 "${A[@]}" https://127.0.0.1:$PORT/v1/health
check health-ipv6 200 "${A[@]}" "https://[::1]:$PORT/v1/health"
ETAG=$(curl -s -D - -o "$W/snap.json" --cacert "$W/cert/ca.pem" "${A[@]}" https://localhost:$PORT/v1/snapshot | tr -d '\r' | awk -F': ' 'tolower($1)=="etag"{print $2}')
echo "etag=$ETAG"; python3 -I -c "import json,sys; s=json.load(open(sys.argv[1])); print('snapshot captures', len(s['captures']), 'tasks', len(s['tasks']))" "$W/snap.json" || fail=1
check snapshot-304 304 "${A[@]}" -H "If-None-Match: $ETAG" https://localhost:$PORT/v1/snapshot
check doc-result 200 "${A[@]}" "https://localhost:$PORT/v1/doc?handle=A-1112-6&part=result"
check doc-draft 200 "${A[@]}" "https://localhost:$PORT/v1/doc?handle=A-1113-2&part=draft"
check doc-missing 404 "${A[@]}" "https://localhost:$PORT/v1/doc?handle=A-0&part=result"
F=$S/requests
check audio 204 "${A[@]}" -X PUT -H "Content-Type: audio/mp4" --data-binary "abcd" https://localhost:$PORT/v1/captures/5b0e7a6e-2c8d-4a55-9a43-0d6c1f3f7b21/audio
check capture-first 201 "${A[@]}" -H "Content-Type: application/json" --data-binary @"$F/capture_request_voice.json" https://localhost:$PORT/v1/captures
check capture-repeat 200 "${A[@]}" -H "Content-Type: application/json" --data-binary @"$F/capture_request_voice.json" https://localhost:$PORT/v1/captures
check capture-unknown-field 400 "${A[@]}" -H "Content-Type: application/json" --data-binary '{"client_id":"x","bogus":1}' https://localhost:$PORT/v1/captures
check command-approve 200 "${A[@]}" -H "Content-Type: application/json" --data-binary @"$F/command_proposal_approve.json" https://localhost:$PORT/v1/commands
check snapshot-changed 200 "${A[@]}" -H "If-None-Match: $ETAG" https://localhost:$PORT/v1/snapshot
python3 -I -c "import json,sys; s=json.load(open(sys.argv[1])); p=[x for x in s['proposals'] if x['handle']=='P-1112-8'][0]; print('P-1112-8 state', p['state']); sys.exit(p['state']!='approved')" "$W/last.body" || fail=1
check command-done 200 "${A[@]}" -H "Content-Type: application/json" --data-binary @"$F/command_task_done.json" https://localhost:$PORT/v1/commands
check command-unknown-field 400 "${A[@]}" -H "Content-Type: application/json" --data-binary '{"id":"z","type":"task.done","handle":"c1112-03-1","rev":"r","args":{},"x":1}' https://localhost:$PORT/v1/commands
check command-unknown-handle 404 "${A[@]}" -H "Content-Type: application/json" --data-binary '{"id":"y","type":"task.done","handle":"nope","rev":"r","args":{}}' https://localhost:$PORT/v1/commands
check untrusted-ca 000 --cacert /dev/null https://localhost:$PORT/v1/health
echo "log lines: $(wc -l < "$W/requests.jsonl")"; tail -3 "$W/requests.jsonl"
[ $fail = 0 ] && echo "SELFTEST OK" || echo "SELFTEST FAILED"
exit $fail
