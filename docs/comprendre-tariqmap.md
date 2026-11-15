# Comprendre TariqMap

Ce texte décrit le projet tel qu’il fonctionne aujourd’hui, pour la personne qui le défend. Les chiffres ci-dessous viennent du catalogue et du code. Ce ne sont pas des objectifs.

## Ce que c’est

TariqMap enregistre des observations de dégradations de chaussée en Tunisie.

Trois écrans servent à les regarder ou à les commenter :

- le tableau de bord d’une autorité, une fois le compte connecté ;
- la vue d’un visiteur, sans compte, qui ne voit pas les dossiers un par un ;
- un assistant qui répond à partir de six manuels techniques de pathologie routière.

L’application mobile, dans le dépôt, sert à capturer des observations. Le tableau de bord, lui, lit ce qui est déjà dans la base. L’assistant ne tourne pas dans le navigateur : il tourne dans Google Colab, et le tableau de bord l’appelle seulement si une adresse publique a été enregistrée.

## Ouvrir le tableau de bord

Le dossier est `/tmp/Road-damage-project/dashboard`. C’est une application Vite.

Le fichier `vite.config.js` prévoit le port 5173. Pour la démonstration, le serveur est ouvert sur le port 4317 :

```bash
cd /tmp/Road-damage-project/dashboard
npm run dev -- --host 127.0.0.1 --port 4317
```

