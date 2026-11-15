"""Assistant RAG de soutenance, exécuté dans le notebook Colab.

Qwen2.5-7B-Instruct en 4 bits, BGE-M3, FAISS IndexFlatIP.
L'API écoute seulement 127.0.0.1. Le tableau de bord colle la ligne
URL_DASHBOARD=https://…
Si NGROK_AUTHTOKEN est défini (environnement ou secret Colab), le tunnel
est ngrok. Sinon cloudflared ouvre un tunnel Cloudflare rapide vers
http://127.0.0.1:8000, sans jeton. Les embeddings ne sont recalculés que
si aucun index valide n'est déjà là. Si l'API répond déjà sur le port 8000,
Qwen n'est pas rechargé : seul le tunnel est ouvert.
"""

from __future__ import annotations

import argparse
import json
import os
import pickle
import platform
import re
import shutil
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.request
from pathlib import Path

EMBEDDING_MODEL = "BAAI/bge-m3"
LLM_MODEL = "Qwen/Qwen2.5-7B-Instruct"
CHUNK_SIZE = 800
CHUNK_OVERLAP = 100
DIMENSION = 1024
API_HOST = "127.0.0.1"
API_PORT = 8000
TRYCLOUDFLARE_RE = re.compile(r"https://[A-Za-z0-9-]+\.trycloudflare\.com")
CLOUDFLARED_RELEASE = "https://github.com/cloudflare/cloudflared/releases/latest/download"

# Noms réels du corpus, présents sur origin/feature/road-damage-rag.
EXPECTED_DOCS = (
    "Arya_2024_RDD2022_Geoscience_Data_Journal (2).txt",
    "Benjelloun_Cours_Routes_EPA_Agadir_Chapitres_1-2 (2).txt",
    "Cours_Pathologies_et_entretien_des_routes_et_ouvrages_dart_4geniecivil (2).txt",
    "FHWA_HRT-13-092_Distress_Identification_Manual_LTPP (2).txt",
    "MTQ_Manuel_identification_degradations_chaussees_flexibles_PROJET (2).txt",
    "Pathologie_des_routes_clean (3).txt",
)

DEMO_QUESTIONS = (
    {
        "id": "types",
        "question": "Quels sont les principaux types de dégradations des chaussées ?",
    },
    {
        "id": "detection",
        "question": "Comment identifier une dégradation de la chaussée à partir de son aspect visuel ?",
    },
    {
        "id": "repair",
        "question": "Quels principes de réparation s'appliquent à une fissure de chaussée ?",
    },
    {
        "id": "causes",
        "question": "Quelles sont les principales causes des fissures de chaussée ?",
    },
    {
        "id": "absent",
        "question": "Quel est le prix d'une tonne d'enrobé bitumineux en dinars tunisiens ?",
    },
)

ABSENCE_MARKERS = (
    "pas été trouvée",
    "n'a pas été trouvée",
    "ne figure pas",
    "pas dans le contexte",
    "aucune information",
    "n'est pas présente",
    "ne contient pas",
)


def chunk_text(text, chunk_size=CHUNK_SIZE, overlap=CHUNK_OVERLAP):
    chunks = []
    start = 0
    step = chunk_size - overlap
    if step <= 0:
        raise ValueError("overlap must be smaller than chunk size")
    while start < len(text):
        piece = text[start:start + chunk_size]
        if piece.strip():
            chunks.append(piece)
        start += step
    return chunks


def missing_documents(data_dir):
    folder = Path(data_dir)
    present = set()
    if folder.is_dir():
        present = {path.name for path in folder.glob("*.txt")}
    return [name for name in EXPECTED_DOCS if name not in present]


def load_documents(data_dir):
    documents = []
    for name in EXPECTED_DOCS:
        path = Path(data_dir) / name
        text = path.read_text(encoding="utf-8")
        if text.strip():
            documents.append({"text": text, "source": name})
    return documents


def documents_to_chunks(documents):
    chunks = []
    for document in documents:
        for piece in chunk_text(document["text"]):
            chunks.append({"text": piece, "source": document["source"]})
    return chunks


