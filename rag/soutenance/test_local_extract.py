"""The local excerpts are copied from the manuals. They are not written here."""

import json
import threading
import unittest
import urllib.request
from pathlib import Path

from colab_assistant import EXPECTED_DOCS
from local_extract import (
    CORPUS_DIR,
    MISSING_LINE,
    answer_question,
    build_index,
    make_server,
)

CLASS_QUESTION = "Que désignent les classes D00, D10, D20 et D40 dans RDD2022 ?"
PRICE_QUESTION = "Quel est le prix d'une tonne d'enrobé bitumineux en dinars tunisiens ?"
ARYA_NAME = "Arya_2024_RDD2022_Geoscience_Data_Journal (2).txt"


class LocalExtractTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.index, cls.documents = build_index()
        cls.arya = (CORPUS_DIR / ARYA_NAME).read_text(encoding="utf-8")

    def test_class_codes_are_quoted_from_the_arya_manual(self):
        result = answer_question(self.index, CLASS_QUESTION, 5)
        self.assertIn(ARYA_NAME, EXPECTED_DOCS)
        self.assertTrue(result["sources"])
        quoted = []
        for source in result["sources"]:
            self.assertEqual(source["source"], ARYA_NAME)
            self.assertIn(source["text"], self.arya)
            quoted.append(source["text"].strip())
        self.assertIn("\n\n".join(quoted), result["answer"])
        self.assertIn("Longitudinal Cracks (D00)", result["answer"])
        self.assertIn("Transverse Cracks (D10)", result["answer"])
        self.assertIn("Alligator Cracks (D20)", result["answer"])
        self.assertIn("Potholes (D40)", result["answer"])
        server = Path(__file__).with_name("local_extract.py").read_text(encoding="utf-8")
        self.assertNotIn("Longitudinal Cracks (D00)", server)
        self.assertNotIn("Potholes (D40)", server)

    def test_a_price_is_not_invented(self):
        result = answer_question(self.index, PRICE_QUESTION, 5)
        self.assertIn(MISSING_LINE, result["answer"])
        self.assertEqual(result["sources"], [])
        self.assertNotRegex(result["answer"], r"\d")

    def test_http_ask_allows_the_dashboard_origin(self):
        server = make_server("127.0.0.1", 0)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            port = server.server_address[1]
            health_request = urllib.request.Request(
                f"http://127.0.0.1:{port}/health",
                headers={"Origin": "http://127.0.0.1:4317", "Accept": "application/json"},
            )
            with urllib.request.urlopen(health_request, timeout=5) as response:
                self.assertEqual(response.status, 200)
                self.assertEqual(response.headers["Access-Control-Allow-Origin"], "http://127.0.0.1:4317")
                health = json.loads(response.read().decode("utf-8"))
            self.assertEqual(health["status"], "ok")
            self.assertIsNone(health["llm"])

            body = json.dumps({"question": CLASS_QUESTION, "k": 5}).encode("utf-8")
            ask_request = urllib.request.Request(
                f"http://127.0.0.1:{port}/ask",
                data=body,
                headers={
                    "Origin": "http://127.0.0.1:4317",
                    "Content-Type": "application/json",
                    "Accept": "application/json",
                },
                method="POST",
            )
            with urllib.request.urlopen(ask_request, timeout=5) as response:
                payload = json.loads(response.read().decode("utf-8"))
            self.assertIn("Longitudinal Cracks (D00)", payload["answer"])
            self.assertIn(payload["sources"][0]["text"], self.arya)
        finally:
            server.shutdown()
            thread.join(timeout=5)


if __name__ == "__main__":
    unittest.main()
