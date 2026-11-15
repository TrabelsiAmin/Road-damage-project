# Soutenance — assistant dans Colab

Le fichier à ouvrir est `assistant_colab.ipynb`. Il contient le même code que `colab_assistant.py`.

Il charge Qwen2.5-7B-Instruct en 4 bits, BGE-M3 et FAISS. Il répond à cinq questions dans la sortie du notebook. L'API n'écoute que `127.0.0.1`. Ensuite la cellule ouvre un tunnel HTTPS (cloudflared, sinon localtunnel, sinon ngrok) et imprime `URL_DASHBOARD=https://…`.

L'index de 479 vecteurs n'est pas récupérable. Les six manuels ne sont pas dans le dépôt. Sans ces fichiers, et sans GPU, le script s'arrête avant tout calcul d'embeddings. S'ils sont déjà tous là, la cellule ne redemande pas de les envoyer.

Dans le tableau de bord, collez cette ligne dans le champ « Adresse de l'API Colab » de la carte Assistant intelligent, puis envoyez une question. L'adresse est gardée dans le navigateur (`tariqmap_rag_url`).
