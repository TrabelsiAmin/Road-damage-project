# Soutenance — assistant dans Colab

Le fichier à ouvrir est `assistant_colab.ipynb`. Il contient le même code que `colab_assistant.py`.

Il charge Qwen2.5-7B-Instruct en 4 bits, BGE-M3 et FAISS. Il répond à cinq questions dans la sortie du notebook. Il n'utilise pas ngrok et n'écoute que `127.0.0.1`.

L'index de 479 vecteurs n'est pas récupérable. Les six manuels ne sont pas dans le dépôt. Sans ces fichiers, et sans GPU, le script s'arrête avant tout calcul d'embeddings.

Le tableau de bord reste branché par `VITE_RAG_API_URL` dans `dashboard/.env.local`, jamais dans le code. Laissez cette variable vide tant que l'API n'est pas sur le même ordinateur que Vite. Le panneau dit alors que l'assistant est indisponible.
