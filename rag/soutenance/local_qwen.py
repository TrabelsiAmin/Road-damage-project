"""Qwen Instruct on this CPU, for the dashboard when Colab is offline.

Qwen2.5-7B-Instruct does not load here: there is no GPU, and the free RAM
cannot hold the 4-bit weights. This process loads a smaller Qwen2.5 Instruct
checkpoint and calls generate(). Retrieval is lexical over the same six
manuals. The answer text is the generate() return value, not a pasted chunk.

A live Colab URL still wins: the dashboard only calls this port when the
saved address does not answer /health.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from colab_assistant import build_context, clean_api_answer, make_generate
from local_extract import build_index, fold, tokenize

HOST = "127.0.0.1"
PORT = 4733
# 0.5B invents a price in dinars even when the manuals do not contain one.
# 1.5B Instruct still fits in the free RAM, in bfloat16, with no GPU.
LLM_MODEL = "Qwen/Qwen2.5-1.5B-Instruct"
FINGERPRINTS = {
    "Qwen/Qwen2.5-0.5B-Instruct": {"hidden_size": 896, "num_hidden_layers": 24},
    "Qwen/Qwen2.5-1.5B-Instruct": {"hidden_size": 1536, "num_hidden_layers": 28},
}
DASHBOARD_ORIGIN = "http://127.0.0.1:4317"
ORIGIN_RE = re.compile(r"https?://(?:127\.0\.0\.1|localhost)(?::\d+)?\Z")
CODE_RE = re.compile(r"d\d+")


def order_hits(question, hits):
    """Prefer chunks that contain the question's Dxx codes. Scores stay BM25."""
    codes = []
    seen = set()
    for token in tokenize(question):
        if CODE_RE.fullmatch(token) and token not in seen:
            seen.add(token)
            codes.append(token)
    if not codes:
        return hits

    def key(hit):
        folded = fold(hit["text"])
        covered = sum(code in folded for code in codes)
        return (-covered, -hit["score"])

    return sorted(hits, key=key)


def answer_with_generate(index, question, generate_answer, k=5):
    text = str(question or "").strip()
    if not text:
        raise ValueError("empty_question")
    try:
        limit = int(k)
    except (TypeError, ValueError) as exc:
        raise ValueError("invalid_k") from exc
    if limit < 1 or limit > 8:
        raise ValueError("invalid_k")
    hits = order_hits(text, index.search(text, limit))
    # Two passages: with five, this 1.5B drops the manual name of D40.
    chosen = hits[:2]
    context = build_context(chosen)
    print(f"generate() {LLM_MODEL} question={text!r}", flush=True)
    raw = generate_answer(text, context)
    answer = raw if isinstance(raw, str) else ""
    print(
        f"generate() fini {LLM_MODEL} caractères={len(answer)} début={answer[:160]!r}",
        flush=True,
    )
    return clean_api_answer(answer, chosen)


def assert_fingerprint(model, model_id):
    expected_map = FINGERPRINTS.get(model_id)
    if not expected_map:
        raise RuntimeError(f"Modèle non prévu pour cette machine : {model_id}")
    config = model.config
    if getattr(config, "model_type", "") != "qwen2":
        raise RuntimeError(f"Checkpoint inattendu : {getattr(config, 'model_type', None)}")
    for name, expected in expected_map.items():
        actual = int(getattr(config, name))
        if actual != expected:
            raise RuntimeError(
                f"{model_id} refusé : {name}={actual}, attendu {expected}. "
                "Le serveur ne démarre pas avec un autre modèle."
            )


def load_causal_lm(model_id=LLM_MODEL, model_dir=None):
    import torch
    from transformers import AutoModelForCausalLM, AutoTokenizer

    source = str(model_dir) if model_dir else model_id
    local_only = model_dir is not None
    threads = max(1, min(4, os.cpu_count() or 1))
    torch.set_num_threads(threads)
    print(f"Chargement de {model_id} sur CPU ({threads} fils)…", flush=True)
    tokenizer = AutoTokenizer.from_pretrained(source, local_files_only=local_only)
    # The published checkpoint is bfloat16 (~1 Go). float32 would double it.
    model = AutoModelForCausalLM.from_pretrained(
        source,
        dtype=torch.bfloat16,
        low_cpu_mem_usage=True,
        local_files_only=local_only,
    )
    model.eval()
    assert_fingerprint(model, model_id)
    original = model.generate

    def generate(*args, **kwargs):
        print(f"generate() appel model.generate {model_id}", flush=True)
        return original(*args, **kwargs)

    model.generate = generate
    print(f"{model_id} chargé sur CPU.", flush=True)
    return tokenizer, model


