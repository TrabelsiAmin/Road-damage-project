# Road Damage RAG — Assistant IA pour les dommages et pathologies routières


Ce projet implémente un système **RAG (Retrieval-Augmented Generation)** en français, spécialisé dans les dégradations des chaussées (fissures longitudinales/transversales, faïençage, ornières, nids-de-poule, classes RDD2022, etc.). Il est conçu pour alimenter l'agent de détection de fissures routières (YOLO / RDD2022) avec une base de connaissances documentaire.

---

## 1. Architecture

```
Documents (.txt)
      │
      ▼
Découpage en chunks (800 caractères, overlap 100)
      │
      ▼
Embeddings  ── BAAI/bge-m3 (1024 dimensions, normalisés)
      │
      ▼
Index FAISS (IndexFlatIP, similarité cosinus)
      │
Question ─► Embedding ─► Recherche top-k ─► Construction du contexte
                                                    │
                                                    ▼
                                    Qwen2.5-7B-Instruct (4 bits, NF4)
                                                    │
                                                    ▼
                                      Réponse + sources (API FastAPI)
```

| Composant | Choix |
|---|---|
| Embeddings | `BAAI/bge-m3` (SentenceTransformers, exécuté sur CPU) |
| Base vectorielle | FAISS `IndexFlatIP` (produit scalaire sur vecteurs normalisés) |
| LLM | `Qwen/Qwen2.5-7B-Instruct`, quantification 4 bits via `bitsandbytes` |
| API | FastAPI + Uvicorn, exposée via ngrok |
| Environnement | Google Colab, GPU T4 (~5,2 Go de VRAM utilisés) |

---

## 2. Corpus documentaire

Six documents texte placés dans `/content/road_damage_rag/data` :

- `Manuel_identification_degradations_chaussees_flexibles_contenu_organise.txt`
- `Pathologie_des_routes_contenu_organise.txt`
- `Cours_Pathologies_Entretien_Routes_Ouvrages_contenu_organise.txt`
- `Distress_Identification_Manual_contenu_organise.txt`
- `RDD2022_contenu_organise.txt`
- `ArticleOuargla_contenu_organise.txt`

Après découpage : **479 chunks**.

---

## 3. Structure du notebook

| Étape | Contenu |
|---|---|
| 1 | Vérification de PyTorch et du GPU |
| 2 | Installation : `transformers`, `accelerate`, `bitsandbytes`, `sentence-transformers`, `faiss-cpu` |
| 3 | Chargement de BGE-M3 et test de similarité |
| 4 | Chargement de Qwen2.5-7B-Instruct en 4 bits et test de génération |
| 5 | Mini-démonstration RAG sur 3 documents + FAISS |
| 6 | Création des dossiers `data/` et `vector_db/` |
| 7 | Chargement des `.txt` et découpage en chunks |
| 8 | Embeddings des chunks et construction de l'index FAISS |
| 9 | Fonctions `retrieve`, `build_context`, `build_prompt`, `generate_answer`, `ask_rag` |
| 10 | Batterie de 10 questions de test |
| 11 | Sauvegarde de l'index, des chunks et de la configuration |
| 12 | API FastAPI + tunnel ngrok |

---

## 4. Prérequis

- Compte Google Colab avec GPU (T4 suffisant)
- Les 6 fichiers `.txt` du corpus dans `/content/road_damage_rag/data`
- (Optionnel) un token ngrok pour exposer l'API

```bash
pip install -q -U transformers accelerate bitsandbytes sentence-transformers faiss-cpu
pip install -q fastapi uvicorn pyngrok nest-asyncio
```

---

## 5. Utilisation

### 5.1 Exécution du notebook

1. Activer le GPU : *Exécution → Modifier le type d'exécution → T4 GPU*.
2. Uploader les fichiers `.txt` dans `/content/road_damage_rag/data`.
3. Exécuter les cellules dans l'ordre.

### 5.2 Interrogation directe

```python
answer, sources = ask_rag(
    "Qu'est-ce qu'une fissure longitudinale ?",
    k=5
)
print(answer)
for s in sources:
    print(s["source"], round(s["score"], 4))
```

### 5.3 API REST

| Méthode | Route | Description |
|---|---|---|
| GET | `/` | Vérification de l'état de l'API |
| POST | `/ask` | Pose une question au RAG |

Exemple de requête :

```bash
curl -X POST "https://<url-ngrok>/ask" \
  -H "Content-Type: application/json" \
  -d '{"question": "Qu'\''est-ce que le faïençage ?", "k": 5}'
```

Réponse :

```json
{
  "answer": "...",
  "sources": [
    {"source": "fichier.txt", "score": 0.69, "text": "..."}
  ]
}
```

La documentation interactive est disponible sur `/docs`.

---

## 6. Artefacts sauvegardés (`/content/road_damage_rag/vector_db`)

| Fichier | Rôle |
|---|---|
| `index.faiss` | Index vectoriel FAISS (~1,9 Mo) |
| `chunks.pkl` | Texte et source de chaque chunk |
| `config.json` | Paramètres de construction (modèles, chunking, dimension, k) |

> Colab étant éphémère, copier ce dossier sur Google Drive pour le conserver.

Pour recharger sans recalculer les embeddings :

```python
import faiss, pickle
index = faiss.read_index("/content/road_damage_rag/vector_db/index.faiss")
with open("/content/road_damage_rag/vector_db/chunks.pkl", "rb") as f:
    chunks = pickle.load(f)
```

---

## 7. Paramètres principaux

| Paramètre | Valeur |
|---|---|
| `chunk_size` | 800 caractères |
| `chunk_overlap` | 100 caractères |
| `k` (top-k) | 5 |
| `max_new_tokens` | 300 |
| Décodage | `do_sample=False` (déterministe) |
| Quantification | 4 bits NF4, double quantification, calcul en float16 |

Le prompt impose de répondre **uniquement à partir du contexte**, sans inventer, et d'indiquer explicitement quand l'information est absente.

---