Puis ouvrir [http://127.0.0.1:4317/](http://127.0.0.1:4317/).

## L’écran d’accueil

La barre latérale est bleu marine. Le reste de la page claire est blanc, avec des accents bleus.

L’accueil montre, dans cet ordre :

1. quatre cartes ;
2. la carte de la Tunisie ;
3. un anneau des classes ;
4. des barres par gouvernorat ;
5. l’assistant ;
6. les derniers incidents.

Les quatre cartes sont :

- **Total des incidents**
- **Routes concernées**
- **Zones concernées**
- **Dernier incident recensé**

Les routes et les gouvernorats ne sont pas des champs enregistrés. Ils sont déduits du point le plus proche. L’écran le dit.

L’anneau s’intitule « Répartition par classe ». Les barres s’intitulent « Incidents par gouvernorat ».

## Thème clair et mode sombre

Le thème clair est le fond blanc et bleu décrit plus haut. Un bouton de la barre du haut passe en mode sombre, ou revient au clair.

Le choix est gardé dans le navigateur, sous la clé `tariqmap_theme`, avec la valeur `light` ou `dark`. S’il n’y a pas encore de choix, le thème suit celui du système.

## Les chiffres à ne pas mélanger

**128** n’est pas un total de la base. C’était un chiffre de maquette. L’accueil ne doit pas l’afficher.

Le catalogue visible sans compte contient **67** observations : **31** réelles et **36** de démonstration.

Parmi les lignes réelles non rejetées, **21** ont des coordonnées utilisables. Elles sont dessinées en **15** mailles d’environ 1 km. Le point affiché est le centre de la maille, pas la position mesurée. Le visiteur ne voit pas les dossiers un par un : le tableau des derniers incidents dit que les lignes individuelles restent réservées aux comptes autorisés.

Les fonctions `public_damage_summary` et `public_map_cells` répondent **HTTP 404**. Le total public officiel n’existe donc pas. La légende de la carte du visiteur le dit en toutes lettres : elle compte les signalements réels du catalogue visible, hors démonstration et hors rejets, puis ajoute que le total public officiel est indisponible (HTTP 404). Avec le catalogue actuel, cette phrase parle de 21 signalements et de 15 mailles.

Ce que montrent les quatre cartes, dans le code actuel :

- **Visiteur.** Le total officiel ayant échoué, la première carte reprend le total du catalogue visible, donc 21, avec la phrase : « Signalements réels non rejetés du catalogue visible. Le total public officiel reste indisponible. » Les cartes des routes et des zones sont déduites de ces mailles. La quatrième carte reste **Indisponible**, avec le sous-texte « Dossier individuel non visible », parce que la date d’un dossier ne doit pas être montrée au visiteur.
- **Compte connecté, chargement réussi.** L’écran charge les lignes non démo, environ 31 sur 67. La case « Inclure enregistrements démo » est décochée par défaut. La première carte compte les signalements non rejetés de ce filtre. Le 21 du catalogue ne sert de plancher que si aucun filtre ni aucune recherche n’est actif, et seulement s’il est plus grand que ce total. Avec ces lignes réelles, il ne l’est pas : la carte affiche le total du compte, pas 21. Un filtre ou une recherche peut montrer une part plus petite. Les derniers incidents de ce compte sont listés.
- **Compte connecté, chargement des lignes échoué.** Si les mailles du catalogue sont déjà là, les cartes reprennent ce total connu, et le tableau dit que la liste détaillée n’est pas chargée.

Quatre cas réels critiques du 20 janvier 2026 n’ont pas de coordonnées. Ils ne peuvent pas être placés sur la carte. S’ils ne sont pas rejetés, ils restent dans le décompte du compte connecté.

La carte du compte connecté utilise les agrégats du serveur, à environ 20 m, pour les observations qui ont un point. La légende HTTP 404 est celle du visiteur.

## Ce que l’écran refuse d’inventer

Les classes restent les codes **D00**, **D10**, **D20** et **D40**. L’écran ne les remplace pas par un nom français de dégradation.

Le coût de réparation affiche **Indisponible**. Aucun barème n’est dans le dépôt.

Le délai moyen n’est pas calculé à partir de dates de réparation. Là où ce délai est affiché, le texte est **Non calculé**.

## Retenir une observation

L’assistant a besoin d’une observation retenue avant « Demander une recommandation ».

- Visiteur : cliquer une maille sur la carte. L’infobulle propose « Retenir cette observation ». C’est un agrégat, pas un dossier.
- Compte connecté : cliquer une ligne des derniers incidents, ou un agrégat sur la carte.

Ensuite, cliquer **Demander une recommandation**.

Sans adresse publique enregistrée, ce bouton n’appelle pas le modèle. Le message affiché est « l'API ne répond pas ». Il faut d’abord remplir le champ **Adresse de l'API Colab** et cliquer **Enregistrer**.

La question envoyée ne contient que la classe, la priorité et le statut connus. Elle n’envoie ni photo, ni coordonnées précises, ni identifiant.

## L’assistant

Il répond seulement à partir des six manuels indexés. S’il ne trouve pas l’information dans ces textes, il doit le dire. Il n’invente pas un prix, un délai ou un lieu.

Le modèle de réponse est **Qwen2.5-7B-Instruct**, chargé en 4 bits. Les passages sont cherchés avec **BAAI/bge-m3**. L’index est un **FAISS IndexFlatIP** : 431 vecteurs, dimension 1024. Le découpage est de 800 caractères, avec un recouvrement de 100.

La question « Quel est le prix d'une tonne d'enrobé bitumineux en dinars tunisiens ? » sert à montrer un refus. Ce prix n’est pas dans les manuels. Une réponse qui donnerait un montant serait une erreur.

Chaque question posée dans le tableau de bord part vers le modèle en marche. Une réponse enregistrée à l’avance n’est pas une réponse de remplacement. Si l’adresse ne répond pas, l’écran dit « l'API ne répond pas ».

## Relier le tableau de bord à Colab

L’API Colab n’écoute que `127.0.0.1:8000`, et seulement à l’intérieur de la machine Colab. Le tableau de bord tourne dans le navigateur, sur l’ordinateur qui affiche `http://127.0.0.1:4317`. Pour ce navigateur, `127.0.0.1` est son propre ordinateur, pas Colab. Un appel direct au port 8000 ne peut donc pas atteindre le modèle.

La cellule à lancer est celle de `rag/soutenance/assistant_colab.ipynb`, sur la branche `cursor/rag-free-local-prototype-4fb6`, à partir du commit `f0cf924`.

Après le démarrage, la cellule ouvre un tunnel HTTPS et imprime une ligne `URL_DASHBOARD=https://…`.

- Si le secret Colab `NGROK_AUTHTOKEN` est présent, ou la variable d’environnement du même nom, le tunnel est ngrok.
- Sinon, `cloudflared` ouvre un tunnel Cloudflare et imprime `URL_DASHBOARD=https://….trycloudflare.com`. Aucun jeton n’est nécessaire pour cette voie.

Copier cette ligne dans **Adresse de l'API Colab**, cliquer **Enregistrer**, puis écrire une question. L’adresse est gardée dans le navigateur sous la clé `tariqmap_rag_url`.

Si le port 8000 répond déjà avec le bon format, la cellule ne recharge pas Qwen : elle ouvre seulement le tunnel.

## Les six manuels

La cellule cherche ces six noms de fichiers, et seulement ceux-là :

- `Arya_2024_RDD2022_Geoscience_Data_Journal (2).txt`
- `Benjelloun_Cours_Routes_EPA_Agadir_Chapitres_1-2 (2).txt`
- `Cours_Pathologies_et_entretien_des_routes_et_ouvrages_dart_4geniecivil (2).txt`
- `FHWA_HRT-13-092_Distress_Identification_Manual_LTPP (2).txt`
- `MTQ_Manuel_identification_degradations_chaussees_flexibles_PROJET (2).txt`
- `Pathologie_des_routes_clean (3).txt`

Ils ne sont pas dans le dépôt Git. Ils sont sur la session Colab, avec l’index de 431 vecteurs.

Les noms qui finissent par `_contenu_organise.txt` appartiennent à une autre description, celle d’un index de 479 vecteurs. Ce n’est pas l’index utilisé ici.

## Ce qu’il ne faut pas faire

- N’ouvrez un tunnel public que pour donner au tableau de bord l’adresse à coller. Ne diffusez pas cette adresse au-delà de la démonstration.
- Ne faites pas une réinitialisation d’usine de Colab. Elle efface les six manuels et l’index.
- Ne téléchargez pas un index de 479 vecteurs. Il n’a jamais été sur le disque. L’index à réutiliser est celui de 431 vecteurs, déjà construit à partir des six fichiers ci-dessus.