def index_is_reusable(index, chunks, config):
    if index is None or not chunks or not isinstance(config, dict):
        return False
    if type(index).__name__ != "IndexFlatIP":
        return False
    if int(index.ntotal) != len(chunks) or int(index.d) != DIMENSION:
        return False
    if config.get("embedding_model") != EMBEDDING_MODEL:
        return False
    if config.get("embedding_dimension") != DIMENSION:
        return False
    if config.get("num_chunks") != len(chunks):
        return False
    if config.get("llm_model") not in (None, LLM_MODEL):
        return False
    sources = {item.get("source") for item in chunks}
    if sources != set(EXPECTED_DOCS):
        return False
    import numpy as np

    vectors = np.vstack([index.reconstruct(i) for i in range(index.ntotal)])
    error = float(np.max(np.abs(np.linalg.norm(vectors, axis=1) - 1.0)))
    return error <= 1e-3


def build_prompt(question, context):
    return f"""
Tu es un assistant spécialisé dans les dommages et pathologies routières.

Réponds à la question uniquement à partir du contexte fourni.

Règles :
- Utilise uniquement les informations présentes dans le contexte.
- N'invente aucune information.
- Si l'information n'est pas présente dans le contexte,
  indique clairement que l'information n'a pas été trouvée.
- Donne une réponse claire, précise et concise.
- Ne mentionne pas les sources dans ta réponse.
- Ne mentionne pas "SOURCE 1", "SOURCE 2", etc.
- Les sources seront affichées séparément par l'application.

Contexte :
{context}

Question :
{question}

Réponse :
"""


def build_context(results):
    blocks = []
    for index, result in enumerate(results, start=1):
        blocks.append(
            f"SOURCE {index}: {result['source']}\n\n{result['text']}\n\n------------------------------"
        )
    return "\n".join(blocks)


def clean_api_answer(answer, sources):
    text = (answer or "").strip() or "L'information n'a pas été trouvée dans les manuels."
    cleaned = []
    for source in sources or []:
        name = str(source.get("source") or "").strip()
        excerpt = source.get("text")
        score = source.get("score")
        if not name or not isinstance(excerpt, str) or not isinstance(score, (int, float)):
            continue
        cleaned.append({"source": name, "score": float(score), "text": excerpt})
    return {"answer": text, "sources": cleaned}


def signals_missing_information(answer):
    folded = (answer or "").lower()
    return any(marker in folded for marker in ABSENCE_MARKERS)


def environment_report():
    report = {"gpu": False, "gpuName": None, "freeBytes": None, "totalBytes": None}
    try:
        import torch
    except Exception:
        return report
    report["gpu"] = bool(torch.cuda.is_available())
    if report["gpu"]:
        free, total = torch.cuda.mem_get_info()
        report["freeBytes"] = int(free)
        report["totalBytes"] = int(total)
        report["gpuName"] = torch.cuda.get_device_name(0)
    return report


def default_root():
    if Path("/content").is_dir():
        return Path("/content/road_damage_rag")
    return Path(__file__).resolve().parent / "local"


def read_saved_index(vector_dir):
    index_path = Path(vector_dir) / "index.faiss"
    chunks_path = Path(vector_dir) / "chunks.pkl"
    config_path = Path(vector_dir) / "config.json"
    if not index_path.is_file() or not chunks_path.is_file() or not config_path.is_file():
        return None, None, None
    import faiss

    index = faiss.read_index(str(index_path))
    with chunks_path.open("rb") as handle:
        chunks = pickle.load(handle)
    config = json.loads(config_path.read_text(encoding="utf-8"))
    return index, chunks, config


