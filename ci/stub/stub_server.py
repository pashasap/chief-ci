"""Contract v1 stub server for the Kit (Chief) app. Python standard library only.
Usage: python3 -I stub_server.py --fixtures DIR --cert CERT --key KEY --token TOKEN --port 8443 --log FILE
Serves HTTPS on [::] (dual stack, so localhost resolves either way). Every request is appended to --log as JSON."""
import argparse
import hashlib
import json
import socket
import ssl
import threading
import time
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

p = argparse.ArgumentParser()
p.add_argument("--fixtures", required=True)
p.add_argument("--cert", required=True)
p.add_argument("--key", required=True)
p.add_argument("--token", required=True)
p.add_argument("--port", type=int, default=8443)
p.add_argument("--log", required=True)
args = p.parse_args()


def load(name):
    with open(f"{args.fixtures}/{name}") as f:
        return json.load(f)


STATE = load("snapshot.json")
DOCS = load("docs.json")
CREATED = load("capture_created.json")
OK = load("command_ok.json")
LOCK = threading.RLock()
SEEN_COMMANDS = {}
SEEN_CAPTURES = {}
AUDIO = set()
CAPTURE_KEYS = {"client_id", "recorded_at", "kind", "duration_s", "text", "transcriber", "locale", "has_audio", "alt"}
COMMAND_KEYS = {"id", "type", "handle", "rev", "args"}


def now():
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def snapshot_bytes():
    body = json.dumps(STATE, ensure_ascii=False).encode()
    return body, '"' + hashlib.sha1(body).hexdigest()[:16] + '"'


def find(handle):
    for key in ("tasks", "notes", "waiting", "candidates", "proposals", "questions"):
        for it in STATE[key]:
            if it["handle"] == handle:
                return key, it
    return None, None


def new_rev(it):
    it["rev"] = hashlib.sha1((it.get("rev", "") + now()).encode()).hexdigest()[:12]


