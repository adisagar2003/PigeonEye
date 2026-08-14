"""Field Log server. Stdlib http.server + one JSON endpoint. No state."""

import json
import os
import traceback
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

HERE = Path(__file__).parent

# Load .env before importing agent, so the SDK client sees the key.
for line in (HERE / ".env").read_text().splitlines() if (HERE / ".env").exists() else []:
    if "=" in line and not line.lstrip().startswith("#"):
        k, _, v = line.partition("=")
        os.environ.setdefault(k.strip(), v.strip().strip("'\""))

import agent  # noqa: E402

MAX_BODY = 256 * 1024  # a voice note is text; anything bigger is not a field note


def run_step(note: str, answers: dict, round_: int) -> dict:
    """One turn of the bounded loop. Stateless: the client carries the answers."""
    e = agent.extract(note, prior=answers)

    if not e.is_field_record:
        return {
            "done": True,
            "refused": True,
            "reason": e.reject_reason or "This does not look like a field record.",
            "step": 2, "max_steps": agent.MAX_STEPS,
        }

    rec = agent.to_record(e) | {k: v for k, v in answers.items() if v}
    gaps = agent.missing(rec)
    step = min(2 + round_ * 2, agent.MAX_STEPS)

    out = {
        "record": rec,
        "missing": gaps,
        "sources": [s.model_dump() for s in e.sources],
        "guessed": e.guessed,
        "step": step,
        "max_steps": agent.MAX_STEPS,
        "round": round_,
    }

    if not gaps:
        return out | {"done": True, "csv": agent.to_csv_row(rec)}

    if round_ >= agent.MAX_ROUNDS:
        # Bounded on purpose: stop asking, refuse to emit an incomplete row.
        return out | {
            "done": True, "incomplete": True,
            "reason": f"Stopped after {agent.MAX_ROUNDS} questions. "
                      f"Still missing: {', '.join(gaps)}. No row written.",
        }

    q = agent.ask(note, rec, gaps[0])
    return out | {"done": False, "question": q.model_dump()}


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def _send(self, code: int, body: bytes, ctype: str):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _json(self, code: int, obj: dict):
        self._send(code, json.dumps(obj).encode(), "application/json")

    def do_GET(self):
        if self.path.split("?")[0] not in ("/", "/index.html"):
            return self._json(404, {"error": "not found"})
        self._send(200, (HERE / "index.html").read_bytes(), "text/html; charset=utf-8")

    def do_POST(self):
        if self.path != "/api/step":
            return self._json(404, {"error": "not found"})
        try:
            n = int(self.headers.get("Content-Length") or 0)
            if n > MAX_BODY:
                return self._json(413, {"error": "note too large"})
            raw = self.rfile.read(n) or b"{}"
            try:
                req = json.loads(raw)
            except (ValueError, UnicodeDecodeError):
                return self._json(400, {"error": "body is not valid JSON"})
            note = str(req.get("note") or "")
            answers = {k: str(v) for k, v in (req.get("answers") or {}).items()}
            round_ = max(0, min(int(req.get("round") or 0), agent.MAX_ROUNDS))
            self._json(200, run_step(note, answers, round_))
        except Exception as exc:
            traceback.print_exc()
            # Clean error to the UI, never a stack trace.
            self._json(502, {"error": f"{type(exc).__name__}: {exc}"})

    def log_message(self, fmt, *args):
        print(f"{self.command} {self.path} -> {args[1] if len(args) > 1 else ''}")


if __name__ == "__main__":
    print("Field Log on http://localhost:8000")
    ThreadingHTTPServer(("127.0.0.1", 8000), Handler).serve_forever()
