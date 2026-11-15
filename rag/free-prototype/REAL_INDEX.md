# Index FAISS réel : lecture seule, comparaison non exécutée

15 novembre 2026, heure de Tunis. Le notebook n’a pas été modifié. Les embeddings n’ont pas été recalculés. Cloudflare, Groq et Workers AI n’ont pas été appelés. Le dashboard, Supabase et le backend n’ont pas changé. Rien n’a été poussé.

## Fichiers que le notebook écrit

Le notebook `rag/RDDRAG.ipynb` n’est pas sur cette branche. Il est sur `origin/feature/tariqmap-ui-and-functionality`. Il enregistre, sans les embarquer dans le fichier :

| Fichier | Rôle |
| --- | --- |
| `/content/road_damage_rag/vector_db/index.faiss` | `IndexFlatIP`, produit scalaire |
| `/content/road_damage_rag/vector_db/chunks.pkl` | liste de `{text, source}` |
| `/content/road_damage_rag/vector_db/config.json` | modèle, taille de chunk, dimension, k |

`chunks.pkl` est produit par `pickle.dump(chunks)`. Chaque élément a `text` et `source`. L’embedding est `BAAI/bge-m3`, `normalize_embeddings=True`, dimension 1024. Le découpage est 800 caractères avec un recouvrement de 100.

## Deux exécutions différentes

| Exécution | Commit du notebook | Vecteurs | Dimension | `index.faiss` | `chunks.pkl` |
| --- | --- | --- | --- | --- | --- |
| Corpus décrit dans `rag/README.md` | `09e38d98` | 479 | 1024 | 1,87 Mo | 0,39 Mo |
| Dernière exécution enregistrée | `7edfe2f1` | 431 | 1024 | 1,68 Mo | 0,34 Mo |

La seconde exécution a démarré sans les six fichiers `*_contenu_organise.txt`. Colab a alors reçu six fichiers aux noms différents, pour environ 306 ko de texte au total. Le nombre 479 du README correspond à la première exécution, pas à la dernière.

Les dix questions de référence sont celles du notebook. Leurs classements imprimés, noms de fichiers et scores seulement, sont dans `fixtures/colab-reference-questions.json`. Ce sont les scores du corpus de 479 chunks. Cinq des six noms du README apparaissent dans ces top 5. `ArticleOuargla_contenu_organise.txt` n’y figure pas. Le notebook n’imprime pas le nombre de chunks par fichier.

Sur le corpus de 431 chunks, les mêmes questions changent de fichiers en tête et de scores. Ce n’est pas le même index.

## Comparaison JavaScript

`index.faiss` et `chunks.pkl` ne sont ni dans Git, ni dans le notebook, ni sur cette machine. L’export réel n’a donc rien écrit. Les vecteurs et les textes des manuels ne sont pas entrés dans Git.

Le comparer est prêt :

```bash
python3 scripts/compare_real_index.py \
  --index /chemin/index.faiss \
  --chunks /chemin/chunks.pkl \
  --work-dir export/real
```

Il lit les deux fichiers, reconstruit les vecteurs déjà stockés, et classe chaque vecteur avec FAISS puis avec `src/search.mjs`. Il ne rappelle pas le modèle d’embeddings. `export/real/` et `local-index/` sont ignorés par Git.

Une répétition sur un index temporaire de 48 vecteurs de dimension 1024 donne 0 identifiant différent, un écart de score maximal de 1,5e-7, et 48 recherches sur 48 qui retrouvent leur propre vecteur en premier. Ce n’est pas l’index TariqMap.

## Ce qui manque pour le rapport des 479 vecteurs

Il faut une copie locale des deux fichiers de l’exécution à 479 vecteurs, celle dont l’index pèse 1,87 Mo. Dès qu’elle est placée hors de Git, la commande ci-dessus peut produire les dimensions, les normes, les effectifs par fichier, les écarts d’identifiants et les écarts de scores. L’intégration au tableau de bord attend toujours une validation séparée.
