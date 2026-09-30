# Road Damage RAG — Intelligent Road Damage Assistant

## Présentation du projet

**Road Damage RAG** est un assistant intelligent spécialisé dans les dommages et les pathologies routières. Il utilise une architecture **Retrieval-Augmented Generation (RAG)** pour fournir des réponses contextualisées à partir de documents techniques relatifs à l'identification, à la classification et à l'entretien des chaussées.

Le système combine un modèle de langage, un moteur de recherche vectorielle et une interface utilisateur interactive afin de faciliter l'accès aux connaissances techniques sur les dégradations routières.

## Objectifs

* Répondre aux questions concernant les pathologies routières.
* Rechercher des informations pertinentes dans des documents techniques.
* Générer des réponses contextualisées à l'aide d'un modèle de langage.
* Faciliter l'accès aux connaissances sur les fissures et autres dégradations des chaussées.
* Préparer l'intégration avec un système global de détection des dommages routiers et un système d'information géographique (SIG).

## Architecture du système

Le prototype repose sur les composants suivants :

| Composant             | Technologie         | Rôle                                         |
| --------------------- | ------------------- | -------------------------------------------- |
| Modèle de langage     | Qwen2.5-7B-Instruct | Génération des réponses                      |
| Modèle d'embedding    | BGE-M3              | Vectorisation des documents et des questions |
| Base vectorielle      | FAISS               | Recherche de passages pertinents             |
| Interface utilisateur | Streamlit           | Interaction avec l'utilisateur               |
| Langage               | Python              | Développement du système                     |

###  Pipeline RAG

1. **Collecte des documents** : récupération de ressources techniques sur les dommages routiers.
2. **Prétraitement** : extraction et découpage des documents en segments (*chunks*).
3. **Vectorisation** : transformation des segments en représentations vectorielles avec BGE-M3.
4. **Indexation** : stockage des vecteurs dans FAISS.
5. **Recherche sémantique** : récupération des segments les plus pertinents pour une question.
6. **Génération** : utilisation du contexte récupéré pour produire une réponse avec Qwen2.5-7B-Instruct.
7. **Affichage** : présentation de la réponse dans l'interface Streamlit.

## Technologies utilisées

* Python
* Hugging Face Transformers
* Sentence Transformers
* BGE-M3
* FAISS
* Qwen2.5-7B-Instruct
* Streamlit
* PyTorch

## Structure du projet

```text
road_damage_rag/
│
├── app.py                 # Application Streamlit
├── requirements.txt       # Dépendances Python
├── README.md              # Documentation du projet
├── .gitignore             # Fichiers exclus de Git
│
├── data/                  # Documents sources (non versionnés)
│
└── vector_db/             # Index vectoriel et données générées
                           # (non versionnés)
```

## Installation

### 1. Cloner le dépôt

```bash
git clone https://github.com/TrabelsiAmin/Road-damage-project.git
cd Road-damage-project
```

### 2. Accéder à la branche du RAG

```bash
git switch feature/road-damage-rag
```

### 3. Créer un environnement virtuel

Sous Windows :

```powershell
python -m venv .venv
.venv\Scripts\activate
```

### 4. Installer les dépendances

```bash
pip install -r requirements.txt
```

##  Exécution

Lancer l'application Streamlit :

```bash
streamlit run app.py
```

Ouvrir ensuite l'adresse locale indiquée dans le terminal, généralement :

```text
http://localhost:8501
```

**Prérequis :** les fichiers de configuration, les documents et l'index FAISS nécessaires doivent être disponibles. Si les données et l'index ne sont pas inclus dans Git, ils doivent être générés ou récupérés selon la procédure de préparation du projet.

## Exemple d'utilisation

**Question :**

> Qu'est-ce qu'une fissure longitudinale et quelles sont ses caractéristiques ?

**Fonctionnement attendu :**

* Recherche des passages pertinents dans les documents techniques.
* Récupération du contexte correspondant à la question.
* Génération d'une réponse contextualisée.
* Affichage de la réponse dans l'interface utilisateur.

Les réponses dépendent des documents indexés et du contexte retrouvé.

**Road Damage RAG — From technical documents to contextualized road-damage knowledge.**
