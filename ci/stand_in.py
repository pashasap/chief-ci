"""A stand-in HTTPS server for the API of a native product, played against by its journeys (issue #94).

A public CI runner cannot reach the product's real server, so the journeys job starts this server on the runner,
on localhost, with a certificate that the simulator trusts (`ci/stand_in_cert.sh`, `ci/stand_in_start.sh`). Standard
library only: the runner copies this file as `ci/stand_in.py` and runs it with its own `python3`.

The data file (`native_ci/stand_ins/<product>/data.json`) holds invented content only, because the public CI copy
and its artifacts can be read from the internet. Its presence is the declaration: a product without one gets no
stand-in part. The server answers the endpoints of the Kit API contract (health, snapshot with ETag, document,
audio upload, capture, command, chat), checks the bearer token, and keeps a small script of state changes: a
posted capture moves through the statuses of `filing.statuses` on later snapshot reads and is then filed with one
item, and a command of `commands` changes, or removes, the item it names.

Every request is one JSON line in the request log (`LOG_KEYS`): method, path, query, status, whether the token was
right, the client's user agent, and selected fields of the body. A capture's text, a chat message and audio bytes
are never written. The log is uploaded with the journey artifacts, so a later step or the server-side verdict can
require that a request reached the server (`matching`).
"""
from __future__ import annotations

import argparse
import copy
import fnmatch
import json
import re
import ssl
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qsl, urlsplit

STAND_INS = Path(__file__).resolve().parent / "native_ci" / "stand_ins"
STAND_IN_DATA = "data.json"
STAND_IN_STEP_LISTS = "journeys"
LOG_KEYS = ("seq", "time", "method", "path", "query", "status", "auth", "agent", "fields")
CAPTURE_FIELDS = ("client_id", "kind", "transcriber", "duration_s", "has_audio")
COMMAND_FIELDS = ("id", "type", "handle", "rev", "args")
AUDIO_LIMIT = 16 * 1024 * 1024
AUDIO_PATH = re.compile(r"^/v1/captures/([^/]+)/audio$")
CONTRACT_LISTS = ("captures", "tasks", "notes", "waiting", "candidates", "proposals", "questions", "results",
                  "unreadable")


def product_data(product: str, root: Path = STAND_INS) -> str | None:
    """The text of the stand-in data file a product declares, or None when it declares none."""
    path = Path(root) / product / STAND_IN_DATA
    return path.read_text(encoding="utf-8") if path.is_file() else None


def product_step_lists(product: str, root: Path = STAND_INS) -> list[dict[str, object]]:
    """The step lists played against the product's stand-in, ordered by file name."""
    folder = Path(root) / product / STAND_IN_STEP_LISTS
    return [json.loads(path.read_text(encoding="utf-8")) for path in sorted(folder.glob("*.json"))]


def load_data(text: str) -> dict[str, object]:
    """The data of a stand-in, or ValueError when it lacks a token or a snapshot with an `api` number."""
    data = json.loads(text)
    if not isinstance(data, dict):
        raise ValueError("stand-in data is a JSON object")
    token = data.get("token")
    if not isinstance(token, str) or not token:
        raise ValueError("stand-in data needs a non-empty 'token'")
    snapshot = data.get("snapshot")
    if not isinstance(snapshot, dict) or not isinstance(snapshot.get("api"), int):
        raise ValueError("stand-in data needs a 'snapshot' object with an 'api' number")
    return data


def read_log(path: Path) -> list[dict[str, object]]:
    """The request log as records, oldest first; an absent log is empty."""
    path = Path(path)
    if not path.is_file():
        return []
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]


def matching(records: list[dict[str, object]], method: str, path: str, field: str | None = None,
             value: object = None) -> list[dict[str, object]]:
    """The logged requests with this method, a path that matches `path` (`*` matches one part), and, when `field`
    is given, that field among the selected body fields or the query, equal to `value`."""
    found = []
    for record in records:
        if record.get("method") != method or not fnmatch.fnmatchcase(str(record.get("path")), path):
            continue
        if field is not None:
            seen: dict[str, object] = {}
            for part in (record.get("query"), record.get("fields")):
                if isinstance(part, dict):
                    seen.update({str(k): v for k, v in part.items()})
            if field not in seen or seen[field] != value:
                continue
        found.append(record)
    return found


def _utc_now() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def _problem(status: int, code: str, message: str) -> tuple[int, dict[str, object]]:
    return status, {"error": {"code": code, "message": message}}


