# Récupération de l’index de 479 vecteurs

À coller dans une cellule temporaire de Colab. Ne pas l’enregistrer dans `RDDRAG.ipynb`. Le diagnostic ne télécharge rien. La cellule suivante ne télécharge que si un index de 479 vecteurs est reconnu. Aucune des deux ne recalcule les embeddings ni n’écrit dans `vector_db`.

La première exécution s’est arrêtée sur `SystemExit: Aucun index de 479 vecteurs`. Ce message veut dire qu’aucun dossier ne remplissait toutes les conditions. Il ne télécharge pas l’index de 431 vecteurs. Colab affiche cette sortie volontaire comme une erreur rouge.

Lancez d’abord cette cellule. Elle ne télécharge rien et ne s’arrête pas par une exception.

```python
import json, os, pickle

print("Drive monte :", os.path.isdir("/content/drive"))
roots = ["/content"]
if os.path.isdir("/content/drive"):
    roots.append("/content/drive")
found = []
for root in roots:
    for dirpath, _dirnames, filenames in os.walk(root):
        if "index.faiss" in filenames:
            found.append(dirpath)
if not found:
    print("Aucun index.faiss sous", ", ".join(roots))
for folder in found:
    print("=" * 60)
    print(folder)
    for name in ("index.faiss", "chunks.pkl", "config.json"):
        path = os.path.join(folder, name)
        print(f"  {name}:", f"{os.path.getsize(path)} octets" if os.path.isfile(path) else "absent")
    index_path = os.path.join(folder, "index.faiss")
    if not os.path.isfile(index_path):
        continue
    import faiss, numpy as np
    index = faiss.read_index(index_path)
    vectors = np.vstack([index.reconstruct(i) for i in range(index.ntotal)])
    print("  type:", type(index).__name__)
    print("  vecteurs:", index.ntotal)
    print("  dimension:", index.d)
    print("  ecart max a la norme 1:", float(np.max(np.abs(np.linalg.norm(vectors, axis=1) - 1))))
    chunks_path = os.path.join(folder, "chunks.pkl")
    if os.path.isfile(chunks_path):
        with open(chunks_path, "rb") as handle:
            chunks = pickle.load(handle)
        if isinstance(chunks, dict) and "chunks" in chunks:
            chunks = chunks["chunks"]
        counts = {}
        if isinstance(chunks, list):
            for item in chunks:
                name = item.get("source") if isinstance(item, dict) else None
                counts[name] = counts.get(name, 0) + 1
        print("  enregistrements:", len(chunks))
        for name, count in sorted(counts.items(), key=lambda pair: str(pair[0])):
            print(f"    {count}  {name}")
    config_path = os.path.join(folder, "config.json")
    if os.path.isfile(config_path):
        config = json.load(open(config_path, encoding="utf-8"))
        print("  config:", config.get("num_chunks"), config.get("embedding_dimension"), config.get("embedding_model"))
print("Aucun telechargement.")
```

Le diagnostic du 15 novembre 2026, 20:18 heure de Tunis, a répondu `Drive monte : False` et `Aucun index.faiss sous /content`. À 20:20, Drive était monté et la recherche a répondu `index trouves : 0`. Rien n’a été téléchargé. Le notebook ne copie pas `vector_db` vers Drive, et aucune copie nommée `index.faiss` n’y est visible. L’index de 479 vecteurs n’est pas récupérable depuis cette session. Les embeddings ne sont pas recalculés.

Si cette cellule imprime `Aucun index.faiss` et `Drive monte : False`, la session n’a plus le dossier `/content`. Montez Drive seulement si une copie de `vector_db` y a déjà été enregistrée, puis relancez le diagnostic :

```python
from google.colab import drive
drive.mount("/content/drive")
```

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
    print("Aucun index de 479 vecteurs. Rien n'a ete telecharge.")
else:
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
