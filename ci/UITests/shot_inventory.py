#!/usr/bin/env python3
"""Compare the shot names the UI test logged against the PNGs actually in the upload directory.

The test writes each PNG atomically before it logs "KIT <t> shot <name>", and the runner mirrors the shot directory
into the artifact directory while the test runs. So a logged shot with no file means collection lost output (a
timeout, a surviving writer, a dropped copy). That is an explicit failure, never a silent short list.

Two further rules stop a count from standing in for evidence:
  * the floor counts UNIQUE names, so repeating one marker cannot satisfy it;
  * --require-shots names the stops a group must have covered, and each name must be both logged and uploaded, so a
    missing screen is a mismatch instead of an untested gap.

Usage:
  shot_inventory.py --log test.log --dir artifacts/xl/shots --out artifacts/xl/inventory.txt \
      [--require 1] [--require-shots 50-xl-inbox,54b-xxxl-record]
  shot_inventory.py --self-test
Exit 0 when every logged shot is present, the unique count reaches --require and every named stop was captured;
1 otherwise.
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


def compare(log, directory, require, require_shots=()):
    want = logged(log)
    uniq = set(want)
    have = files(directory)
    missing = [n for n in want if n not in have]
    extra = sorted(have - uniq)
    required = [n for n in require_shots if n]
    not_logged = [n for n in required if n not in uniq]
    no_png = [n for n in required if n not in have]
    # A group that logged no shots has no evidence at all, so it can never be ok even with --require 0.
    ok = (not missing and len(uniq) >= require and len(want) > 0
          and not not_logged and not no_png)
    lines = [
        "shots logged={} uploaded={} unique_logged={} missing={} extra={} required={} named_required={}".format(
            len(want), len(have), len(uniq), len(missing), len(extra), require, len(required)),
        "missing: " + (", ".join(missing[:60]) if missing else "none"),
        "extra: " + (", ".join(extra[:60]) if extra else "none"),
        "named_missing_log: " + (", ".join(not_logged[:40]) if not_logged else "none"),
        "named_missing_png: " + (", ".join(no_png[:40]) if no_png else "none"),
        "result: " + ("ok" if ok else "MISMATCH"),
    ]
    if len(uniq) < require:
        lines.append("reason: only {} unique shot name(s) logged, at least {} required".format(len(uniq), require))
    if missing:
        lines.append("reason: {} logged shot(s) have no uploaded PNG".format(len(missing)))
    if not_logged:
        lines.append("reason: required stop(s) never logged: {}".format(", ".join(not_logged)))
    if no_png:
        lines.append("reason: required stop(s) logged with no uploaded PNG: {}".format(", ".join(no_png)))
    return ok, "\n".join(lines), missing, extra


def self_test():
    tmp = tempfile.mkdtemp(prefix="shot-inventory-")
    full = os.path.join(tmp, "full")
    os.makedirs(full)
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
        open(os.path.join(full, n + ".png"), "wb").write(b"\x89PNG\r\n\x1a\n")
    empty = os.path.join(tmp, "empty.log")
    open(empty, "w").close()
    # One marker repeated five times with a single PNG: the count looks healthy, the coverage is one screen.
    repeat_log = os.path.join(tmp, "repeat.log")
    with open(repeat_log, "w", encoding="utf-8") as f:
        f.write("\n".join("KIT 1.{} shot rep-01".format(i) for i in range(5)) + "\n")
    repeat = os.path.join(tmp, "repeat")
    os.makedirs(repeat)
    open(os.path.join(repeat, "rep-01.png"), "wb").write(b"\x89PNG\r\n\x1a\n")
    failed = []

    def check(name, lg, dr, req, want, named=()):
        ok, detail, _, _ = compare(lg, dr, req, named)
        good = ok == want
        if not good:
            failed.append(name)
        print("{} {}: want={} got={} | {}".format("PASS" if good else "FAIL", name, want, ok,
                                                  detail.splitlines()[0]))

    check("complete", log, full, 2, True)
    check("too few shots", log, full, 3, False)
    check("named stops present", log, full, 2, True, ("a-01", "a-02"))
    check("named stop never logged", log, full, 2, False, ("a-01", "zz-never-shot"))
    check("repeated markers fail the unique floor", repeat_log, repeat, 3, False)
    check("one unique shot meets a floor of one", repeat_log, repeat, 1, True)
    # Mutations happen after the cases that need the intact fixtures.
    os.remove(os.path.join(full, "a-02.png"))
    check("timeout lost a shot", log, full, 1, False)
    check("named stop logged but never uploaded", log, full, 1, False, ("a-01", "a-02"))
    os.remove(os.path.join(full, "a-01.png"))
    check("nothing collected", log, full, 1, False)
    check("no shots logged at all", empty, full, 0, False)
    print("self-test: 10 cases, {} failed".format(len(failed)))
    return 1 if failed else 0


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--log")
    p.add_argument("--dir")
    p.add_argument("--out")
    p.add_argument("--require", type=int, default=0)
    p.add_argument("--require-shots", default="")
    p.add_argument("--self-test", action="store_true")
    a = p.parse_args()
    if a.self_test:
        return self_test()
    if not a.log or not a.dir:
        print("--log and --dir are required", file=sys.stderr)
        return 1
    named = tuple(n.strip() for n in a.require_shots.split(",") if n.strip())
    ok, detail, missing, extra = compare(a.log, a.dir, a.require, named)
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