def save_index(vector_dir, index, chunks, config):
    folder = Path(vector_dir)
    folder.mkdir(parents=True, exist_ok=True)
    import faiss

    faiss.write_index(index, str(folder / "index.faiss"))
    with (folder / "chunks.pkl").open("wb") as handle:
        pickle.dump(chunks, handle)
    (folder / "config.json").write_text(
        json.dumps(config, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )


def try_upload_documents(data_dir, missing):
    pending = [name for name in (missing or []) if str(name).strip()]
    if not pending:
        print("Les six manuels sont déjà là. Aucun fichier à renvoyer.")
        return []
    try:
        from google.colab import files
    except Exception:
        print("Hors de Colab : placez les six manuels dans", data_dir)
        return pending
    print("Il manque", len(pending), "manuel(s). Sélectionnez les fichiers .txt.")
    uploaded = files.upload()
    folder = Path(data_dir)
    folder.mkdir(parents=True, exist_ok=True)
    for name, content in uploaded.items():
        if not str(name).lower().endswith(".txt"):
            print("Ignoré :", name)
            continue
        target = folder / Path(name).name
        target.write_bytes(content)
        print("Enregistré :", target.name, len(content), "octets")
    return missing_documents(data_dir)


def ensure_packages():
    required = {
        "transformers": "transformers",
        "accelerate": "accelerate",
        "bitsandbytes": "bitsandbytes",
        "sentence_transformers": "sentence-transformers",
        "faiss": "faiss-cpu",
        "fastapi": "fastapi",
        "uvicorn": "uvicorn",
        "numpy": "numpy",
        "pyngrok": "pyngrok",
    }
    missing = []
    for module, package in required.items():
        try:
            __import__(module)
        except Exception:
            missing.append(package)
    if not missing:
        print("Dépendances déjà présentes.")
        return
    import subprocess

    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", *missing])


def load_embedding(existing):
    if existing is not None:
        print("BGE-M3 déjà chargé.")
        return existing
    from sentence_transformers import SentenceTransformer

    model = SentenceTransformer(EMBEDDING_MODEL, device="cpu")
    print("BGE-M3 chargé.")
    return model


def load_llm(existing):
    if existing is not None:
        print("Qwen déjà chargé. Pas de second chargement.")
        return existing
    import torch
    from transformers import AutoModelForCausalLM, AutoTokenizer, BitsAndBytesConfig

    quant = BitsAndBytesConfig(
        load_in_4bit=True,
        bnb_4bit_compute_dtype=torch.float16,
        bnb_4bit_quant_type="nf4",
        bnb_4bit_use_double_quant=True,
    )
    tokenizer = AutoTokenizer.from_pretrained(LLM_MODEL)
    model = AutoModelForCausalLM.from_pretrained(
        LLM_MODEL,
        quantization_config=quant,
        device_map="auto",
    )
    print("Qwen2.5-7B-Instruct chargé en 4 bits.")
    return tokenizer, model


def build_index(embedding_model, chunks):
    import faiss
    import numpy as np

    texts = [item["text"] for item in chunks]
    vectors = embedding_model.encode(texts, normalize_embeddings=True, show_progress_bar=True)
    vectors = np.asarray(vectors, dtype="float32")
    index = faiss.IndexFlatIP(int(vectors.shape[1]))
    index.add(vectors)
    return index


def make_retrieve(embedding_model, index, chunks):
    def retrieve(query, k=5):
        import numpy as np

        if index.ntotal == 0:
            return []
        try:
            limit = int(k)
        except (TypeError, ValueError):
            limit = 5
        limit = min(8, max(1, limit), int(index.ntotal))
        query_vector = np.asarray(
            embedding_model.encode([query], normalize_embeddings=True),
            dtype="float32",
        )
        scores, indices = index.search(query_vector, limit)
        results = []
        for score, idx in zip(scores[0], indices[0]):
            position = int(idx)
            if position < 0 or position >= len(chunks):
                continue
            text = chunks[position].get("text")
            source = str(chunks[position].get("source") or "").strip()
            if not source or not isinstance(text, str):
                continue
            results.append({"text": text, "source": source, "score": float(score)})
        return results

    return retrieve


def make_generate(tokenizer, llm):
    # La démo du notebook et une question du tableau de bord partagent le GPU.
    lock = threading.Lock()

    def generate_answer(question, context):
        import torch

        messages = [
            {"role": "system", "content": "Tu es un assistant spécialisé dans les dommages routiers."},
            {"role": "user", "content": build_prompt(question, context)},
        ]
        rendered = tokenizer.apply_chat_template(messages, tokenize=False, add_generation_prompt=True)
        with lock:
            inputs = tokenizer([rendered], return_tensors="pt").to(llm.device)
            with torch.no_grad():
                outputs = llm.generate(**inputs, max_new_tokens=300, do_sample=False)
            return tokenizer.decode(outputs[0][inputs["input_ids"].shape[1]:], skip_special_tokens=True)

    return generate_answer


# Le tableau de bord tourne souvent sur http://127.0.0.1:4317, parfois sur
# un autre port local, parfois sur une page HTTPS. On renvoie l'Origin reçu.
DASHBOARD_ORIGINS = (
    "http://127.0.0.1:4317",
    "http://localhost:4317",
    "http://127.0.0.1:5173",
    "http://localhost:5173",
)
ORIGIN_REFLECT_RE = r"https?://[^/\s]+"


def create_app(retrieve, generate_answer, vector_count):
    from fastapi import FastAPI
    from fastapi.middleware.cors import CORSMiddleware
    from pydantic import BaseModel, Field

    app = FastAPI(title="TariqMap RAG soutenance", version="soutenance")
    app.add_middleware(
        CORSMiddleware,
        allow_origins=list(DASHBOARD_ORIGINS),
        allow_origin_regex=ORIGIN_REFLECT_RE,
        allow_methods=["GET", "POST", "OPTIONS"],
        allow_headers=["*"],
    )

    class QuestionRequest(BaseModel):
        question: str = Field(min_length=1, max_length=2000)
        k: int = Field(default=5, ge=1, le=8)

    # `from __future__ import annotations` laisse le nom QuestionRequest
    # en texte. FastAPI le cherche dans le module, pas dans cette fonction.
    # Sans cette affectation, le JSON {question, k} est ignoré et l'API
    # répond 422 : paramètre d'URL `request` manquant.
    globals()["QuestionRequest"] = QuestionRequest

    @app.get("/health")
    def health():
        report = environment_report()
        return {
            "status": "ok",
            "llm": LLM_MODEL,
            "embeddings": EMBEDDING_MODEL,
            "vectors": vector_count,
            "dimension": DIMENSION,
            "gpu": report["gpu"],
        }

    @app.get("/")
    def root():
        return health()

    @app.post("/ask")
    def ask(request: QuestionRequest):
        results = retrieve(request.question.strip(), k=request.k)
        answer = generate_answer(request.question.strip(), build_context(results))
        return clean_api_answer(answer, results)

    return app


def port_open(port=API_PORT):
    import socket

    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.settimeout(0.4)
        return sock.connect_ex((API_HOST, port)) == 0


def question_body_status():
    """'ok' si /ask attend le JSON, 'old' si le schéma est l'ancien, 'unknown' sinon."""
    try:
        spec = http_json("GET", "/openapi.json", timeout=5)
    except Exception:
        return "unknown"
    if ask_body_accepts_question(spec):
        return "ok"
    return "old"


OLD_API_ERROR = (
    "Le port 8000 sert encore l'ancienne API : elle attend un paramètre "
    "d'URL nommé request et refuse le JSON {question, k}. "
    "Redémarrez l'environnement d'exécution, puis relancez cette cellule."
)


def ask_body_accepts_question(spec):
    post = (spec.get("paths") or {}).get("/ask", {}).get("post") or {}
    schema = (
        ((post.get("requestBody") or {}).get("content") or {})
        .get("application/json", {})
        .get("schema")
        or {}
    )
    if str(schema.get("$ref") or "").endswith("/QuestionRequest"):
        return True
    return "question" in (schema.get("properties") or {})


def start_api(app):
    if port_open():
        status = question_body_status()
        if status == "old":
            raise RuntimeError(OLD_API_ERROR)
        print("Une API répond déjà sur", API_HOST, API_PORT, flush=True)
        return
    import uvicorn

    thread = threading.Thread(
        target=uvicorn.run,
        kwargs={"app": app, "host": API_HOST, "port": API_PORT, "log_level": "warning"},
        daemon=True,
    )
    thread.start()
    for _ in range(40):
        if port_open():
            return
        time.sleep(0.25)
    raise RuntimeError("L'API locale n'a pas démarré.")


def http_json(method, path, payload=None, timeout=180):
    data = None if payload is None else json.dumps(payload).encode("utf-8")
    request = urllib.request.Request(
        f"http://{API_HOST}:{API_PORT}{path}",
        data=data,
        method=method,
        headers={"Content-Type": "application/json", "Accept": "application/json"},
    )
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as error:
        detail = error.read().decode("utf-8", errors="replace")
        raise RuntimeError(
            f"HTTP {error.code} sur {method} {path} : {detail}"
        ) from error


def print_demo_result(item, payload):
    print("=" * 80)
    print(item["id"])
    print(item["question"])
    print(payload.get("answer", ""))
    for rank, source in enumerate(payload.get("sources") or [], start=1):
        print(f"{rank}. {source.get('source')}  score={float(source.get('score', 0)):.4f}")
    if item["id"] == "absent" and not signals_missing_information(payload.get("answer")):
        print("ALERTE : la question hors corpus n'indique pas que l'information manque.")


def run_demo():
    health = http_json("GET", "/health", timeout=10)
    print("SANTE", json.dumps(health, ensure_ascii=False))
    if health.get("status") != "ok":
        raise RuntimeError("La sonde /health n'est pas ok. Les questions ne sont pas lancées.")
    for item in DEMO_QUESTIONS:
        payload = http_json("POST", "/ask", {"question": item["question"], "k": 5})
        print_demo_result(item, payload)


def format_dashboard_url(url):
    return f"URL_DASHBOARD={url}"


def read_ngrok_token():
    """Jeton ngrok : variable NGROK_AUTHTOKEN, sinon secret Colab du même nom."""
    token = os.environ.get("NGROK_AUTHTOKEN", "").strip()
    if token:
        return token
    try:
        from google.colab import userdata
    except Exception:
        return ""
    try:
        return str(userdata.get("NGROK_AUTHTOKEN") or "").strip()
    except Exception:
        return ""


def _https_origin(tunnel):
    origin = getattr(tunnel, "public_url", str(tunnel)).strip().rstrip("/")
    if origin.startswith("http://"):
        origin = "https://" + origin[len("http://"):]
    return origin


def _connect_ngrok(ngrok):
    # pyngrok 6 : bind_tls=True. pyngrok 7 ouvre déjà un tunnel HTTPS.
    try:
        return ngrok.connect(API_PORT, bind_tls=True)
    except TypeError:
        return ngrok.connect(str(API_PORT))
    except Exception as exc:
        if "bind_tls" not in str(exc).lower():
            raise
        return ngrok.connect(str(API_PORT))


def tunnel_state():
    state = globals().get("_TUNNEL")
    if not isinstance(state, dict):
        state = {"url": None, "process": None}
        globals()["_TUNNEL"] = state
    return state


def cached_public_url(state):
    url = state.get("url")
    if not url:
        return None
    process = state.get("process")
    if process is not None and process.poll() is not None:
        state["url"] = None
        state["process"] = None
        return None
    return url


def remember_public_url(origin, process=None):
    state = tunnel_state()
    state["url"] = origin
    state["process"] = process
    print("Copiez cette ligne dans le tableau de bord, champ « Adresse de l'API Colab ».", flush=True)
    print(format_dashboard_url(origin), flush=True)
    return origin


def start_ngrok_tunnel(token):
    """Tunnel ngrok HTTPS. Retourne l'origine https, ou None si ngrok échoue."""
    try:
        from pyngrok import ngrok
    except Exception:
        subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "pyngrok"])
        from pyngrok import ngrok

    try:
        ngrok.set_auth_token(token)
        for tunnel in list(ngrok.get_tunnels()):
            origin = _https_origin(tunnel)
            if origin.startswith("https://"):
                return origin
        origin = _https_origin(_connect_ngrok(ngrok))
    except Exception as exc:
        detail = str(exc).replace(token, "…")
        print("ngrok n'a pas démarré :", detail, flush=True)
        return None
    if not origin.startswith("https://"):
        print("ngrok n'a pas renvoyé d'adresse HTTPS.", flush=True)
        return None
    return origin