class StandInState:
    """The server's state: the snapshot as it changes, the captures and commands already seen, and the log."""

    def __init__(self, data: dict[str, object], log_path: Path):
        self.data = data
        self.token = str(data["token"])
        snapshot = data["snapshot"]
        self.snapshot: dict[str, object] = copy.deepcopy(snapshot) if isinstance(snapshot, dict) else {}
        for name in CONTRACT_LISTS:
            if not isinstance(self.snapshot.get(name), list):
                self.snapshot[name] = []
        filing = data.get("filing")
        self.filing: dict[str, object] = filing if isinstance(filing, dict) else {}
        commands = data.get("commands")
        self.commands: dict[str, object] = commands if isinstance(commands, dict) else {}
        self.version = 1
        self.captures: dict[str, tuple[int, dict[str, object]]] = {}
        self.pending: list[dict[str, object]] = []
        self.done: dict[str, tuple[int, dict[str, object]]] = {}
        self.texts: dict[str, str] = {}
        self.seq = 0
        self.lock = threading.Lock()
        self.log_path = Path(log_path)
        self.log_path.parent.mkdir(parents=True, exist_ok=True)

    def list_of(self, name: str) -> list[dict[str, object]]:
        value = self.snapshot.get(name)
        return value if isinstance(value, list) else []

    def rendered(self) -> dict[str, object]:
        out = copy.deepcopy(self.snapshot)
        now = _utc_now()
        out["generated_at"] = now
        if not out.get("today"):
            out["today"] = now[:10]
        return out

    def advance(self) -> None:
        listed = self.filing.get("statuses")
        statuses = [str(s) for s in listed] if isinstance(listed, list) else []
        for capture in list(self.pending):
            current = str(capture.get("status"))
            following = statuses[statuses.index(current) + 1] if current in statuses else (statuses or [None])[0]
            if following is None:
                self.pending.remove(capture)
                continue
            capture["status"] = following
            if following == statuses[-1]:
                self.pending.remove(capture)
                self.file(capture)
            self.version += 1

    def file(self, capture: dict[str, object]) -> None:
        kind = str(self.filing.get("item_kind") or "note")
        handle = f"{capture['id']}-1"
        text = self.texts.get(str(capture["id"]), "")
        capture["items"] = [{"handle": handle, "kind": kind, "text": text, "state": "open"}]
        listed = {"note": "notes", "task": "tasks"}.get(kind)
        if listed == "notes":
            self.list_of("notes").insert(0, {"handle": handle, "rev": "rev-1", "text": text, "note": "",
                                             "capture": capture["id"]})
        elif listed == "tasks":
            self.list_of("tasks").insert(0, {"handle": handle, "rev": "rev-1", "text": text, "note": "",
                                             "when": {"kind": "later", "date": None}, "state": "open",
                                             "capture": capture["id"], "pick": None})

    def answer(self, method: str, target: str, headers: dict[str, str],
               body: bytes) -> tuple[int, dict[str, str], bytes, dict[str, object], str, dict[str, str]]:
        """(status, response headers, response body, logged fields, auth word, query) of one request."""
        parts = urlsplit(target)
        path, query = parts.path, dict(parse_qsl(parts.query))
        given = headers.get("authorization", "")
        auth = "ok" if given == "Bearer " + self.token else "missing" if not given else "wrong"
        fields: dict[str, object] = {}
        extra: dict[str, str] = {}
        with self.lock:
            if auth != "ok":
                status, doc = _problem(401, "unauthorized", "Missing or wrong token")
            else:
                status, doc = self.route(method, path, query, headers, body, fields, extra)
        payload = b"" if doc is None else json.dumps(doc).encode("utf-8")
        if payload:
            extra["Content-Type"] = "application/json"
        return status, extra, payload, fields, auth, query

    def route(self, method: str, path: str, query: dict[str, str], headers: dict[str, str], body: bytes,
              fields: dict[str, object], extra: dict[str, str]) -> tuple[int, dict[str, object] | None]:
        audio = AUDIO_PATH.match(path)
        if method == "GET" and path == "/v1/health":
            return 200, {"ok": True, "api": self.snapshot.get("api"), "time": _utc_now()}
        if method == "GET" and path == "/v1/snapshot":
            etag = f'"v{self.version}"'
            extra["ETag"] = etag
            if headers.get("if-none-match") == etag:
                return 304, None
            doc = self.rendered()
            self.advance()
            return 200, doc
        if method == "GET" and path == "/v1/doc":
            docs = self.data.get("docs") if isinstance(self.data.get("docs"), dict) else {}
            entry = docs.get(query.get("handle", "")) if isinstance(docs, dict) else None
            part = entry.get(query.get("part", "")) if isinstance(entry, dict) else None
            if not isinstance(part, dict):
                return _problem(404, "not_found", "Unknown handle or part")
            return 200, {"handle": query["handle"], "part": query["part"], "title": part.get("title", ""),
                         "markdown": part.get("markdown", "")}
        if method == "PUT" and audio:
            fields.update({"client_id": audio.group(1), "content_type": headers.get("content-type", ""),
                           "bytes": len(body)})
            if len(body) > AUDIO_LIMIT:
                return _problem(413, "too_large", "Audio over 16 MB")
            return 204, None
        if method == "POST" and path == "/v1/captures":
            return self.capture(body, fields)
        if method == "POST" and path == "/v1/commands":
            return self.command(body, fields)
        if method == "POST" and path == "/v1/chat":
            return self.chat(body, fields)
        return _problem(404, "not_found", "Unknown path")

    def capture(self, body: bytes, fields: dict[str, object]) -> tuple[int, dict[str, object]]:
        doc = _json_object(body)
        if doc is None or not isinstance(doc.get("client_id"), str) or not isinstance(doc.get("kind"), str):
            return _problem(400, "invalid_request", "A capture needs a client_id and a kind")
        fields.update({k: doc[k] for k in CAPTURE_FIELDS if k in doc})
        client = str(doc["client_id"])
        if client in self.captures:
            return 200, self.captures[client][1]
        number = len(self.captures) + 1
        capture_id = f"{self.filing.get('id_prefix') or 'c0000-'}{number:02d}"
        now = _utc_now()
        record: dict[str, object] = {"id": capture_id, "date": now[:10], "time": now[11:16], "source": "app",
                                     "client_id": client, "text": str(doc.get("text") or ""), "status": "on_server",
                                     "status_note": "", "items": []}
        self.texts[capture_id] = str(doc.get("text") or "")
        self.list_of("captures").insert(0, record)
        self.pending.append(record)
        self.version += 1
        answer: dict[str, object] = {"id": capture_id, "status": "on_server"}
        self.captures[client] = (201, answer)
        return 201, answer

    def command(self, body: bytes, fields: dict[str, object]) -> tuple[int, dict[str, object]]:
        doc = _json_object(body)
        if doc is None or not all(isinstance(doc.get(k), str) for k in ("id", "type", "handle")):
            return _problem(400, "invalid_request", "A command needs an id, a type and a handle")
        fields.update({k: doc[k] for k in COMMAND_FIELDS if k in doc})
        if str(doc["id"]) in self.done:
            return self.done[str(doc["id"])]
        rule = self.commands.get(str(doc["type"]))
        if not isinstance(rule, dict):
            return _problem(422, "rejected", f"The stand-in has no script for {doc['type']}")
        items = self.list_of(str(rule.get("list")))
        item = next((i for i in items if isinstance(i, dict) and i.get("handle") == doc["handle"]), None)
        if item is None:
            return _problem(404, "not_found", "Unknown handle")
        if "rev" in item and doc.get("rev") != item["rev"]:
            return _problem(409, "stale", "This changed since you read it")
        args = doc.get("args") if isinstance(doc.get("args"), dict) else {}
        if rule.get("remove"):
            items.remove(item)
            for capture in self.list_of("captures"):
                held = capture.get("items")
                if isinstance(held, list):
                    capture["items"] = [i for i in held if not (isinstance(i, dict) and i.get("handle") == doc["handle"])]
        else:
            changes = rule.get("set")
            if isinstance(changes, dict):
                item.update({str(k): v for k, v in changes.items()})
            taken = rule.get("from_args")
            for key, arg in (taken.items() if isinstance(taken, dict) else ()):
                if isinstance(args, dict) and arg in args:
                    item[str(key)] = args[arg]
            self.version += 1
            item["rev"] = f"{item.get('rev', 'rev')}.{self.version}"
        self.version += 1
        result: tuple[int, dict[str, object]] = (200, {"ok": True})
        self.done[str(doc["id"])] = result
        return result

    def chat(self, body: bytes, fields: dict[str, object]) -> tuple[int, dict[str, object]]:
        doc = _json_object(body)
        messages = doc.get("messages") if doc is not None else None
        session = doc.get("session_id") if doc is not None else None
        if not isinstance(session, str) or not isinstance(messages, list) or not messages:
            return _problem(400, "invalid_request", "A chat needs a session_id and messages")
        fields.update({"session_id": session, "messages": len(messages)})
        last = messages[-1]
        if not isinstance(last, dict) or last.get("role") != "user" or not last.get("content"):
            return _problem(400, "invalid_request", "The last message is the user's")
        return 200, {"session_id": session, "reply": str(self.data.get("chat_reply") or "Stand-in reply."),
                     "model": "stand-in"}

    def write_log(self, record: dict[str, object]) -> None:
        with self.lock:
            self.seq += 1
            line = {"seq": self.seq, **record}
            with self.log_path.open("a", encoding="utf-8") as out:
                out.write(json.dumps({k: line[k] for k in LOG_KEYS}, sort_keys=True) + "\n")


