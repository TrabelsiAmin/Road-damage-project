# Prototype local, non déployé

Ce dossier n’est pas branché au tableau de bord et n’appelle rien tout seul.

```bash
cd rag/free-prototype
npm test
python3 scripts/parity_check.py
node scripts/live-check.mjs
```

`npm test` vérifie le classement, les sources, les dimensions, le 429 et le secours, sans réseau.

`parity_check.py` construit un index FAISS temporaire, l’exporte, et compare le classement JavaScript. Il n’ouvre pas le corpus Colab.

`live-check.mjs` s’arrête sans appel si `CLOUDFLARE_ACCOUNT_ID`, `CLOUDFLARE_API_TOKEN` ou `GROQ_API_KEY` manque. Ces valeurs restent dans l’environnement, jamais dans Git.

Pour exporter plus tard une copie locale de l’index Colab, sans modifier les fichiers sources :

```bash
python3 scripts/export_faiss.py \
  --index /chemin/index.faiss \
  --chunks /chemin/chunks.pkl \
  --out export/index.json
```

Les résultats mesurés ici sont dans `RESULTS.md`.
