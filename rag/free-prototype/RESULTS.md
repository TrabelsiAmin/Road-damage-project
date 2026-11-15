# Résultats du prototype local

Mesures du 15 novembre 2026, sur cette machine. Aucun déploiement Cloudflare. Aucun appel Groq. Aucun appel Workers AI. Le dashboard, l’URL ngrok, le notebook, Supabase, `backend/` et Flutter n’ont pas été modifiés.

## Ce qui a été exécuté

| Contrôle | Résultat |
| --- | --- |
| Tests Node | 11 sur 11 |
| Santé `/health` | 200, et aucun appel fournisseur |
| Classement planté | Les 9 questions rattachées à un extrait retrouvent ce fichier en premier, score 1 |
| Question hors corpus | La réponse dit que les extraits ne contiennent pas l’information. Les sources renvoyées sont celles de l’index, pas un fichier inventé |
| Dimension fausse | HTTP 422 `dimension_mismatch` |
| Vecteurs non normés | La requête est renormalisée avant le produit scalaire. L’index doit déjà être unitaire |
| Quota embedding | HTTP 429 Cloudflare : HTTP 503 `quota`, Groq n’est pas appelé |
| Quota Groq | Un 429 sur `qwen/qwen3.8-27b` provoque un seul essai sur `llama-3.1-8b-instant`. Deux 429 donnent HTTP 503 `quota` |
| Clés | Absentes de la réponse JSON |
| Recherche 479 × 1024 | 2,233 ms |
| Export d’un fichier manquant | Arrêt sans écrire de JSON |
| Parité FAISS | Index temporaire 48 × 1024, normes à 6e-8 de 1. Trois requêtes, 0 identifiant différent, écart de score maximal 2,9e-8 |
| Sonde live | Ignorée : aucune variable Cloudflare ou Groq dans l’environnement |

## Comparaison avec le RAG Colab

La comparaison des réponses et du classement sur le vrai corpus n’a pas pu être faite. `index.faiss`, `chunks.pkl` et les six textes ne sont pas dans le dépôt, et le notebook n’y est pas non plus. L’export est prêt à les lire le jour où une copie locale est fournie. Il ne les modifie pas.

Ce qui est comparable aujourd’hui : le produit scalaire JavaScript reproduit `IndexFlatIP` sur des vecteurs déjà normalisés. Le modèle de rédaction prévu est `qwen/qwen3.8-27b`, pas Qwen2.5-7B-Instruct. L’embedding prévu est `@cf/baai/bge-m3`. Sans appel réel, on ne sait pas encore si ce checkpoint renormalise comme SentenceTransformers. Le prototype renormalise la requête si sa norme s’écarte de 1 de plus de 0,001.

## Quotas estimés, non mesurés sur un compte

Une question d’une cinquantaine de jetons vers BGE-M3 coûte de l’ordre de 0,05 neurone sur le tarif publié d’environ 1 075 neurones par million de jetons. Le plafond gratuit de 10 000 neurones par jour, remis à 00:00 UTC, couvre largement les embeddings. Il ne couvre pas en plus une génération par un gros modèle Cloudflare : ce prototype ne l’utilise pas.

Groq Free publie, pour `qwen/qwen3.8-27b`, environ 1 000 requêtes et 200 000 jetons par jour. Une réponse avec cinq extraits de 800 caractères et 300 jetons générés représente quelques milliers de jetons. Dix questions de test resteraient loin de ce plafond. Ce sont des ordres de grandeur lus dans la documentation, pas une consommation constatée : aucun compte n’a été appelé.

Le secours `llama-3.1-8b-instant` a son propre compteur, publié autour de 14 400 requêtes par jour. Il reste gratuit. Il n’est pas Qwen.

## Limites

- Pas de preuve que Workers AI et Groq répondent depuis ce réseau, ni de leur latence réelle. Le délai de 90 secondes du tableau de bord n’a donc pas été mesuré de bout en bout.
- Pas de score de qualité sur les 479 chunks du corpus.
- Le service gratuit peut répondre 429. Le prototype le transforme en 503 après un seul secours. Il ne réessaie pas en boucle.
- Rien de ceci n’est disponible depuis le tableau de bord. L’intégration attend une validation séparée.
