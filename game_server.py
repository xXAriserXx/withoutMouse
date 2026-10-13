#!/usr/bin/env python3
"""Serves game.html and keeps its scores in a JSON file.

    python3 game_server.py [--host 127.0.0.1] [--port 8095] [--scores PATH]

GET  /             -> game.html
GET  /api/scores   -> {"best": {"mixed/medium": 41.2, ...}, "runs": [...latest first]}
POST /api/scores   -> body: one run {mode, size, score, total, misses, avg}; returns
                      {"best": ..., "previousBest": <score or null>, "runs": ...}

Standard library only (the Mac mini has the system Python 3.9).
"""
import argparse
import json
import os
import tempfile
import threading
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HERE = os.path.dirname(os.path.abspath(__file__))
GAME_FILE = os.path.join(HERE, "game.html")
DEFAULT_SCORES = os.path.expanduser("~/Library/Application Support/WhiteWindowGame/scores.json")

MODES = {"click", "mixed", "drag"}
SIZES = {"large", "medium", "small"}
MAX_RUNS_RETURNED = 50

lock = threading.Lock()


def load_runs(path):
    try:
        with open(path) as f:
            data = json.load(f)
        return data.get("runs", []) if isinstance(data, dict) else []
    except (FileNotFoundError, json.JSONDecodeError):
        return []


def save_runs(path, runs):
    # Write to a temp file and rename, so a crash never leaves half a file
    os.makedirs(os.path.dirname(path), exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path), suffix=".tmp")
    with os.fdopen(fd, "w") as f:
        json.dump({"runs": runs}, f, indent=1)
    os.replace(tmp, path)


def bests(runs):
    best = {}
    for r in runs:
        key = f"{r['mode']}/{r['size']}"
        if key not in best or r["score"] < best[key]:
            best[key] = r["score"]
    return best


def parse_run(body):
    run = json.loads(body)
    if run.get("mode") not in MODES or run.get("size") not in SIZES:
        raise ValueError("bad mode or size")
    clean = {"mode": run["mode"], "size": run["size"]}
    for field in ("score", "total", "avg"):
        value = float(run[field])
        if not 0 <= value < 100000:
            raise ValueError(f"bad {field}")
        clean[field] = round(value, 3)
    clean["misses"] = int(run["misses"])
    clean["date"] = datetime.now(timezone.utc).isoformat(timespec="seconds")
    return clean


class Handler(BaseHTTPRequestHandler):
    scores_path = DEFAULT_SCORES

    def send_json(self, status, payload):
        body = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path in ("/", "/index.html", "/game.html"):
            with open(GAME_FILE, "rb") as f:
                body = f.read()
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(body)
        elif self.path == "/api/scores":
            with lock:
                runs = load_runs(self.scores_path)
            self.send_json(200, {"best": bests(runs), "runs": runs[::-1][:MAX_RUNS_RETURNED]})
        else:
            self.send_error(404)

    def do_POST(self):
        if self.path != "/api/scores":
            self.send_error(404)
            return
        length = int(self.headers.get("Content-Length", 0))
        if length > 10000:
            self.send_error(413)
            return
        try:
            run = parse_run(self.rfile.read(length))
        except (ValueError, KeyError, TypeError) as e:
            self.send_json(400, {"error": str(e)})
            return
        with lock:
            runs = load_runs(self.scores_path)
            previous = bests(runs).get(f"{run['mode']}/{run['size']}")
            runs.append(run)
            save_runs(self.scores_path, runs)
        self.send_json(200, {"best": bests(runs), "previousBest": previous,
                             "runs": runs[::-1][:MAX_RUNS_RETURNED]})

    def log_message(self, fmt, *args):
        print(f"{self.address_string()} {fmt % args}", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8095)
    parser.add_argument("--scores", default=DEFAULT_SCORES)
    args = parser.parse_args()
    Handler.scores_path = os.path.expanduser(args.scores)
    server = ThreadingHTTPServer((args.host, args.port), Handler)
    print(f"Serving game on http://{args.host}:{args.port} (scores: {Handler.scores_path})", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