def _json_object(body: bytes) -> dict[str, object] | None:
    try:
        doc = json.loads(body.decode("utf-8")) if body else None
    except (ValueError, UnicodeDecodeError):
        return None
    return doc if isinstance(doc, dict) else None


class StandInServer(ThreadingHTTPServer):
    """A threading HTTPS server that holds one `StandInState`."""

    daemon_threads = True

    def __init__(self, address: tuple[str, int], state: StandInState):
        super().__init__(address, StandInHandler)
        self.state = state

    @property
    def port(self) -> int:
        return int(self.server_address[1])

    def close(self) -> None:
        self.shutdown()
        self.server_close()

    def handle_error(self, request: object, client_address: object) -> None:
        problem = sys.exc_info()[1]
        sys.stderr.write(f"{_utc_now()} stand-in: connection from {client_address} failed: {problem!r}\n")
        sys.stderr.flush()


class StandInHandler(BaseHTTPRequestHandler):
    """One request: read the body, let the state answer, send the answer, write the log line."""

    protocol_version = "HTTP/1.1"
    server_version = "FactoryStandIn/1"

    def do_GET(self) -> None:
        self.serve("GET")

    def do_POST(self) -> None:
        self.serve("POST")

    def do_PUT(self) -> None:
        self.serve("PUT")

    def do_DELETE(self) -> None:
        self.serve("DELETE")

    def serve(self, method: str) -> None:
        server = self.server
        if not isinstance(server, StandInServer):
            raise TypeError("the stand-in handler runs only in a StandInServer")
        length = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(length) if length > 0 else b""
        headers = {k.lower(): v for k, v in self.headers.items()}
        status, extra, payload, fields, auth, query = server.state.answer(method, self.path, headers, body)
        self.send_response(status)
        for name, value in extra.items():
            self.send_header(name, value)
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        if payload:
            self.wfile.write(payload)
        server.state.write_log({"time": _utc_now(), "method": method, "path": urlsplit(self.path).path,
                                "query": query, "status": status, "auth": auth,
                                "agent": headers.get("user-agent", "")[:80], "fields": fields})

    def log_message(self, format: str, *args: object) -> None:
        return None


