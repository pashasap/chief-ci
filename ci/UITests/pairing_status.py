#!/usr/bin/env python3
"""Pairing verdict from the stub request log.

A device counts as paired only when the log holds an app-authored authenticated health check answered 200 AND a
snapshot fetch answered 200/304. The workflow's own `curl` health probes carry `Content-Type:
application/x-kit-probe`, so a probe can never stand in for the app. The visible "Paired" label is never read
here: a silent label must not fail a paired device, and a label alone must not pass an unpaired one.

Usage:
  pairing_status.py --log requests.jsonl --since 0 [--wait 30] [--allow-earlier-snapshot] --out /tmp/kitctl/x-status
  pairing_status.py --self-test
Exit 0 always when inspecting a log (the verdict is data, the XCTest assertion decides). Exit 1 on a usage error.
"""
import argparse
import json
import os
import sys
import tempfile
import time

PROBE_CT = "application/x-kit-probe"


def records(path, since):
    if not os.path.exists(path):
        return []
    out = []
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        for i, line in enumerate(f):
            if i < since:
                continue
            line = line.strip()
            if not line:
                continue
            try:
                out.append(json.loads(line))
            except json.JSONDecodeError:
                continue
    return out


def path_of(rec):
    return str(rec.get("path", "")).split("?")[0]


def app_health(rec):
    return (str(rec.get("method", "")).upper() == "GET"
            and path_of(rec) == "/v1/health"
            and rec.get("status") == 200
            and rec.get("auth") == "ok"
            and rec.get("content_type") != PROBE_CT)


def snapshot(rec):
    return (str(rec.get("method", "")).upper() == "GET"
            and path_of(rec) == "/v1/snapshot"
            and rec.get("status") in (200, 304))


def verdict(path, since, allow_earlier_snapshot):
    fresh = records(path, since)
    health = sum(1 for r in fresh if app_health(r))
    snap_after = sum(1 for r in fresh if snapshot(r))
    snap_all = snap_after if allow_earlier_snapshot else 0
    if allow_earlier_snapshot:
        snap_all = sum(1 for r in records(path, 0) if snapshot(r))
    paired = health >= 1 and (snap_after >= 1 or snap_all >= 1)
    detail = ("app_health_200={} snapshot_after={} snapshot_any={} records_since={} probe_lines={}"
              .format(health, snap_after, snap_all, len(fresh),
                      sum(1 for r in fresh if r.get("content_type") == PROBE_CT)))
    return ("paired" if paired else "notpaired"), detail


def self_test():
    good = [
        {"method": "GET", "path": "/v1/health", "status": 200, "auth": "ok", "content_type": None},
        {"method": "GET", "path": "/v1/snapshot", "status": 200, "auth": "ok", "content_type": None},
    ]
    probe_only = [
        {"method": "GET", "path": "/v1/health", "status": 200, "auth": "ok", "content_type": PROBE_CT},
    ]
    rejected = [
        {"method": "GET", "path": "/v1/health", "status": 401, "auth": "wrong", "content_type": None},
        {"method": "GET", "path": "/v1/health", "status": 200, "auth": "ok", "content_type": PROBE_CT},
    ]
    # Snapshot taken by an earlier group (line 0), health check by this group (line 1): the light group's case.
    split = [
        {"method": "GET", "path": "/v1/snapshot", "status": 200, "auth": "ok", "content_type": None},
        {"method": "GET", "path": "/v1/health", "status": 200, "auth": "ok", "content_type": None},
    ]
    tmp = tempfile.mkdtemp(prefix="pairing-status-")
    cases = []

    def put(name, recs):
        p = os.path.join(tmp, name + ".jsonl")
        with open(p, "w", encoding="utf-8") as f:
            for r in recs:
                f.write(json.dumps(r) + "\n")
        return p

    cases.append(("paired app log", put("good", good), 0, False, "paired"))
    cases.append(("host probe only", put("probe", probe_only), 0, False, "notpaired"))
    cases.append(("rejected token", put("rejected", rejected), 0, False, "notpaired"))
    cases.append(("snapshot before baseline", put("split", split), 1, False, "notpaired"))
    cases.append(("snapshot before baseline, earlier allowed", put("split2", split), 1, True, "paired"))
    cases.append(("empty log", put("empty", []), 0, False, "notpaired"))
    failed = 0
    for name, path, since, allow, want in cases:
        got, detail = verdict(path, since, allow)
        ok = got == want
        failed += 0 if ok else 1
        print("{} {}: want={} got={} ({})".format("PASS" if ok else "FAIL", name, want, got, detail))
    print("self-test: {} cases, {} failed".format(len(cases), failed))
    return 1 if failed else 0


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--log")
    p.add_argument("--since", type=int, default=0)
    p.add_argument("--wait", type=int, default=0)
    p.add_argument("--allow-earlier-snapshot", action="store_true")
    p.add_argument("--out")
    p.add_argument("--self-test", action="store_true")
    a = p.parse_args()
    if a.self_test:
        return self_test()
    if not a.log or not a.out:
        print("--log and --out are required", file=sys.stderr)
        return 1
    deadline = time.time() + max(0, a.wait)
    result, detail = verdict(a.log, a.since, a.allow_earlier_snapshot)
    while result != "paired" and time.time() < deadline:
        time.sleep(1)
        result, detail = verdict(a.log, a.since, a.allow_earlier_snapshot)
    tmp = a.out + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(result + "\n")
    os.replace(tmp, a.out)
    print("pairing {}: {} ({})".format(result, detail, a.log))
    return 0


if __name__ == "__main__":
    sys.exit(main())
