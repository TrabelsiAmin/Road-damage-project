import contextlib
import io
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

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
    cloudflare_command,
    create_app,
    format_dashboard_url,
    http_json,
    index_is_reusable,
    main,
    missing_documents,
    parse_trycloudflare_url,
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
        self.assertIn("cloudflared tunnel --url http://127.0.0.1:8000", script)
        self.assertIn("trycloudflare.com", script)
        self.assertIn("ensure_cloudflared", script)
        self.assertNotIn("localtunnel", script)
        self.assertNotIn("secrets du notebook", script)
        self.assertNotIn("NGROK_AUTH_TOKEN", script)
        self.assertNotRegex(script, r"set_auth_token\(\s*[\"']")
        self.assertIn("URL_DASHBOARD=", script)
        self.assertIn('globals()["QuestionRequest"] = QuestionRequest', script)
        self.assertIn("Qwen n'est pas rechargé.", script)
        prepare_body = script.split("def prepare", 1)[1].split("\ndef ", 1)[0]
        self.assertLess(prepare_body.index("finish_public_session()"), prepare_body.index("start_api(app)"))
        self.assertLess(prepare_body.index("start_api(app)"), prepare_body.rindex("finish_public_session()"))
        self.assertLess(prepare_body.index("Qwen n'est pas rechargé"), prepare_body.index("load_llm("))

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
        preflight = client.options(
            "/ask",
            headers={
                "Origin": "http://127.0.0.1:4317",
                "Access-Control-Request-Method": "POST",
                "Access-Control-Request-Headers": "content-type,ngrok-skip-browser-warning,bypass-tunnel-reminder",
            },
        )
        self.assertEqual(preflight.status_code, 200, preflight.text)
        allowed_headers = preflight.headers.get("access-control-allow-headers", "").lower()
        self.assertIn("content-type", allowed_headers)
        self.assertIn("ngrok-skip-browser-warning", allowed_headers)
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

    def test_missing_ngrok_token_opens_a_cloudflare_tunnel(self):
        import colab_assistant as module

        previous = os.environ.get("NGROK_AUTHTOKEN")
        os.environ.pop("NGROK_AUTHTOKEN", None)
        module.__dict__.pop("_TUNNEL", None)
        output = io.StringIO()

        def fake_cloudflare():
            return "https://demo-session.trycloudflare.com", None

        def fake_ngrok(token):
            raise AssertionError(token)

        try:
            with patch.object(module, "start_cloudflare_tunnel", fake_cloudflare), \
                 patch.object(module, "start_ngrok_tunnel", fake_ngrok), \
                 contextlib.redirect_stdout(output):
                url = module.open_public_tunnel()
        finally:
            module.__dict__.pop("_TUNNEL", None)
            if previous is None:
                os.environ.pop("NGROK_AUTHTOKEN", None)
            else:
                os.environ["NGROK_AUTHTOKEN"] = previous
        self.assertEqual(url, "https://demo-session.trycloudflare.com")
        text = output.getvalue()
        self.assertIn("NGROK_AUTHTOKEN absent", text)
        self.assertIn("sans jeton", text)
        self.assertIn("URL_DASHBOARD=https://demo-session.trycloudflare.com", text)
        self.assertNotIn("secrets du notebook", text)

    def test_ngrok_token_skips_cloudflare(self):
        import colab_assistant as module

        previous = os.environ.get("NGROK_AUTHTOKEN")
        os.environ["NGROK_AUTHTOKEN"] = "test-token-not-a-real-secret"
        module.__dict__.pop("_TUNNEL", None)
        seen = {}

        def fake_ngrok(token):
            seen["token"] = token
            return "https://abc.ngrok-free.app"

        def fake_cloudflare():
            raise AssertionError("cloudflare")

        output = io.StringIO()
        try:
            with patch.object(module, "start_ngrok_tunnel", fake_ngrok), \
                 patch.object(module, "start_cloudflare_tunnel", fake_cloudflare), \
                 contextlib.redirect_stdout(output):
                url = module.open_public_tunnel()
        finally:
            module.__dict__.pop("_TUNNEL", None)
            if previous is None:
                os.environ.pop("NGROK_AUTHTOKEN", None)
            else:
                os.environ["NGROK_AUTHTOKEN"] = previous
        self.assertEqual(seen["token"], "test-token-not-a-real-secret")
        self.assertEqual(url, "https://abc.ngrok-free.app")
        self.assertIn("URL_DASHBOARD=https://abc.ngrok-free.app", output.getvalue())

    def test_failed_ngrok_falls_back_to_cloudflare(self):
        import colab_assistant as module

        previous = os.environ.get("NGROK_AUTHTOKEN")
        os.environ["NGROK_AUTHTOKEN"] = "test-token-not-a-real-secret"
        module.__dict__.pop("_TUNNEL", None)
        output = io.StringIO()
        try:
            with patch.object(module, "start_ngrok_tunnel", lambda token: None), \
                 patch.object(
                     module,
                     "start_cloudflare_tunnel",
                     lambda: ("https://fallback.trycloudflare.com", None),
                 ), \
                 contextlib.redirect_stdout(output):
                url = module.open_public_tunnel()
        finally:
            module.__dict__.pop("_TUNNEL", None)
            if previous is None:
                os.environ.pop("NGROK_AUTHTOKEN", None)
            else:
                os.environ["NGROK_AUTHTOKEN"] = previous
        self.assertEqual(url, "https://fallback.trycloudflare.com")
        self.assertIn("Ouverture d'un tunnel Cloudflare", output.getvalue())

    def test_cloudflare_command_targets_the_local_api(self):
        command = cloudflare_command("/tmp/cloudflared")
        self.assertEqual(command[:2], ["/tmp/cloudflared", "tunnel"])
        self.assertIn("--url", command)
        self.assertEqual(command[command.index("--url") + 1], "http://127.0.0.1:8000")
        self.assertIn("http2", command)
        boxed = "INF |  https://random-name.trycloudflare.com  |"
        self.assertEqual(parse_trycloudflare_url(boxed), "https://random-name.trycloudflare.com")
        self.assertIsNone(parse_trycloudflare_url("pas d'adresse"))

    def test_cloudflared_already_on_path_is_reused(self):
        import colab_assistant as module

        with patch.object(module.shutil, "which", return_value="/usr/bin/cloudflared"):
            self.assertEqual(module.ensure_cloudflared(), "/usr/bin/cloudflared")

    def test_cloudflare_output_yields_the_public_url(self):
        import colab_assistant as module

        process = subprocess.Popen(
            [
                sys.executable,
                "-c",
                "print('boot', flush=True); print('https://demo-session.trycloudflare.com', flush=True); import time; time.sleep(2)",
            ],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1,
        )
        try:
            origin, _tail = module.wait_for_cloudflare_url(process, timeout=5)
        finally:
            process.kill()
            process.wait(timeout=5)
        self.assertEqual(origin, "https://demo-session.trycloudflare.com")

    def test_cloudflare_output_without_url_returns_none(self):
        import colab_assistant as module

        process = subprocess.Popen(
            [sys.executable, "-c", "print('echec du tunnel', flush=True)"],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1,
        )
        origin, tail = module.wait_for_cloudflare_url(process, timeout=5)
        process.wait(timeout=5)
        if process.stdout is not None:
            process.stdout.close()
        self.assertIsNone(origin)
        self.assertTrue(any("echec" in line for line in tail))

    def test_existing_api_opens_the_tunnel_without_reloading_qwen(self):
        import colab_assistant as module

        def fake_http(method, path, payload=None, timeout=180):
            if path == "/openapi.json":
                return {
                    "paths": {
                        "/ask": {
                            "post": {
                                "requestBody": {
                                    "content": {
                                        "application/json": {
                                            "schema": {"$ref": "#/components/schemas/QuestionRequest"}
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            if path == "/health":
                return {"status": "ok", "vectors": 431}
            if path == "/ask":
                question = (payload or {}).get("question", "")
                answer = (
                    "L'information n'a pas été trouvée dans les manuels."
                    if "prix" in question
                    else "Les dégradations comprennent les fissures."
                )
                return {
                    "answer": answer,
                    "sources": [{"source": "manuel.txt", "score": 0.9, "text": "extrait"}],
                }
            raise AssertionError(path)

        with tempfile.TemporaryDirectory() as folder:
            with patch.object(module, "port_open", return_value=True), \
                 patch.object(module, "http_json", side_effect=fake_http), \
                 patch.object(module, "open_public_tunnel", return_value="https://demo.trycloudflare.com") as tunnel, \
                 patch.object(module, "load_llm", side_effect=AssertionError("Qwen")), \
                 patch.object(module, "load_embedding", side_effect=AssertionError("BGE")):
                output = io.StringIO()
                with contextlib.redirect_stdout(output):
                    code = module.prepare(folder)
        self.assertEqual(code, 0)
        tunnel.assert_called_once()
        text = output.getvalue()
        self.assertIn("Qwen n'est pas rechargé", text)
        self.assertIn("URL_DASHBOARD=https://demo.trycloudflare.com", text)
        self.assertIn("API locale : http://127.0.0.1:8000", text)
        for item in DEMO_QUESTIONS:
            self.assertIn(item["id"], text)

    def test_old_api_on_port_8000_does_not_reload_qwen(self):
        import colab_assistant as module

        def fake_http(method, path, payload=None, timeout=180):
            if path == "/openapi.json":
                return {"paths": {"/ask": {"post": {}}}}
            raise AssertionError(path)

        with tempfile.TemporaryDirectory() as folder:
            with patch.object(module, "port_open", return_value=True), \
                 patch.object(module, "http_json", side_effect=fake_http), \
                 patch.object(module, "load_llm", side_effect=AssertionError("Qwen")), \
                 patch.object(module, "open_public_tunnel", side_effect=AssertionError("tunnel")):
                with self.assertRaises(RuntimeError) as caught:
                    module.prepare(folder)
        self.assertIn("ancienne API", str(caught.exception))
        self.assertIn("{question, k}", str(caught.exception))

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