def cloudflared_asset_name():
    machine = platform.machine().lower()
    if machine in ("x86_64", "amd64"):
        return "cloudflared-linux-amd64"
    if machine in ("aarch64", "arm64"):
        return "cloudflared-linux-arm64"
    if machine in ("armv7l", "armv6l"):
        return "cloudflared-linux-arm"
    raise RuntimeError(f"Architecture non prise en charge pour cloudflared : {machine}")


def cloudflare_command(binary):
    # cloudflared tunnel --url http://127.0.0.1:8000
    # http2 : le réseau Colab bloque souvent QUIC.
    return [
        binary,
        "tunnel",
        "--no-autoupdate",
        "--protocol",
        "http2",
        "--url",
        f"http://{API_HOST}:{API_PORT}",
    ]


def ensure_cloudflared():
    found = shutil.which("cloudflared")
    if found:
        return found
    dest = Path(os.environ.get("TMPDIR") or "/tmp") / "cloudflared"
    if dest.is_file() and os.access(dest, os.X_OK) and dest.stat().st_size > 1_000_000:
        return str(dest)
    name = cloudflared_asset_name()
    url = f"{CLOUDFLARED_RELEASE}/{name}"
    print("Installation de cloudflared…", flush=True)
    partial = dest.with_name(dest.name + ".partial")
    request = urllib.request.Request(url, headers={"User-Agent": "tariqmap-colab"})
    with urllib.request.urlopen(request, timeout=120) as response, partial.open("wb") as handle:
        while True:
            chunk = response.read(256 * 1024)
            if not chunk:
                break
            handle.write(chunk)
    partial.chmod(0o755)
    partial.replace(dest)
    return str(dest)


