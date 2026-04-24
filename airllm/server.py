"""
airllm/server.py — Ollama-compatible HTTP server backed by AirLLM.

Speaks the exact API the hackcode Rust binary calls:
GET  /api/tags       model list
GET  /api/version    version string
POST /api/chat       NDJSON streaming chat
POST /api/generate   NDJSON streaming generate
POST /api/show       model info
POST /api/pull       acknowledge pull (model loads lazily on first use)
"""
from __future__ import annotations
import argparse
import datetime
import json
import os
import sys
import threading
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from airllm.models import list_local, resolve

_name:  str | None = None
_model             = None
_lock              = threading.Lock()

def _load(name: str) -> None:
    global _name, _model
    if _name == name:
        return
    with _lock:
        if _name == name:
            return
        from airllm.loader import AirLLMLoader
        path   = resolve(name)
        print(f"[AirLLM] Loading {name} from {path}", flush=True)
        _model = AirLLMLoader(path)
        _name  = name
        print("[AirLLM] Model ready", flush=True)

def _now() -> str:
    return datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%S.%fZ")

def _chat_line(model: str, text: str, done: bool) -> bytes:
    d: dict = {"model": model, "created_at": _now(), "message": {"role": "assistant", "content": text}, "done": done}
    if done:
        d.update({"total_duration": 0, "load_duration": 0, "prompt_eval_count": 0, "eval_count": 0, "eval_duration": 0})
    return (json.dumps(d) + "\n").encode()

def _gen_line(model: str, text: str, done: bool) -> bytes:
    return (json.dumps({"model": model, "created_at": _now(), "response": text, "done": done}) + "\n").encode()

class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_): pass

    def do_GET(self):
        if   self.path == "/api/tags":    self._json({"models": list_local()})
        elif self.path == "/api/version": self._json({"version": "airllm-0.1"})
        else:                             self._json({})
    
    def do_POST(self):
        body = self._body()
        if body is None:
            return
        if   self.path == "/api/chat":     self._chat(body)
        elif self.path == "/api/generate": self._generate(body)
        elif self.path == "/api/show":     self._show(body)
        elif self.path == "/api/pull":     self._pull(body)
        else:                              self._json({})
    
    def _chat(self, body: dict):
        model = body.get("model", "hackcode-uncensored")
        msgs  = body.get("messages", [])
        opts  = body.get("options", {})
        kw    = {"max_new_tokens": int(opts.get("num_predict", body.get("num_predict", 512))),
                 "temperature": float(opts.get("temperature", 0.7)),
                 "top_p":       float(opts.get("top_p", 0.95)),
                 "top_k":       int(opts.get("top_k", 40))}
        if not body.get("stream", True):
            _load(model)
            text = "".join(_model.generate(msgs, **kw))
            return self._json({"model": model, "created_at": _now(),
                               "message": {"role": "assistant", "content": text}, "done": True})
        self._stream_headers()
        try:
            _load(model)
            for tok in _model.generate(msgs, **kw):
                self._chunk(_chat_line(model, tok, False))
            self._chunk(_chat_line(model, "", True))
            self._chunk(b"")
        except BrokenPipeError:
            pass
        except Exception as e:
            print(f"[AirLLM] generation error: {e}", file=sys.stderr)
    
    def _generate(self, body: dict):
        model = body.get("model", "hackcode-uncensored")
        msgs  = [{"role": "user", "content": body.get("prompt", "")}]
        opts  = body.get("options", {})
        kw    = {"max_new_tokens": int(opts.get("num_predict", 512)),
                 "temperature": float(opts.get("temperature", 0.7)),
                 "top_p": float(opts.get("top_p", 0.95))}
        self._stream_headers()
        try:
            _load(model)
            for tok in _model.generate(msgs, **kw):
                self._chunk(_gen_line(model, tok, False))
            self._chunk(_gen_line(model, "", True))
            self._chunk(b"")
        except BrokenPipeError:
            pass
    
    def _show(self, body: dict):
        m = body.get("model", "hackcode-uncensored")
        self._json({"modelfile": f"FROM {m}", "parameters": "",
                    "details": {"family": "qwen", "format": "safetensors"}})
    
    def _pull(self, body: dict):
        model = body.get("model", "hackcode-uncensored")
        self.send_response(200)
        self.send_header("Content-Type", "application/x-ndjson")
        self.end_headers()
        for s in ["pulling manifest", f"queued {model}", "success"]:
            self.wfile.write((json.dumps({"status": s}) + "\n").encode())
            self.wfile.flush()
    
    def _body(self) -> dict | None:
        n = int(self.headers.get("Content-Length", 0))
        if n == 0:
            return {}
        try:
            return json.loads(self.rfile.read(n))
        except Exception as e:
            self.send_error(400, str(e)); return None
    
    def _json(self, obj: dict):
        data = json.dumps(obj).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)
    
    def _stream_headers(self):
        self.send_response(200)
        self.send_header("Content-Type", "application/x-ndjson")
        self.send_header("Transfer-Encoding", "chunked")
        self.end_headers()
    
    def _chunk(self, data: bytes):
        self.wfile.write(f"{len(data):X}\r\n".encode() + data + b"\r\n")
        self.wfile.flush()

class _Server(HTTPServer):
    def process_request(self, req, addr):
        threading.Thread(target=self._h, args=(req, addr), daemon=True).start()
    def _h(self, req, addr):
        try:    self.finish_request(req, addr)
        except: self.handle_error(req, addr)
        finally: self.shutdown_request(req)
    
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("–host",  default="127.0.0.1")
    ap.add_argument("–port",  type=int, default=int(os.environ.get("AIRLLM_PORT", 11434)))
    ap.add_argument("–model", default="")
    args = ap.parse_args()
    if args.model:
        threading.Thread(target=_load, args=(args.model,), daemon=True).start()
    srv = _Server((args.host, args.port), Handler)
    print(f"[AirLLM] Listening on {args.host}:{args.port}", flush=True)
    try:    srv.serve_forever()
    except KeyboardInterrupt: print("\n[AirLLM] Stopped.")
    
if __name__ == "__main__":
    main()