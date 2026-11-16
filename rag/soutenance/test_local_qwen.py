"""The local assistant answers with generate(), not with pasted excerpts."""

import json
import threading
import unittest
import urllib.request
from pathlib import Path

from local_extract import build_index
from local_qwen import (
    DASHBOARD_ORIGIN,
    LLM_MODEL,
    PORT,
    answer_with_generate,
    make_server,
    order_hits,
)

CLASS_QUESTION = "Que désignent les classes D00, D10, D20 et D40 dans RDD2022 ?"
PRICE_QUESTION = "Quel est le prix d'une tonne d'enrobé bitumineux en dinars tunisiens ?"


class LocalQwenTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.index, _documents = build_index()

    def test_class_codes_are_ranked_into_the_prompt_context(self):
        hits = order_hits(CLASS_QUESTION, self.index.search(CLASS_QUESTION, 5))
        top = hits[0]["text"]
        self.assertIn("(D00)", top)
        self.assertIn("(D10)", top)
        self.assertIn("(D20)", top)
        self.assertIn("(D40)", top)
        self.assertIn("Longitudinal", top)
        self.assertIn("Pothole", top)

    def test_answer_text_is_whatever_generate_returns(self):
        def generate_answer(question, context):
            self.assertEqual(question, CLASS_QUESTION)
            self.assertIn("Longitudinal Cracks (D00)", context)
            self.assertIn("Transverse Cracks (D10)", context)
            self.assertIn("Alligator Cracks (D20)", context)
            self.assertIn("Potholes (D40)", context)
            return "RÉPONSE_ÉCRITE_PAR_GENERATE"

        result = answer_with_generate(self.index, CLASS_QUESTION, generate_answer, 5)
        self.assertEqual(result["answer"], "RÉPONSE_ÉCRITE_PAR_GENERATE")
        self.assertNotIn("Aucun modèle ne rédige", result["answer"])
        self.assertTrue(result["sources"])
        self.assertLessEqual(len(result["sources"]), 2)
        self.assertNotIn(result["sources"][0]["text"], result["answer"])

    def test_a_generated_absence_is_not_replaced_by_an_excerpt(self):
        def generate_answer(question, context):
            self.assertEqual(question, PRICE_QUESTION)
            return "L'information n'a pas été trouvée dans le contexte."

        result = answer_with_generate(self.index, PRICE_QUESTION, generate_answer, 5)
        self.assertEqual(
            result["answer"],
            "L'information n'a pas été trouvée dans le contexte.",
        )
        self.assertNotRegex(result["answer"], r"\d")
        self.assertNotIn("Extraits des manuels", result["answer"])

    def test_http_names_the_small_model_and_allows_the_dashboard(self):
        def generate_answer(question, context):
            return f"généré:{question[:12]}"

        server = make_server(generate_answer, "127.0.0.1", 0)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            port = server.server_address[1]
            self.assertNotEqual(port, 4721)
            health_request = urllib.request.Request(
                f"http://127.0.0.1:{port}/health",
                headers={"Origin": DASHBOARD_ORIGIN, "Accept": "application/json"},
            )
            with urllib.request.urlopen(health_request, timeout=5) as response:
                self.assertEqual(response.status, 200)
                self.assertEqual(
                    response.headers["Access-Control-Allow-Origin"],
                    DASHBOARD_ORIGIN,
                )
                health = json.loads(response.read().decode("utf-8"))
            self.assertEqual(health["status"], "ok")
            self.assertEqual(health["llm"], LLM_MODEL)
            self.assertNotIn("7B", health["llm"])
            self.assertFalse(health["gpu"])

            body = json.dumps({"question": CLASS_QUESTION, "k": 5}).encode("utf-8")
            ask_request = urllib.request.Request(
                f"http://127.0.0.1:{port}/ask",
                data=body,
                headers={
                    "Origin": DASHBOARD_ORIGIN,
                    "Content-Type": "application/json",
                    "Accept": "application/json",
                },
                method="POST",
            )
            with urllib.request.urlopen(ask_request, timeout=5) as response:
                self.assertEqual(
                    response.headers["Access-Control-Allow-Origin"],
                    DASHBOARD_ORIGIN,
                )
                payload = json.loads(response.read().decode("utf-8"))
            self.assertTrue(payload["answer"].startswith("généré:"))
        finally:
            server.shutdown()

    def test_server_source_calls_generate_and_does_not_claim_7b(self):
        source = Path(__file__).with_name("local_qwen.py").read_text(encoding="utf-8")
        self.assertIn('LLM_MODEL = "Qwen/Qwen2.5-1.5B-Instruct"', source)
        self.assertIn("model.generate", source)
        self.assertIn("make_generate", source)
        self.assertNotIn('LLM_MODEL = "Qwen/Qwen2.5-7B-Instruct"', source)
        self.assertNotIn("4721", source)
        self.assertIn(str(PORT), source)
        self.assertIn(DASHBOARD_ORIGIN, source)
