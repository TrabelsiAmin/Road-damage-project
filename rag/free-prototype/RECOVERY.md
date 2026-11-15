# Récupération de l’index de 479 vecteurs

À coller dans une cellule temporaire de Colab. Ne pas l’enregistrer dans `RDDRAG.ipynb`. La cellule lit les fichiers et peut les télécharger. Elle ne recalcule pas les embeddings et n’écrit rien dans `vector_db`.

L’index retenu a 479 vecteurs, la dimension 1024, le type `IndexFlatIP`, des normes proches de 1, et les six noms `*_contenu_organise.txt`. L’index de 431 vecteurs, celui d’environ 1,68 Mo, est refusé et n’est pas téléchargé.

```python
import json, os, pickle

EXPECTED_CHUNKS = 479
EXPECTED_DIMENSION = 1024
EXPECTED_SOURCES = {
    "ArticleOuargla_contenu_organise.txt",
    "Cours_Pathologies_Entretien_Routes_Ouvrages_contenu_organise.txt",
    "Distress_Identification_Manual_contenu_organise.txt",
    "Manuel_identification_degradations_chaussees_flexibles_contenu_organise.txt",
    "Pathologie_des_routes_contenu_organise.txt",
    "RDD2022_contenu_organise.txt",
}

def describe(folder):
    paths = {
        name: os.path.join(folder, name)
        for name in ("index.faiss", "chunks.pkl", "config.json")
    }
    print("dossier", folder)
    for name, path in paths.items():
        print(f"  {name}", os.path.getsize(path) if os.path.isfile(path) else "absent")
    if any(not os.path.isfile(path) for path in paths.values()):
        return False
    import faiss, numpy as np
    index = faiss.read_index(paths["index.faiss"])
    with open(paths["chunks.pkl"], "rb") as handle:
        chunks = pickle.load(handle)
    config = json.load(open(paths["config.json"], encoding="utf-8"))
    vectors = np.vstack([index.reconstruct(i) for i in range(index.ntotal)])
    norm_error = float(np.max(np.abs(np.linalg.norm(vectors, axis=1) - 1)))
    sources = {item.get("source") for item in chunks}
    print("  type", type(index).__name__)
    print("  vecteurs", index.ntotal, "chunks", len(chunks), "dimension", index.d)
    print("  ecart de norme", norm_error)
    print("  config", config.get("num_chunks"), config.get("embedding_dimension"), config.get("embedding_model"))
    ok = (
        type(index).__name__ == "IndexFlatIP"
        and index.ntotal == EXPECTED_CHUNKS
        and len(chunks) == EXPECTED_CHUNKS
        and index.d == EXPECTED_DIMENSION
        and norm_error <= 1e-3
        and sources == EXPECTED_SOURCES
        and config.get("num_chunks") == EXPECTED_CHUNKS
        and config.get("embedding_dimension") == EXPECTED_DIMENSION
        and config.get("embedding_model") == "BAAI/bge-m3"
    )
    print("  retenu" if ok else "  refuse")
    return ok

candidates = []
canonical = "/content/road_damage_rag/vector_db"
if os.path.isdir(canonical):
    candidates.append(canonical)
roots = ["/content"]
if os.path.isdir("/content/drive"):
    roots.append("/content/drive")
seen = {os.path.abspath(canonical)}
for root in roots:
    for dirpath, _dirnames, filenames in os.walk(root):
        if "index.faiss" not in filenames:
            continue
        folder = os.path.abspath(dirpath)
        if folder not in seen:
            seen.add(folder)
            candidates.append(folder)

kept = next((folder for folder in candidates if describe(folder)), None)
if not kept:
    raise SystemExit("Aucun index de 479 vecteurs. Ne telechargez pas celui de 431.")

from google.colab import files
for name in ("index.faiss", "chunks.pkl", "config.json"):
    files.download(os.path.join(kept, name))
```

Si `/content/road_damage_rag/vector_db` n’existe plus, la session Colab a été recyclée. Monter Drive dans une autre cellule temporaire, puis relancer la cellule ci-dessus :

```python
from google.colab import drive
drive.mount("/content/drive")
```

Le téléchargement passe par le navigateur. Déposer les trois fichiers, sans les renommer, dans :

`rag/free-prototype/local-index/`

Ce dossier et `rag/free-prototype/export/real/` sont ignorés par Git. Ne pas les copier ailleurs dans le dépôt.

Une fois les fichiers posés, le contrôle local, toujours sans réécriture, est :

```bash
python3 scripts/inspect_index.py \
  --index local-index/index.faiss \
  --chunks local-index/chunks.pkl \
  --config local-index/config.json
```

La comparaison FAISS / JavaScript ne part que si ce contrôle accepte l’index. Elle ne recalcule pas les embeddings. Les dix questions restent la référence déjà imprimée par Colab : leurs vecteurs de question n’ont pas été sauvegardés, donc elles ne seront pas réencodées.
