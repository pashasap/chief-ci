#!/usr/bin/env python3
"""Compare the shot names the UI test logged against the PNGs actually in the upload directory.

The test writes each PNG atomically before it logs "KIT <t> shot <name>", and the runner mirrors /tmp/kitshots
into the artifact directory while the test runs. So a logged shot with no file means collection lost output (a
timeout, a surviving writer, a dropped copy). That is an explicit failure, never a silent short list.

Usage:
  shot_inventory.py --log test.log --dir artifacts/xl/shots --out artifacts/xl/inventory.txt [--require 1]
  shot_inventory.py --self-test
Exit 0 when every logged shot is present (and count >= --require), 1 otherwise.
"""
import argparse
import os
import re
import sys
import tempfile

SHOT = re.compile(r"^KIT [0-9.]+ shot (\S+)$")


def logged(path):
    names = []
    if not os.path.exists(path):
        return names
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        for line in f:
            m = SHOT.match(line.strip())
            if m:
                names.append(m.group(1))
    return names


def files(directory):
    if not os.path.isdir(directory):
        return set()
    return {n[:-4] for n in os.listdir(directory) if n.endswith(".png") and not n.startswith(".")}


def compare(log, directory, require):
    want = logged(log)
    have = files(directory)
    missing = [n for n in want if n not in have]
    extra = sorted(have - set(want))
    # A group that logged no shots has no evidence at all, so it can never be ok even with --require 0.
    ok = not missing and len(want) >= require and len(want) > 0
    lines = [
        "shots logged={} uploaded={} unique_logged={} missing={} extra={} required={}".format(
            len(want), len(have), len(set(want)), len(missing), len(extra), require),
        "missing: " + (", ".join(missing[:60]) if missing else "none"),
        "extra: " + (", ".join(extra[:60]) if extra else "none"),
        "result: " + ("ok" if ok else "MISMATCH"),
    ]
    if len(want) < require:
        lines.append("reason: only {} shot(s) logged, at least {} required".format(len(want), require))
    if missing:
        lines.append("reason: {} logged shot(s) have no uploaded PNG".format(len(missing)))
    return ok, "\n".join(lines), missing, extra


def self_test():
    tmp = tempfile.mkdtemp(prefix="shot-inventory-")
    shots = os.path.join(tmp, "shots")
    os.makedirs(shots)
    log = os.path.join(tmp, "test.log")
    body = [
        "KIT 1.0 AUDIT begin 01 x",
        "KIT 1.1 shot a-01",
        "KIT 1.2 shot a-02",
        "KIT 1.3 DONE testX",
    ]
    with open(log, "w", encoding="utf-8") as f:
        f.write("\n".join(body) + "\n")
    for n in ("a-01", "a-02"):
        open(os.path.join(shots, n + ".png"), "wb").write(b"\x89PNG\r\n\x1a\n")
    empty = os.path.join(tmp, "empty.log")
    open(empty, "w").close()
    failed = []

    def check(name, lg, dr, req, want):
        ok, detail, _, _ = compare(lg, dr, req)
        good = ok == want
        if not good:
            failed.append(name)
        print("{} {}: want={} got={} | {}".format("PASS" if good else "FAIL", name, want, ok,
                                                  detail.splitlines()[0]))

    # Each mutation happens between checks, so a case can never be judged against a later state.
    check("complete", log, shots, 2, True)
    check("too few shots", log, shots, 3, False)
    os.remove(os.path.join(shots, "a-02.png"))
    check("timeout lost a shot", log, shots, 1, False)
    os.remove(os.path.join(shots, "a-01.png"))
    check("nothing collected", log, shots, 1, False)
    check("no shots logged at all", empty, shots, 0, False)
    print("self-test: 5 cases, {} failed".format(len(failed)))
    return 1 if failed else 0


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--log")
    p.add_argument("--dir")
    p.add_argument("--out")
    p.add_argument("--require", type=int, default=0)
    p.add_argument("--self-test", action="store_true")
    a = p.parse_args()
    if a.self_test:
        return self_test()
    if not a.log or not a.dir:
        print("--log and --dir are required", file=sys.stderr)
        return 1
    ok, detail, missing, extra = compare(a.log, a.dir, a.require)
    print(detail)
    if a.out:
        tmp = a.out + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            f.write(detail + "\n")
        os.replace(tmp, a.out)
    if missing:
        print("SHOT INVENTORY MISMATCH: {} logged shot(s) missing from {}".format(len(missing), a.dir),
              file=sys.stderr)
    if len(extra) > 400:
        print("note: {} extra PNGs (files with no shot line)".format(len(extra)), file=sys.stderr)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