def parse_trycloudflare_url(text):
    match = TRYCLOUDFLARE_RE.search(text or "")
    return match.group(0) if match else None


def wait_for_cloudflare_url(process, timeout=75):
    """Lit stdout fusionné avec stderr jusqu'à l'URL trycloudflare, ou None."""
    found = {}
    tail = []

    def consume():
        stream = process.stdout
        if stream is None:
            return
        try:
            for line in iter(stream.readline, ""):
                tail.append(line.rstrip())
                del tail[:-20]
                if "url" not in found:
                    origin = parse_trycloudflare_url(line)
                    if origin:
                        found["url"] = origin
        except Exception:
            return

    thread = threading.Thread(target=consume, daemon=True)
    thread.start()
    deadline = time.time() + timeout
    while time.time() < deadline and "url" not in found:
        if process.poll() is not None:
            break
        time.sleep(0.25)
    thread.join(timeout=1)
    return found.get("url"), tail


def start_cloudflare_tunnel():
    """cloudflared tunnel --url http://127.0.0.1:8000. Aucun jeton."""
    binary = ensure_cloudflared()
    command = cloudflare_command(binary)
    print("Tunnel Cloudflare :", " ".join(command), flush=True)
    process = subprocess.Popen(
        command,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
    )
    origin, tail = wait_for_cloudflare_url(process)
    if not origin:
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                process.kill()
        detail = " | ".join(tail[-8:])
        print("cloudflared n'a pas renvoyé d'adresse trycloudflare.com.", detail, flush=True)
        return None, None
    return origin, process


