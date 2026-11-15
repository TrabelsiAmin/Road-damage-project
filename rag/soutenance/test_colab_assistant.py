import json
import pickle
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
    chunk_text,
    clean_api_answer,
    index_is_reusable,
    missing_documents,
    prepare,
    signals_missing_information,
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
        self.assertNotIn("pyngrok", script)
        self.assertNotIn("ngrok.connect", script)
        self.assertNotIn("NGROK_AUTH_TOKEN", script)


if __name__ == "__main__":
    unittest.main()
