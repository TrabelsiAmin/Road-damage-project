"""Extractive stand-in for the Colab assistant.

Qwen is not loaded. The answer is a verbatim excerpt of the six manuals
already indexed for the defense, or an explicit statement that the
passage is not in those manuals. Nothing here is a generated quotation.
"""

from __future__ import annotations

import json
import math
import re
import sys
import unicodedata
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from colab_assistant import EXPECTED_DOCS, chunk_text

HOST = "127.0.0.1"
PORT = 4721
CORPUS_DIR = Path(__file__).resolve().parent / "corpus"
TOKEN_RE = re.compile(r"[a-z0-9]+", re.IGNORECASE)
ORIGIN_RE = re.compile(r"https?://(?:127\.0\.0\.1|localhost)(?::\d+)?\Z")
# The prefix is a status line, not a quotation. The rest of a hit is copied
# from a chunk. A miss does not invent a sentence from the manuals.
STATUS_LINE = (
    "Le modèle Colab est arrêté et le tunnel est fermé. "
    "Aucun modèle ne rédige cette réponse."
)
EXCERPT_LEAD = "Extraits des manuels indexés :"
MISSING_LINE = "L'information n'a pas été trouvée dans les manuels indexés."
# Below this BM25 score the overlap is only common words. Do not quote it.
MIN_SCORE = 2.5

STOPWORDS = {
    "a", "au", "aux", "ce", "ces", "dans", "de", "des", "du", "en", "et",
    "la", "le", "les", "ou", "par", "pour", "que", "qui", "sur", "un", "une",
    "the", "and", "for", "of", "to", "in", "on", "with", "from",
}


def fold(text):
    normalized = unicodedata.normalize("NFKD", str(text).lower())
    return "".join(char for char in normalized if not unicodedata.combining(char))


def tokenize(text):
    return [token for token in TOKEN_RE.findall(fold(text)) if token not in STOPWORDS and len(token) > 1]


def load_documents(corpus_dir=CORPUS_DIR):
    folder = Path(corpus_dir)
    documents = []
    missing = []
    for name in EXPECTED_DOCS:
        path = folder / name
        if not path.is_file():
            missing.append(name)
            continue
        text = path.read_text(encoding="utf-8")
        if text.strip():
            documents.append({"source": name, "text": text})
    if missing or len(documents) != len(EXPECTED_DOCS):
        raise FileNotFoundError(
            "Manuels indexés introuvables : " + ", ".join(missing or ["corpus incomplet"])
        )
    return documents


def documents_to_chunks(documents):
    chunks = []
    for document in documents:
        for piece in chunk_text(document["text"]):
            chunks.append({"source": document["source"], "text": piece})
    return chunks


class Bm25:
    def __init__(self, chunks, k1=1.5, b=0.75):
        if not chunks:
            raise ValueError("empty corpus")
        self.chunks = chunks
        self.k1 = k1
        self.b = b
        self.docs = [tokenize(chunk["text"]) for chunk in chunks]
        self.avgdl = sum(len(doc) for doc in self.docs) / len(self.docs)
        self.tf = []
        self.df = {}
        for doc in self.docs:
            counts = {}
            for token in doc:
                counts[token] = counts.get(token, 0) + 1
            self.tf.append(counts)
            for token in counts:
                self.df[token] = self.df.get(token, 0) + 1
        self.count = len(self.docs)

    def search(self, question, k):
        query = tokenize(question)
        ranked = []
        for index, counts in enumerate(self.tf):
            length = len(self.docs[index]) or 1
            score = 0.0
            for token in query:
                frequency = counts.get(token)
                if not frequency:
                    continue
                idf = math.log(1 + (self.count - self.df[token] + 0.5) / (self.df[token] + 0.5))
                numerator = frequency * (self.k1 + 1)
                denominator = frequency + self.k1 * (1 - self.b + self.b * length / self.avgdl)
                score += idf * numerator / denominator
            if score > 0:
                ranked.append((score, index))
        ranked.sort(key=lambda item: (-item[0], item[1]))
        hits = []
        for score, index in ranked[:k]:
            chunk = self.chunks[index]
            hits.append({
                "source": chunk["source"],
                "score": round(float(score), 6),
                "text": chunk["text"],
            })
        return hits


def answer_from_hits(hits):
    useful = [hit for hit in hits if hit["score"] >= MIN_SCORE]
    if not useful:
        return {
            "answer": f"{STATUS_LINE} {MISSING_LINE}",
            "sources": [],
        }
    excerpts = "\n\n".join(hit["text"].strip() for hit in useful)
    return {
        "answer": f"{STATUS_LINE}\n\n{EXCERPT_LEAD}\n\n{excerpts}",
        "sources": useful,
    }


def build_index(corpus_dir=CORPUS_DIR):
    documents = load_documents(corpus_dir)
    return Bm25(documents_to_chunks(documents)), len(documents)


def question_is_covered(index, question, hits):
    """True when the manuals actually contain the question's content words.

    A word that never occurs cannot be quoted. If those missing words
    outnumber the words that do occur, the excerpts would not answer
    the question, so they are not returned.
    """
    content = []
    seen = set()
    for token in tokenize(question):
        if len(token) < 4 or token in seen:
            continue
        seen.add(token)
        content.append(token)
    if not content or not hits:
        return False
    missing = [token for token in content if index.df.get(token, 0) == 0]
    present = [token for token in content if index.df.get(token, 0) > 0]
    if not present or len(missing) > len(present):
        return False
    top = fold(hits[0]["text"])
    return any(token in top for token in present)


def answer_question(index, question, k=5):
    text = str(question or "").strip()
    if not text:
        raise ValueError("empty_question")
    hits = index.search(text, k)
    if not question_is_covered(index, text, hits):
        hits = []
    return answer_from_hits(hits)


class ExtractHandler(BaseHTTPRequestHandler):
    index = None
    document_count = 0
    chunk_count = 0

    def log_message(self, fmt, *args):
        return

    def _send(self, status, payload):
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        origin = self.headers.get("Origin", "")
        if ORIGIN_RE.fullmatch(origin):
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
            "mode": "extract",
            "llm": None,
            "documents": self.document_count,
            "vectors": self.chunk_count,
        })

    def do_POST(self):
        path = self.path.split("?", 1)[0]
        if path != "/ask":
            self._send(404, {"status": "not_found"})
            return
        length = int(self.headers.get("Content-Length") or 0)
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
        try:
            k = int(payload.get("k", 5))
        except (TypeError, ValueError):
            self._send(400, {"error": "invalid_k"})
            return
        if k < 1 or k > 8:
            self._send(400, {"error": "invalid_k"})
            return
        self._send(200, answer_question(self.index, question, k))


def make_server(host=HOST, port=PORT, corpus_dir=CORPUS_DIR):
    index, document_count = build_index(corpus_dir)
    ExtractHandler.index = index
    ExtractHandler.document_count = document_count
    ExtractHandler.chunk_count = index.count
    return ThreadingHTTPServer((host, port), ExtractHandler)


def main():
    server = make_server()
    host, port = server.server_address
    print(
        f"extraits locaux sur http://{host}:{port} "
        f"({ExtractHandler.chunk_count} morceaux, sans Qwen)",
        flush=True,
    )
    server.serve_forever()


if __name__ == "__main__":
    main()
