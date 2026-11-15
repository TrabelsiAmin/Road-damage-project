# Soutenance — assistant dans Colab

Le fichier à ouvrir est `assistant_colab.ipynb`. Il contient le même code que `colab_assistant.py`.

Il charge Qwen2.5-7B-Instruct en 4 bits, BGE-M3 et FAISS. L'API n'écoute que `127.0.0.1`. Ensuite la cellule ouvre un tunnel HTTPS et imprime `URL_DASHBOARD=https://…`.

Si le secret Colab `NGROK_AUTHTOKEN` (ou la variable d'environnement du même nom) est présent, le tunnel est ngrok. S'il manque, la cellule installe `cloudflared` au besoin et ouvre un tunnel Cloudflare (`https://….trycloudflare.com`) vers `http://127.0.0.1:8000`. Aucun jeton n'est écrit dans le fichier, et aucun jeton n'est requis pour le tunnel Cloudflare. Si l'API répond déjà sur le port 8000, Qwen n'est pas rechargé.

L'index de 479 vecteurs n'est pas récupérable. Les six manuels ne sont pas dans le dépôt. Sans ces fichiers, et sans GPU, le script s'arrête avant tout calcul d'embeddings. S'ils sont déjà tous là, la cellule ne redemande pas de les envoyer.

Dans le tableau de bord, collez la ligne `URL_DASHBOARD` dans le champ « Adresse de l'API Colab », cliquez Enregistrer, puis posez une question. L'adresse est gardée dans le navigateur (`tariqmap_rag_url`). Le tableau de bord affiche la réponse du modèle, ou « l'API ne répond pas ». Il ne substitue pas une réponse enregistrée.