def open_public_tunnel():
    """Ouvre ngrok si le jeton est là, sinon un tunnel Cloudflare. L'API reste locale."""
    state = tunnel_state()
    cached = cached_public_url(state)
    if cached:
        print(format_dashboard_url(cached), flush=True)
        return cached

    token = read_ngrok_token()
    if token:
        origin = start_ngrok_tunnel(token)
        if origin:
            return remember_public_url(origin)
        print("ngrok n'a pas démarré. Ouverture d'un tunnel Cloudflare.", flush=True)
    else:
        print(
            "NGROK_AUTHTOKEN absent. Ouverture d'un tunnel Cloudflare, sans jeton.",
            flush=True,
        )

    origin, process = start_cloudflare_tunnel()
    if not origin:
        return None
    return remember_public_url(origin, process)


def finish_public_session():
    public_url = open_public_tunnel()
    try:
        run_demo()
    finally:
        print("API locale :", f"http://{API_HOST}:{API_PORT}", flush=True)
        if public_url:
            print("Copiez cette ligne dans le tableau de bord, champ « Adresse de l'API Colab ».", flush=True)
            print(format_dashboard_url(public_url), flush=True)
        else:
            print("Pas de ligne URL_DASHBOARD : le tunnel public n'a pas démarré.", flush=True)
    return 0