def apply(cmd):
    """Applies a command to the in-memory snapshot as the contract describes. Returns (status, body, note)."""
    kind, it = find(cmd["handle"])
    if it is None:
        return 404, {"error": {"code": "not_found", "message": "Unknown handle"}}, "unknown handle"
    rev_note = "rev ok" if cmd.get("rev") == it.get("rev") else f"rev mismatch (sent {cmd.get('rev')}, have {it.get('rev')})"
    t, a = cmd["type"], cmd.get("args") or {}
    states = {"proposal.approve": "approved", "proposal.reject": "rejected", "proposal.change": "changing",
              "task.done": "done", "task.reopen": "open", "task.drop": "dropped", "waiting.close": "closed"}
    if t in states:
        it["state"] = states[t]
        if t == "proposal.approve":
            # The real server queues an action for an approved suggestion; the app shows "Queued as <id>".
            it["action"] = "A-1113-%d" % (7 + len([p for p in STATE["proposals"] if p.get("action")]))
    elif t == "question.answer":
        it["state"] = "answered"
        it["answer"] = it["options"][a["option"]] if "option" in a else a.get("text")
    elif t == "task.defer":
        it["when"] = a.get("when")
    elif t == "item.remove":
        STATE[kind] = [x for x in STATE[kind] if x is not it]
    elif t in ("item.reclassify", "item.correct"):
        pass
    else:
        return 400, {"error": {"code": "invalid_request", "message": f"Unknown command type {t}"}}, "bad type"
    new_rev(it)
    return 200, OK, rev_note


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def setup(self):
        self.request.settimeout(30)
        try:
            self.request.do_handshake()  # in the handler thread, so one stuck client cannot block accept()
        except (ssl.SSLError, OSError) as e:
            with LOCK, open(args.log, "a") as f:
                f.write(json.dumps({"t": now(), "tls_handshake_failed": str(e)[:200]}) + "\n")
            raise
        super().setup()

    def log_message(self, *a):
        pass

    def record(self, status, note="", body=b""):
        entry = {"t": now(), "method": self.command, "path": self.path, "status": status,
                 "auth": self.auth_state, "if_none_match": self.headers.get("If-None-Match"),
                 "content_type": self.headers.get("Content-Type"), "note": note}
        if body:
            try:
                entry["body"] = json.loads(body)
            except Exception:
                entry["body_bytes"] = len(body)
        with LOCK, open(args.log, "a") as f:
            f.write(json.dumps(entry, ensure_ascii=False) + "\n")

    def send(self, status, obj=None, headers=None, note="", reqbody=b""):
        data = b"" if obj is None else (obj if isinstance(obj, bytes) else json.dumps(obj).encode())
        self.send_response(status)
        if data:
            self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        for k, v in (headers or {}).items():
            self.send_header(k, v)
        self.end_headers()
        if data and self.command != "HEAD":
            self.wfile.write(data)
        self.record(status, note, reqbody)

    def body(self):
        n = int(self.headers.get("Content-Length") or 0)
        return self.rfile.read(n) if n else b""

    def authed(self):
        got = self.headers.get("Authorization", "")
        self.auth_state = "ok" if got == "Bearer " + args.token else ("missing" if not got else "wrong")
        return self.auth_state == "ok"

    def unauthorized(self, raw=b""):
        self.send(401, {"error": {"code": "unauthorized", "message": "Missing or wrong token"}}, reqbody=raw)

    def do_GET(self):
        url = urllib.parse.urlsplit(self.path)
        if not self.authed():
            return self.unauthorized()
        with LOCK:
            if url.path == "/v1/health":
                return self.send(200, {"ok": True, "api": 1, "time": now()})
            if url.path == "/v1/snapshot":
                data, etag = snapshot_bytes()
                if self.headers.get("If-None-Match") == etag:
                    return self.send(304, None, {"ETag": etag}, note="not modified")
                return self.send(200, data, {"ETag": etag}, note=f"etag {etag}")
            if url.path == "/v1/doc":
                q = urllib.parse.parse_qs(url.query)
                key = f"{q.get('handle', [''])[0]}|{q.get('part', [''])[0]}"
                if key in DOCS:
                    return self.send(200, DOCS[key], note=key)
                return self.send(404, {"error": {"code": "not_found", "message": "Unknown handle or part"}}, note=key)
        self.send(404, {"error": {"code": "not_found", "message": "Unknown path"}})

    def do_PUT(self):
        raw = self.body()
        url = urllib.parse.urlsplit(self.path)
        if not self.authed():
            return self.unauthorized(raw)
        parts = url.path.strip("/").split("/")
        if len(parts) == 4 and parts[:2] == ["v1", "captures"] and parts[3] == "audio":
            AUDIO.add(parts[2])
            return self.send(204, None, note=f"audio {len(raw)} bytes", reqbody=b"")
        if url.path == "/v1/device/push-token":
            return self.send(204, None, reqbody=raw)
        self.send(404, {"error": {"code": "not_found", "message": "Unknown path"}}, reqbody=raw)

    def do_POST(self):
        raw = self.body()
        url = urllib.parse.urlsplit(self.path)
        if not self.authed():
            return self.unauthorized(raw)
        try:
            req = json.loads(raw or b"null")
            assert isinstance(req, dict)
        except Exception:
            return self.send(400, {"error": {"code": "invalid_request", "message": "Body is not a JSON object"}}, reqbody=raw)
        with LOCK:
            if url.path == "/v1/captures":
                extra = set(req) - CAPTURE_KEYS
                if extra or "client_id" not in req:
                    return self.send(400, {"error": {"code": "invalid_request", "message": f"Unknown or missing field {sorted(extra)}"}}, reqbody=raw)
                cid = req["client_id"]
                if cid in SEEN_CAPTURES:
                    return self.send(200, SEEN_CAPTURES[cid], note="repeat", reqbody=raw)
                n = len(SEEN_CAPTURES) + 10
                answer = dict(CREATED, id=f"c1113-{n:02d}")
                SEEN_CAPTURES[cid] = answer
                STATE["captures"].insert(0, {"id": answer["id"], "date": STATE["today"], "time": "15:00",
                                             "source": "app", "client_id": cid, "text": req.get("text", ""),
                                             "status": "on_server", "status_note": "", "items": []})
                return self.send(201, answer, reqbody=raw)
            if url.path == "/v1/commands":
                extra = set(req) - COMMAND_KEYS
                if extra or not {"id", "type", "handle"} <= set(req):
                    return self.send(400, {"error": {"code": "invalid_request", "message": f"Unknown or missing field {sorted(extra)}"}}, reqbody=raw)
                if req["id"] in SEEN_COMMANDS:
                    status, body = SEEN_COMMANDS[req["id"]]
                    return self.send(status, body, note="repeat", reqbody=raw)
                status, body, note = apply(req)
                SEEN_COMMANDS[req["id"]] = (status, body)
                return self.send(status, body, note=note, reqbody=raw)
        self.send(404, {"error": {"code": "not_found", "message": "Unknown path"}}, reqbody=raw)


class DualStack(ThreadingHTTPServer):
    address_family = socket.AF_INET6
    daemon_threads = True

    def server_bind(self):
        # HTTPServer.server_bind calls socket.getfqdn('::'), which can stall for many seconds on a CI Mac.
        self.socket.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 0)
        self.socket.bind(self.server_address)
        self.server_address = self.socket.getsockname()
        self.server_name, self.server_port = "localhost", self.server_address[1]


server = DualStack(("::", args.port), Handler)
ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
ctx.load_cert_chain(args.cert, args.key)
server.socket = ctx.wrap_socket(server.socket, server_side=True, do_handshake_on_connect=False)
print(f"stub listening on https://localhost:{args.port}", flush=True)
server.serve_forever()
