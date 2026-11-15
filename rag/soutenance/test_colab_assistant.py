import contextlib
import io
import json
import os
import tempfile
import unittest
from pathlib import Path

import faiss
import numpy as np

from colab_assistant import (
    DEMO_QUESTIONS,
    DIMENSION,
    EMBEDDING_MODEL,
    EXPECTED_DOCS,
    LLM_MODEL,
    ORIGIN_REFLECT_RE,
    ask_body_accepts_question,
    build_prompt,
    chunk_text,
    clean_api_answer,
    create_app,
    format_dashboard_url,
    http_json,
    index_is_reusable,
    main,
    missing_documents,
    prepare,
    signals_missing_information,
    try_upload_documents,
)


class AssistantPreparationTest(unittest.TestCase):
    def test_demo_questions_cover_the_five_required_themes(self):
        ids = [item["id"] for item in DEMO_QUESTIONS]
        self.assertEqual(ids, ["types", "detection", "repair", "causes", "absent"])
        self.assertEqual(len(EXPECTED_DOCS), 6)

    def test_missing_documents_and_chunking(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            self.assertEqual(missing_documents(root), list(EXPECTED_DOCS))
            (root / EXPECTED_DOCS[0]).write_text("bonjour", encoding="utf-8")
            missing = missing_documents(root)
            self.assertNotIn(EXPECTED_DOCS[0], missing)
            self.assertEqual(len(missing), 5)
        pieces = chunk_text("a" * 1500)
        self.assertGreater(len(pieces), 1)
        self.assertLessEqual(len(pieces[0]), 800)

    def test_reusable_index_must_match_the_six_sources(self):
        count = 6
        matrix = np.eye(count, DIMENSION, dtype="float32")
        index = faiss.IndexFlatIP(DIMENSION)
        index.add(matrix)
        chunks = [{"text": f"texte {name}", "source": name} for name in EXPECTED_DOCS]
        config = {
            "embedding_model": EMBEDDING_MODEL,
            "llm_model": LLM_MODEL,
            "embedding_dimension": DIMENSION,
            "num_chunks": count,
        }
        self.assertTrue(index_is_reusable(index, chunks, config))
        wrong = dict(config, num_chunks=431)
        self.assertFalse(index_is_reusable(index, chunks, wrong))
        other = [dict(chunks[0], source="autre.txt"), *chunks[1:]]
        self.assertFalse(index_is_reusable(index, other, config))

    def test_check_does_not_build_an_index_without_gpu_or_documents(self):
        with tempfile.TemporaryDirectory() as folder:
            code = prepare(folder, check_only=True)
            self.assertEqual(code, 2)
            self.assertFalse((Path(folder) / "vector_db" / "index.faiss").exists())

    def test_saved_answer_shape_and_absence_marker(self):
        payload = clean_api_answer(
            "  ",
            [{"source": "a.txt", "score": 0.5, "text": "extrait"}],
        )
        self.assertIn("n'a pas été trouvée", payload["answer"])
        self.assertEqual(payload["sources"][0]["source"], "a.txt")
        self.assertTrue(signals_missing_information(payload["answer"]))
        self.assertFalse(signals_missing_information("Le prix est de 400 dinars."))

    def test_jupyter_kernel_argument_does_not_stop_the_parser(self):
        output = io.StringIO()
        with tempfile.TemporaryDirectory() as folder:
            with self.assertRaises(SystemExit) as caught:
                with contextlib.redirect_stdout(output):
                    main(["--check", "--root", folder, "-f", "kernel-132a3d9b.json"])
        self.assertEqual(caught.exception.code, 2)
        self.assertIn('"gpu"', output.getvalue())

    def test_notebook_contains_the_same_preparation_script(self):
        notebook = Path(__file__).with_name("assistant_colab.ipynb")
        script = Path(__file__).with_name("colab_assistant.py").read_text(encoding="utf-8")
        payload = json.loads(notebook.read_text(encoding="utf-8"))
        sources = [
            "".join(cell.get("source", []))
            for cell in payload["cells"]
            if cell.get("cell_type") == "code"
        ]
        self.assertIn(script, sources)
        self.assertIn("from pyngrok import ngrok", script)
        self.assertIn("ngrok.connect", script)
        self.assertIn("NGROK_AUTHTOKEN", script)
        self.assertIn("userdata", script)
        self.assertNotIn("cloudflared", script)
        self.assertNotIn("trycloudflare", script)
        self.assertNotIn("localtunnel", script)
        self.assertNotIn("NGROK_AUTH_TOKEN", script)
        self.assertNotRegex(script, r"set_auth_token\(\s*[\"']")
        self.assertIn("URL_DASHBOARD=", script)
        self.assertIn('globals()["QuestionRequest"] = QuestionRequest', script)
        self.assertLess(script.index("start_api(app)"), script.index("open_public_tunnel()"))

    def test_ask_accepts_question_body_and_keeps_document_only_answers(self):
        seen = {}

        def retrieve(query, k=5):
            seen["query"] = query
            seen["k"] = k
            return [{
                "text": "Les fissures longitudinales suivent l'axe de la chaussée.",
                "source": "manuel.txt",
                "score": 0.91,
            }]

        def generate(question, context):
            seen["context"] = context
            if "prix" in question:
                return "L'information n'a pas été trouvée dans les manuels."
            return "Les dégradations comprennent les fissures."

        prompt = build_prompt("question", "contexte")
        self.assertIn("uniquement à partir du contexte fourni", prompt)
        self.assertIn("n'a pas été trouvée", prompt)

        from fastapi.testclient import TestClient

        app = create_app(retrieve, generate, 431)
        client = TestClient(app)
        for item in DEMO_QUESTIONS:
            response = client.post("/ask", json={"question": item["question"], "k": 5})
            self.assertEqual(response.status_code, 200, response.text)
            body = response.json()
            self.assertTrue(body["answer"])
            self.assertEqual(body["sources"][0]["source"], "manuel.txt")
            self.assertIn("fissures longitudinales", body["sources"][0]["text"])
            if item["id"] == "absent":
                self.assertTrue(signals_missing_information(body["answer"]))
            else:
                self.assertFalse(signals_missing_information(body["answer"]))
        self.assertEqual(seen["k"], 5)
        self.assertIn("manuel.txt", seen["context"])

        rejected = client.post("/ask", json={"query": "ornière", "k": 5})
        self.assertEqual(rejected.status_code, 422)
        self.assertIn("question", rejected.text)
        self.assertIn("body", rejected.text)
        self.assertNotIn('"loc":["query","request"]', rejected.text.replace(" ", ""))

        spec = client.get("/openapi.json").json()
        self.assertTrue(ask_body_accepts_question(spec))
        self.assertFalse(ask_body_accepts_question({"paths": {"/ask": {"post": {}}}}))

    def test_http_error_includes_the_response_body(self):
        from http.server import BaseHTTPRequestHandler, HTTPServer
        import threading

        class Handler(BaseHTTPRequestHandler):
            def do_POST(self):
                length = int(self.headers.get("Content-Length", "0"))
                self.rfile.read(length)
                payload = (
                    b'{"detail":[{"type":"missing","loc":["body","question"],'
                    b'"msg":"Field required"}]}'
                )
                self.send_response(422)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(payload)))
                self.end_headers()
                self.wfile.write(payload)

            def log_message(self, fmt, *args):
                return

        server = HTTPServer(("127.0.0.1", 0), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        import colab_assistant as module

        previous = (module.API_HOST, module.API_PORT)
        module.API_HOST = "127.0.0.1"
        module.API_PORT = server.server_address[1]
        try:
            with self.assertRaises(RuntimeError) as caught:
                http_json("POST", "/ask", {"question": "fissure", "k": 5}, timeout=5)
        finally:
            module.API_HOST, module.API_PORT = previous
            server.shutdown()
            thread.join(timeout=5)
        message = str(caught.exception)
        self.assertIn("HTTP 422", message)
        self.assertIn("question", message)
        self.assertIn("Field required", message)

    def test_zero_missing_manuals_does_not_ask_for_an_upload(self):
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            left = try_upload_documents(Path("/tmp/tariqmap-rag-no-upload"), [])
        self.assertEqual(left, [])
        text = output.getvalue()
        self.assertIn("déjà", text)
        self.assertNotIn("Il manque 0", text)
        self.assertNotIn("Sélectionnez", text)
        source = Path(__file__).with_name("colab_assistant.py").read_text(encoding="utf-8")
        upload = source.split("def try_upload_documents", 1)[1].split("\ndef ", 1)[0]
        self.assertLess(upload.index("if not pending"), upload.index("Il manque"))

    def test_cors_reflects_the_dashboard_origin(self):
        import re

        from fastapi.testclient import TestClient

        self.assertIsNotNone(re.fullmatch(ORIGIN_REFLECT_RE, "http://127.0.0.1:4317"))
        self.assertIsNotNone(re.fullmatch(ORIGIN_REFLECT_RE, "https://random-name.trycloudflare.com"))
        app = create_app(lambda query, k=5: [], lambda question, context: "ok", 1)
        client = TestClient(app)
        for origin in (
            "http://127.0.0.1:4317",
            "http://localhost:5173",
            "https://random-name.trycloudflare.com",
        ):
            response = client.options(
                "/ask",
                headers={
                    "Origin": origin,
                    "Access-Control-Request-Method": "POST",
                    "Access-Control-Request-Headers": "content-type",
                },
            )
            self.assertEqual(response.status_code, 200, response.text)
            self.assertEqual(response.headers.get("access-control-allow-origin"), origin)
        posted = client.post(
            "/ask",
            json={"question": "fissure", "k": 5},
            headers={"Origin": "http://127.0.0.1:4317"},
        )
        self.assertEqual(posted.status_code, 200, posted.text)
        self.assertEqual(posted.headers.get("access-control-allow-origin"), "http://127.0.0.1:4317")

    def test_public_url_line_is_the_ngrok_address(self):
        self.assertEqual(
            format_dashboard_url("https://abc.ngrok-free.app"),
            "URL_DASHBOARD=https://abc.ngrok-free.app",
        )

    def test_missing_ngrok_token_prints_the_secret_step(self):
        import colab_assistant as module

        previous = os.environ.get("NGROK_AUTHTOKEN")
        os.environ.pop("NGROK_AUTHTOKEN", None)
        module.__dict__.pop("_TUNNEL", None)
        output = io.StringIO()
        try:
            with contextlib.redirect_stdout(output):
                url = module.open_public_tunnel()
        finally:
            module.__dict__.pop("_TUNNEL", None)
            if previous is None:
                os.environ.pop("NGROK_AUTHTOKEN", None)
            else:
                os.environ["NGROK_AUTHTOKEN"] = previous
        self.assertIsNone(url)
        text = output.getvalue()
        self.assertIn("NGROK_AUTHTOKEN", text)
        self.assertIn("secrets du notebook", text)
        self.assertNotIn("cloudflared", text)
        self.assertNotRegex(text, r"https://")

    def test_ngrok_token_comes_from_the_environment(self):
        import colab_assistant as module

        previous = os.environ.get("NGROK_AUTHTOKEN")
        os.environ["NGROK_AUTHTOKEN"] = "test-token-not-a-real-secret"
        try:
            self.assertEqual(module.read_ngrok_token(), "test-token-not-a-real-secret")
        finally:
            if previous is None:
                os.environ.pop("NGROK_AUTHTOKEN", None)
            else:
                os.environ["NGROK_AUTHTOKEN"] = previous


if __name__ == "__main__":
    unittest.main()