def prepare(root, check_only=False, embedding_model=None, llm_pair=None):
    root = Path(root)
    data_dir = root / "data"
    vector_dir = root / "vector_db"
    data_dir.mkdir(parents=True, exist_ok=True)
    report = environment_report()
    report["missingDocuments"] = missing_documents(data_dir)
    report["root"] = str(root)
    if check_only:
        print(json.dumps(report, ensure_ascii=False))
        return 0 if report["gpu"] and not report["missingDocuments"] else 2

    # Une cellule précédente a déjà chargé Qwen. On ouvre seulement le tunnel.
    if port_open():
        if question_body_status() == "old":
            raise RuntimeError(OLD_API_ERROR)
        print("Une API répond déjà sur", API_HOST, API_PORT, flush=True)
        print("Qwen n'est pas rechargé.", flush=True)
        return finish_public_session()

    if not report["gpu"]:
        print(json.dumps(report, ensure_ascii=False))
        print("Pas de GPU. Qwen 4 bits n'est pas chargé. Aucun embedding n'est recalculé.")
        return 2
    free = report.get("freeBytes") or 0
    if free < 5 * 1024 ** 3:
        print("Mémoire GPU libre insuffisante :", free, "octets.")
        return 2

    ensure_packages()
    missing = try_upload_documents(data_dir, report["missingDocuments"])
    if missing:
        print("Manuels absents :", ", ".join(missing))
        print("L'index n'est pas reconstruit.")
        return 2

    documents = load_documents(data_dir)
    fresh_chunks = documents_to_chunks(documents)
    saved_index, saved_chunks, saved_config = read_saved_index(vector_dir)
    if saved_chunks == fresh_chunks and index_is_reusable(saved_index, saved_chunks, saved_config):
        index, chunks = saved_index, saved_chunks
        print("Index réutilisé :", index.ntotal, "vecteurs, dimension", index.d)
        rebuilt = False
    else:
        embedding_model = load_embedding(embedding_model)
        chunks = fresh_chunks
        print("Construction de l'index :", len(chunks), "chunks")
        index = build_index(embedding_model, chunks)
        config = {
            "embedding_model": EMBEDDING_MODEL,
            "llm_model": LLM_MODEL,
            "chunk_size": CHUNK_SIZE,
            "chunk_overlap": CHUNK_OVERLAP,
            "embedding_dimension": int(index.d),
            "num_chunks": len(chunks),
            "retrieval_k": 5,
        }
        save_index(vector_dir, index, chunks, config)
        rebuilt = True
        print("Index écrit :", index.ntotal, "vecteurs")

    counts = {}
    for item in chunks:
        counts[item["source"]] = counts.get(item["source"], 0) + 1
    print("Sources :", json.dumps(counts, ensure_ascii=False))
    if not rebuilt:
        embedding_model = load_embedding(embedding_model)
    else:
        embedding_model = embedding_model or load_embedding(None)

    tokenizer, llm = load_llm(llm_pair)
    retrieve = make_retrieve(embedding_model, index, chunks)
    generate_answer = make_generate(tokenizer, llm)
    app = create_app(retrieve, generate_answer, int(index.ntotal))
    start_api(app)
    return finish_public_session()


def running_in_notebook():
    # Colab always launches the cell with "-f <kernel.json>".
    if "-f" in sys.argv:
        return True
    try:
        from IPython import get_ipython
    except Exception:
        return False
    return get_ipython() is not None


def main(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--root", type=Path, default=None)
    # Colab launches the cell with "-f <kernel.json>". Ignore that argument.
    args, _unknown = parser.parse_known_args(argv)
    root = args.root or default_root()
    code = prepare(root, check_only=args.check)
    if code and not running_in_notebook():
        raise SystemExit(code)
    return code


if __name__ == "__main__":
    main()