# A function stored on the handler class would be bound as a method.
_STATE = {"index": None, "generate_answer": None, "chunk_count": 0}


class QwenHandler(BaseHTTPRequestHandler):

    def log_message(self, fmt, *args):
        return

    def _send(self, status, payload):
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        origin = self.headers.get("Origin", "")
        if origin == DASHBOARD_ORIGIN or ORIGIN_RE.fullmatch(origin):
            self.send_header("Access-Control-Allow-Origin", origin)
            self.send_header("Vary", "Origin")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header(
            "Access-Control-Allow-Headers",
            "Content-Type, Accept, ngrok-skip-browser-warning, Bypass-Tunnel-Reminder",
        )
        self.end_headers()
        self.wfile.write(body)

    def do_OPTIONS(self):
        self._send(204, {})

    def do_GET(self):
        path = self.path.split("?", 1)[0]
        if path not in ("/health", "/"):
            self._send(404, {"status": "not_found"})
            return
        self._send(200, {
            "status": "ok",
            "llm": LLM_MODEL,
            "retrieval": "lexical",
            "embeddings": None,
            "vectors": _STATE["chunk_count"],
            "gpu": False,
        })

    def do_POST(self):
        path = self.path.split("?", 1)[0]
        if path != "/ask":
            self._send(404, {"status": "not_found"})
            return
        length = int(self.headers.get("Content-Length") or 0)
        if length > 100_000:
            self._send(400, {"error": "body_too_large"})
            return
        raw = self.rfile.read(length) if length else b""
        try:
            payload = json.loads(raw.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError):
            self._send(400, {"error": "invalid_json"})
            return
        question = payload.get("question") if isinstance(payload, dict) else None
        if not isinstance(question, str) or not question.strip():
            self._send(400, {"error": "empty_question"})
            return
        if len(question) > 2000:
            self._send(400, {"error": "question_too_long"})
            return
        try:
            k = int(payload.get("k", 5))
        except (TypeError, ValueError):
            self._send(400, {"error": "invalid_k"})
            return
        try:
            result = answer_with_generate(
                _STATE["index"], question, _STATE["generate_answer"], k
            )
        except ValueError as exc:
            self._send(400, {"error": str(exc)})
            return
        self._send(200, result)


def make_server(generate_answer, host=HOST, port=PORT, corpus_dir=None):
    if corpus_dir is None:
        index, _documents = build_index()
    else:
        index, _documents = build_index(corpus_dir)
    _STATE["index"] = index
    _STATE["generate_answer"] = generate_answer
    _STATE["chunk_count"] = index.count
    return ThreadingHTTPServer((host, port), QwenHandler)


def main(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default=HOST)
    parser.add_argument("--port", type=int, default=PORT)
    parser.add_argument("--model-dir", type=Path, default=None)
    args = parser.parse_args(argv)
    if args.model_dir is not None and not args.model_dir.is_dir():
        print(f"Dossier de poids introuvable : {args.model_dir}", flush=True)
        return 1
    try:
        tokenizer, model = load_causal_lm(LLM_MODEL, args.model_dir)
    except Exception as exc:
        print(f"Chargement impossible : {exc}", flush=True)
        return 1
    generate_answer = make_generate(tokenizer, model)
    try:
        server = make_server(generate_answer, host=args.host, port=args.port)
    except OSError as exc:
        print(f"Le port {args.host}:{args.port} n'a pas pu être ouvert : {exc}", flush=True)
        return 1
    host, port = server.server_address
    print(
        f"{LLM_MODEL} prêt sur http://{host}:{port} "
        f"({_STATE['chunk_count']} morceaux, generate)",
        flush=True,
    )
    server.serve_forever()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
