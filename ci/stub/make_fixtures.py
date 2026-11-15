"""Builds the stub's answers: a richer snapshot (invented, neutral data) in the exact contract shapes,
plus the /v1/doc answers. Copies the verified small fixtures unchanged.
Usage: python3 -I make_fixtures.py <verified fixtures dir> <out dir>"""
import json
import os
import shutil
import sys

src, out = sys.argv[1], sys.argv[2]
os.makedirs(out, exist_ok=True)
for name in ("capture_created.json", "command_ok.json", "command_error.json"):
    shutil.copy(os.path.join(src, name), os.path.join(out, name))


def item(handle, kind, text, state="open"):
    return {"handle": handle, "kind": kind, "text": text, "state": state}


def cap(cid, date, time, source, client_id, text, status, items, note=""):
    return {"id": cid, "date": date, "time": time, "source": source, "client_id": client_id,
            "text": text, "status": status, "status_note": note, "items": items}


def when(kind, date=None):
    return {"kind": kind, "date": date}


def task(handle, rev, text, w, capture, note=""):
    return {"handle": handle, "rev": rev, "text": text, "note": note, "when": w, "state": "open", "capture": capture}


snapshot = {
    "api": 1,
    "generated_at": "2026-11-13T13:35:00Z",
    "today": "2026-11-13",
    "timezone": "Europe/Paris",
    "captures": [
        cap("c1113-07", "2026-11-13", "14:30", "app", "7d2c9a10-1b3e-4c5f-8a6b-0c1d2e3f4a5b",
            "Pick up the dry cleaning today, and ask the landlord when the boiler service is.", "filed",
            [item("c1113-07-1", "task", "Pick up the dry cleaning"),
             item("w1113-2", "waiting", "Landlord: date for the boiler service"),
             item("A-1113-2", "result", "Notes for the boiler service visit")]),
        cap("c1113-06", "2026-11-13", "14:04", "app", "a3d1f0b2-6f0e-4f7e-8a51-2b9a0e4c7d55",
            "Which account should the gym membership come out of?", "on_server", []),
        cap("c1113-05", "2026-11-13", "14:02", "app", "5b0e7a6e-2c8d-4a55-9a43-0d6c1f3f7b21",
            "Remind me next week to book the car in for winter tyres. And an idea, a shared grocery list app.",
            "filed",
            [item("c1113-05-1", "task", "Book the car in for winter tyres"),
             item("c1113-05-2", "note", "Idea: a shared grocery list app"),
             item("Q-1113-1", "question", "Which account should the gym membership come out of?")]),
        cap("c1113-03", "2026-11-13", "09:15", "app", "3c4d5e6f-7a8b-4c9d-8e0f-1a2b3c4d5e6f",
            "Look up the Sunday opening hours of the city library.", "filing", []),
        cap("c1112-11", "2026-11-12", "19:40", "app", "9e8d7c6b-5a49-4382-9716-0a1b2c3d4e5f",
            "Something about the garden, the recording cut out.", "needs_attention", [],
            "The audio was too short to file"),
        cap("c1112-09", "2026-11-12", None, "telegram", None,
            "Find out who insures the garden shed.", "filed",
            [item("c1112-09-1", "task", "Find out who insures the garden shed"),
             item("P-1112-8", "proposal", "Draft an email to the letting agent asking who insures the garden shed")]),
        cap("c1112-06", "2026-11-12", "08:10", "app", "1f2e3d4c-5b6a-4798-8a7b-6c5d4e3f2a1b",
            "How much is a monthly pass at the swimming pool, and any ideas for weekend projects?", "filed",
            [item("A-1112-6", "result", "Swimming pool monthly pass price"),
             item("pc1112-1", "candidate", "Home energy savings"),
             item("P-1113-4", "proposal", "Look up the library's Sunday opening hours")]),
    ],
    "tasks": [
        task("c1112-03-1", "9f2c41d07a3e", "Buy a birthday card and the ingredients for a vegetable lasagna",
             when("due", "2026-11-13"), "c1112-03", "mentioned again c1113-04"),
        task("c1113-07-1", "2b8e11f0c7a4", "Pick up the dry cleaning", when("today"), "c1113-07"),
        task("c1111-02-1", "6a0c3d9e2f11", "Return the library books", when("due", "2026-11-11"), "c1111-02"),
        task("c1113-05-1", "1b7e02c4a9d1", "Book the car in for winter tyres", when("later"), "c1113-05"),
        task("c1112-09-1", "4e5f6a7b8c9d", "Find out who insures the garden shed", when("due", "2026-11-20"), "c1112-09"),
        task("c1110-01-1", "0a9b8c7d6e5f", "Sort the shelves in the spare room", when("undated"), "c1110-01"),
    ],
    "notes": [
        {"handle": "c1113-05-2", "rev": "77aa01c3e5f0", "text": "Idea: a shared grocery list app", "note": "",
         "capture": "c1113-05"},
    ],
    "waiting": [
        {"handle": "w1113-2", "rev": "5d0c9e11b2a4", "text": "Landlord: date for the boiler service", "state": "open",
         "capture": "c1113-07"},
        {"handle": "w1112-1", "rev": "8c7b6a5d4e3f", "text": "Plumber: quote for the kitchen tap", "state": "open",
         "capture": "c1112-05"},
    ],
    "candidates": [
        {"handle": "pc1112-1", "rev": "c41f7e09d3b8", "text": "Home energy savings", "note": "2 mentions",
         "capture": "c1112-06"},
        {"handle": "pc1113-1", "rev": "d52a8f10e4c9", "text": "Learn basic woodworking", "note": "3 mentions",
         "capture": "c1113-02"},
    ],
    "proposals": [
        # A deliberately long suggestion, to judge wrapping and the button layout.
        {"handle": "P-1113-9", "rev": "a7b6c5d4e3f2",
         "would": "Draft a message to the building manager asking for the autumn gutter cleaning to be booked before "
                  "the first frost, attach last year's invoice from the house folder, offer two weekday mornings next "
                  "week, and add a reminder to Today to check for an answer on Friday",
         "because": "You said the gutters overflowed in the last storm, that the building manager books the cleaning "
                    "every autumn, and that you want it done before the first frost so the hallway ceiling does not "
                    "get wet again like last winter",
         "capture": "c1113-07", "state": "open", "action": None},
        {"handle": "P-1112-8", "rev": "e0a1b2c3d4f5",
         "would": "Draft an email to the letting agent asking who insures the garden shed",
         "because": "You asked to find out who insures the garden shed", "capture": "c1112-09", "state": "open",
         "action": None},
        {"handle": "P-1113-4", "rev": "f1e2d3c4b5a6",
         "would": "Look up the library's Sunday opening hours and add them to Today",
         "because": "A quick lookup answers this capture", "capture": "c1112-06", "state": "open", "action": None},
    ],
    "questions": [
        {"handle": "Q-1113-1", "rev": "0f9e8d7c6b5a",
         "question": "Which account should the gym membership come out of?",
         "options": ["Current account", "Savings account", "Leave it for now"], "about": "c1113-05-1",
         "capture": "c1113-06", "state": "open", "answer": None},
    ],
    "results": [
        {"handle": "A-1112-6", "title": "Swimming pool monthly pass price", "date": "2026-11-12", "kind": "lookup",
         "asked": "How much is a monthly pass at the swimming pool?",
         "answer": "A monthly pass costs 32 euros; off-peak passes are cheaper.", "capture": "c1112-06",
         "has_draft": False},
        {"handle": "A-1113-2", "title": "Notes for the boiler service visit", "date": "2026-11-13", "kind": "prep",
         "asked": "Prepare notes for the boiler service visit",
         "answer": "Three things to raise with the engineer, and a draft message to the landlord.",
         "capture": "c1113-07", "has_draft": True},
    ],
    "actions": {"queued": 1, "running": 0, "blocked": 0, "failed": 0},
    "brief": {"date": "2026-11-13", "recorded": True, "lines": [
        "Morning brief · Fri 13 Nov",
        "",
        "Today (3)",
        "• Buy a birthday card and the ingredients for a vegetable lasagna · c1112-03-1",
        "• Pick up the dry cleaning · c1113-07-1",
        "• Return the library books, overdue · c1111-02-1",
        "",
        "Waiting (2)",
        "• Landlord: date for the boiler service · w1113-2",
        "• Plumber: quote for the kitchen tap · w1112-1",
    ]},
    "health": {"brief_ran_today": True, "last_result": {"handle": "A-1113-2", "date": "2026-11-13"},
               "board_date": "2026-11-13"},
    "settings": {"brief_time": "07:40", "vocabulary": ["Lasagna", "Boiler", "Tyres"]},
    "unreadable": [
        {"file": "2026-W46.md", "line": 14, "text": "- [ ] ring about the ??? before Tuesday"},
    ],
}

