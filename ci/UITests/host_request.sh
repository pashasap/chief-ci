#!/usr/bin/env bash
# One host-side request from the Kit UI test, with its postcondition verified before the acknowledgement is written.
#
#   bash ci/UITests/host_request.sh <request> --ctl DIR [--sim UDID] [--pidfile FILE] [--reqlog FILE]
#        [--url LINK] [--health-url URL] [--cacert FILE] [--token TOKEN]
#
# <request> is openurl, dark, light, revokemic, stopstub, markpair or markopenurl.
#
# DIR/<request>-result always receives "ok" or "fail rc=<n> <reason>". DIR/<request>-ok is created only when the
# postcondition held, so a host that merely ran a command cannot look like a host that changed the simulator:
#   dark/light   the command exits 0 AND the simulator reads back the requested appearance
#   revokemic    the command exits 0
#   stopstub     a healthy stub (http 200), the PID exists, the process ends, the endpoint stops answering 200
#   markpair     writes the current request-log line count to pair-since
#   markopenurl  writes the current request-log line count to openurl-since
#
# External commands are overridable (KIT_XCRUN, KIT_KILL, KIT_CURL) so the pre-push gate can drive every branch
# without a simulator. Exit status is 0 whenever a result file was written (the caller judges its content); 64 on a
# usage error.
set -uo pipefail

XCRUN=${KIT_XCRUN:-xcrun}
KILLCMD=${KIT_KILL:-kill}
CURL=${KIT_CURL:-curl}

REQ=${1:-}
if [ $# -gt 0 ]; then shift; fi
CTL=""; SIM=""; PIDFILE=""; REQLOG=""; LINK=""; HEALTH_URL=""; CACERT=""; TOKEN=""
while [ $# -gt 0 ]; do
  case "$1" in
    --ctl) CTL=${2:-}; shift 2 ;;
    --sim) SIM=${2:-}; shift 2 ;;
    --pidfile) PIDFILE=${2:-}; shift 2 ;;
    --reqlog) REQLOG=${2:-}; shift 2 ;;
    --url) LINK=${2:-}; shift 2 ;;
    --health-url) HEALTH_URL=${2:-}; shift 2 ;;
    --cacert) CACERT=${2:-}; shift 2 ;;
    --token) TOKEN=${2:-}; shift 2 ;;
    *) echo "host_request: unknown option $1" >&2; exit 64 ;;
  esac
done
if [ -z "$REQ" ] || [ -z "$CTL" ]; then
  echo "usage: host_request.sh <request> --ctl DIR [--sim UDID] [--pidfile FILE] [--reqlog FILE] [--url LINK] [--health-url URL] [--cacert FILE] [--token TOKEN]" >&2
  exit 64
fi
mkdir -p "$CTL"

# Bare HTTP status of the fixture endpoint; 000 when nothing answers.
http_code () {
  local code args
  if [ -z "$HEALTH_URL" ]; then echo 000; return; fi
  args=(-s --max-time 5 -o /dev/null -w '%{http_code}')
  if [ -n "$CACERT" ]; then args+=(--cacert "$CACERT"); fi
  code=$("$CURL" "${args[@]}" -H "Authorization: Bearer $TOKEN" \
    -H 'Content-Type: application/x-kit-probe' "$HEALTH_URL" 2>/dev/null)
  code=$(printf '%s' "${code:-000}" | tr -dc '0-9')
  echo "${code:-000}"
}

request_log_lines () {
  if [ -n "$REQLOG" ] && [ -f "$REQLOG" ]; then wc -l < "$REQLOG" | tr -dc '0-9'; else echo 0; fi
}

RC=0; NOTE=""
case "$REQ" in
  openurl)
    if [ -z "$SIM" ]; then RC=96; NOTE="no simulator udid"
    else "$XCRUN" simctl openurl "$SIM" "$LINK"; RC=$?; fi
    ;;
  dark|light)
    if [ -z "$SIM" ]; then RC=96; NOTE="no simulator udid"
    else
      "$XCRUN" simctl ui "$SIM" appearance "$REQ"; RC=$?
      if [ "$RC" -eq 0 ]; then
        SEEN=$("$XCRUN" simctl ui "$SIM" appearance 2>/dev/null | tail -1 | tr -d '[:space:]')
        NOTE="appearance_readback=$SEEN"
        if [ "$SEEN" != "$REQ" ]; then RC=97; NOTE="$NOTE expected=$REQ"; fi
      fi
    fi
    ;;
  revokemic)
    if [ -z "$SIM" ]; then RC=96; NOTE="no simulator udid"
    else "$XCRUN" simctl privacy "$SIM" revoke microphone com.example.Chief; RC=$?; fi
    ;;
  stopstub)
    BEFORE=$(http_code)
    NOTE="health_before=$BEFORE"
    if [ -z "$PIDFILE" ] || [ ! -f "$PIDFILE" ]; then
      RC=98; NOTE="$NOTE no stub pid file"
    else
      PID=$(tr -dc '0-9' < "$PIDFILE")
      if [ -z "$PID" ]; then
        RC=98; NOTE="$NOTE empty stub pid"
      elif [ "$BEFORE" != "200" ]; then
        RC=99; NOTE="$NOTE stub not healthy before stop"
      else
        "$KILLCMD" "$PID" 2>/dev/null; RC=$?
        if [ "$RC" -ne 0 ]; then
          NOTE="$NOTE kill rc=$RC"
        else
          for _ in $(seq 1 20); do
            kill -0 "$PID" 2>/dev/null || break
            sleep 0.5
          done
          if kill -0 "$PID" 2>/dev/null; then kill -9 "$PID" 2>/dev/null; sleep 1; fi
          AFTER=$(http_code)
          NOTE="$NOTE health_after=$AFTER"
          if [ "$AFTER" = "200" ]; then RC=99; NOTE="$NOTE endpoint still reachable"; fi
        fi
      fi
    fi
    ;;
  markpair|markopenurl)
    LINES=$(request_log_lines)
    NOTE="request_log_lines=$LINES"
    if [ "$REQ" = "markpair" ]; then printf '%s\n' "$LINES" > "$CTL/pair-since"
    else printf '%s\n' "$LINES" > "$CTL/openurl-since"; fi
    RC=0
    ;;
  *)
    RC=95; NOTE="unknown request $REQ"
    ;;
esac

if [ "$RC" -eq 0 ]; then
  printf 'ok\n' > "$CTL/$REQ-result"
  : > "$CTL/$REQ-ok"
else
  printf 'fail rc=%s %s\n' "$RC" "$NOTE" > "$CTL/$REQ-result"
fi
echo "host_request $REQ rc=$RC ${NOTE:-ok}"
exit 0