def start(data: dict[str, object], certfile: Path, keyfile: Path, log_path: Path, host: str = "127.0.0.1",
          port: int = 0) -> StandInServer:
    """Serve `data` over HTTPS on `host:port` (0: a free port) in a background thread; `close()` stops it."""
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.minimum_version = ssl.TLSVersion.TLSv1_2
    context.set_alpn_protocols(["http/1.1"])
    context.load_cert_chain(str(certfile), str(keyfile))
    server = StandInServer((host, port), StandInState(load_data(json.dumps(data)), log_path))
    server.socket = context.wrap_socket(server.socket, server_side=True, do_handshake_on_connect=False)
    threading.Thread(target=server.serve_forever, name="stand-in", daemon=True).start()
    return server


def stand_in_main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Serve a stand-in of a product's API over HTTPS.")
    parser.add_argument("--data", required=True, type=Path)
    parser.add_argument("--cert", required=True, type=Path)
    parser.add_argument("--key", required=True, type=Path)
    parser.add_argument("--log", required=True, type=Path)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8443)
    args = parser.parse_args(argv)
    data = load_data(args.data.read_text(encoding="utf-8"))
    server = start(data, args.cert, args.key, args.log, args.host, args.port)
    print(f"ready {server.port}", flush=True)
    threading.Event().wait()
    return 0


if __name__ == "__main__":
    sys.exit(stand_in_main())