docs = {
    "A-1112-6|result": {"handle": "A-1112-6", "part": "result", "title": "Swimming pool monthly pass price",
                        "markdown": "## A-1112-6 · Swimming pool monthly pass price\n\n"
                                    "A monthly pass costs 32 euros; off-peak passes are cheaper.\n\n"
                                    "- Adult monthly: 32 euros\n- Off-peak monthly: 24 euros\n- Ten swims: 45 euros\n\n"
                                    "Prices checked on the pool's own price list.\n"},
    "A-1113-2|result": {"handle": "A-1113-2", "part": "result", "title": "Notes for the boiler service visit",
                        "markdown": "## A-1113-2 · Notes for the boiler service visit\n\n"
                                    "Three things to raise with the engineer:\n\n"
                                    "- The pressure drops every few weeks\n- The radiator in the hall stays cold\n"
                                    "- Ask for the service certificate by email\n"},
    "A-1113-2|draft": {"handle": "A-1113-2", "part": "draft", "title": "Notes for the boiler service visit",
                       "markdown": "## Draft message to the landlord\n\n"
                                   "Hello, could you tell me the date of the boiler service this month? Thank you.\n"},
}

json.dump(snapshot, open(os.path.join(out, "snapshot.json"), "w"), indent=2, ensure_ascii=False)
json.dump(docs, open(os.path.join(out, "docs.json"), "w"), indent=2, ensure_ascii=False)


# Shape check: every object path in the new snapshot has exactly the keys, and only the leaf types,
# that the server-verified snapshot has at the same path (lists merged across elements).
def tname(v):
    return "null" if v is None else {bool: "bool", int: "int", float: "number", str: "string",
                                     list: "array", dict: "object"}[type(v)]


def sig(value, path="$", acc=None):
    acc = {} if acc is None else acc
    e = acc.setdefault(path, {"types": set(), "keys": set()})
    e["types"].add(tname(value))
    if isinstance(value, dict):
        e["keys"] |= set(value)
        for k, v in value.items():
            sig(v, f"{path}.{k}", acc)
    elif isinstance(value, list):
        for v in value:
            sig(v, path + "[]", acc)
    return acc


ref = sig(json.load(open(os.path.join(src, "snapshot.json"))))
new = sig(snapshot)
problems = []
for path, e in new.items():
    if path not in ref:
        problems.append(f"{path} not in verified fixture")
        continue
    if not e["types"] <= ref[path]["types"]:
        problems.append(f"{path} types {sorted(e['types'])} vs verified {sorted(ref[path]['types'])}")
    if "object" in e["types"] and e["keys"] != ref[path]["keys"]:
        problems.append(f"{path} keys {sorted(e['keys'] ^ ref[path]['keys'])} differ")
ref_doc = sig(json.load(open(os.path.join(src, "doc.json"))))
for d in docs.values():
    for path, e in sig(d).items():
        if path not in ref_doc or not e["types"] <= ref_doc[path]["types"] or e["keys"] != ref_doc[path]["keys"]:
            problems.append(f"doc {path} differs")
print("SHAPES " + ("OK" if not problems else "FAIL: " + "; ".join(problems)))
sys.exit(1 if problems else 0)
