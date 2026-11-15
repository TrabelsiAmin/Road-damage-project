# Comprendre TariqMap

Ce texte décrit le projet tel qu’il est dans le code, pour la personne qui le défend. Les chiffres viennent du catalogue et du code. Ce ne sont pas des objectifs, et ce ne sont pas des chiffres de maquette.

TariqMap a trois parties. Le téléphone crée une observation. Le tableau de bord la montre. L’assistant explique la pathologie à partir de manuels, sans lire la photo.

## Ce que TariqMap est

TariqMap sert à constater des dégradations de chaussée en Tunisie, à les garder même sans réseau, puis à les revoir depuis un poste d’autorité.

Le téléphone est une application Flutter, dans le dossier `app/`. Il prend une photo ou une vidéo, fait tourner un modèle sur l’appareil, et enregistre l’observation d’abord dans le téléphone. Quand la personne lance la synchronisation, l’application écrit dans Supabase.

Le tableau de bord est une application React, dans le dossier `dashboard/`. Il lit ce qui est déjà dans la base. Il a deux regards : le visiteur, sans compte, et le compte connecté.

L’assistant ne tourne pas dans le navigateur et ne tourne pas dans le téléphone. Il tourne dans un notebook Google Colab. Le tableau de bord ne l’appelle que si une adresse publique a été collée dans le champ prévu.

Les trois parties ne se remplacent pas. Une photo nouvelle n’apparaît au tableau de bord qu’après la synchronisation. L’assistant ne reçoit pas cette photo.

## Le tableau de bord

La page à ouvrir est [http://127.0.0.1:4317/](http://127.0.0.1:4317/).

Le fichier `dashboard/vite.config.js` prévoit le port 5173. Pour la démonstration, le serveur est lancé sur le port 4317 :

```bash
cd /tmp/Road-damage-project/dashboard
npm run dev -- --host 127.0.0.1 --port 4317
```

### La coque du ministère

La barre latérale porte « Ministère de l’Équipement », puis « TariqMap ». Elle est bleu marine, le texte est blanc, et l’entrée active est bleue.

Le menu principal est : Tableau de bord, Incidents, Cartographie, Assistant IA, Rapports et Synthèse. Plus bas : Risque par tronçon, Analytique, Qualité du modèle, Journal d’audit.

Sans compte, Incidents, Risque par tronçon, Analytique, Qualité du modèle et Journal d’audit affichent « Accès opérationnel limité ». Le texte dit que la vue est réservée aux comptes autorisés, et que les totaux publics restent sur l’aperçu et la carte. Le visiteur peut ouvrir le tableau de bord, la cartographie, l’assistant et les rapports.

En haut de la page, un bouton passe du mode clair au mode sombre, et l’inverse. Le libellé est « Mode sombre » ou « Mode clair ». Le choix est gardé dans le navigateur, clé `tariqmap_theme`, valeur `light` ou `dark`. S’il n’y a pas encore de choix, le thème suit celui du système. Le mode sombre assombrit le fond et garde des accents bleus. Le mode clair est celui de la démonstration : page bleu très pâle, cartes blanches, accents bleus.

### L’accueil

L’accueil montre, dans cet ordre :

1. quatre cartes ;
2. la carte, titre « Carte des incidents » ;
3. un anneau ;
4. des barres par gouvernorat ;
5. le bloc « Assistant intelligent » ;
6. le tableau « Derniers incidents ».

Les quatre cartes sont :

- **Total des incidents** — signalements non rejetés dans la vue ;
- **Routes concernées** — voies approximatives, déduites des coordonnées ;
- **Zones concernées** — gouvernorats déduits des coordonnées ;
- **Dernier incident recensé**.

Les routes et les gouvernorats ne sont pas des champs enregistrés. L’écran le dit : le gouvernorat est déduit du point le plus proche.

L’anneau s’intitule « Répartition par classe » dès qu’un code de classe est présent. Les parts portent les codes, pas un nom de dégradation. S’il n’y a aucun code connu, l’anneau passe à la priorité. Le centre de l’anneau reprend le total et le mot « incidents ».

Les barres s’intitulent « Incidents par gouvernorat ». Au-delà de six gouvernorats, les suivants sont regroupés sous « Autres gouvernorats ».

Le tableau des derniers incidents a les colonnes Date, Route / Lieu, Classe, Statut, Responsable. Le compte connecté en voit au plus cinq, les plus récents, et un lien « Voir tous les incidents ». Le visiteur ne voit pas ces lignes.

## Les chiffres

**128** n’est pas un total de la base. C’était un chiffre de maquette. L’accueil ne l’affiche pas. Les tests du tableau de bord refusent que ce nombre apparaisse dans le total.

Le catalogue visible compte **67** observations : **31** réelles et **36** de démonstration (`is_demo`).

Parmi les lignes réelles non rejetées, **21** ont des coordonnées utilisables. La carte du visiteur les regroupe en **15** mailles d’environ 1 km. Une maille fait 0,01 degré. Le point dessiné est le centre de la maille, pas la position mesurée. La démonstration, les rejets, les coordonnées absentes et le point 0, 0 restent hors de cette grille.

**Quatre dossiers réels n’ont pas de coordonnées.** Ils ne peuvent pas être placés sur la carte. S’ils ne sont pas rejetés, ils restent dans le décompte du compte connecté.

Les fonctions `public_damage_summary` et `public_map_cells` répondent **HTTP 404**. Le total public officiel n’existe donc pas. Le tableau de bord ne transforme pas cet échec en zéro. Quand les mailles viennent du catalogue visible, la légende dit le nombre de signalements réels, le nombre de mailles d’environ 1 km, puis que le total public officiel est indisponible (HTTP 404). Avec le catalogue actuel, cette phrase parle de 21 signalements et de 15 mailles.

Le visiteur ne voit pas les dossiers un par un. Le tableau des derniers incidents dit « Dossiers individuels réservés » et « Les lignes individuelles restent réservées aux comptes autorisés ». La quatrième carte reste **Indisponible**, avec le sous-texte « Dossier individuel non visible ». La date d’un dossier n’est pas montrée au visiteur.

Ce que montrent les quatre cartes, dans le code actuel :

- **Visiteur.** Le total officiel a échoué. La première carte reprend le total du catalogue visible, donc 21, avec la phrase : « Signalements réels non rejetés du catalogue visible. Le total public officiel reste indisponible. » Les cartes des routes et des zones sont déduites des centres de mailles.
- **Compte connecté, lignes chargées.** Les lignes de démonstration sont exclues par défaut. La case « Inclure enregistrements démo » existe sur la barre de filtres des autres vues, pas sur l’accueil, et elle part décochée. La première carte compte les signalements non rejetés de ce filtre. Tant qu’aucune recherche et aucun filtre ne réduisent la vue, ce total ne descend pas sous le compte public : si le nombre chargé était plus petit que 21, la carte afficherait 21. Les 21 signalements localisés font partie des lignes réelles non rejetées, donc le compte chargé n’est pas remplacé par 21. Les derniers incidents de ce compte sont listés. Une recherche ou un filtre peut montrer une part plus petite, et dans ce cas le plancher de 21 ne s’applique plus.
- **Compte connecté, chargement des lignes échoué.** Si les mailles du catalogue sont déjà là, les cartes reprennent ce total connu, 21, et le tableau dit « Liste détaillée non chargée ».

La carte du compte connecté, sur l’onglet Cartographie, utilise les agrégats du serveur à 20 m, pour les observations qui ont un point. La couleur suit la priorité, la taille suit le nombre de signalements. La légende HTTP 404 est celle du visiteur.

Le bouton d’export du visiteur reste inactif tant que les fonctions publiques ne répondent pas. Un fichier vide ne doit pas être présenté comme un export réussi.

## Ce que l’écran ne fabrique pas

Les classes affichées sont les codes **D00**, **D10**, **D20** et **D40**. Le tableau de bord ne les remplace pas par « fissure longitudinale », « fissure transversale », « faïençage » ou « nid-de-poule ». Un code inconnu reste hors de ces quatre cases.

Le coût de réparation affiche **Indisponible**. Aucun barème en dinars n’est dans le dépôt. C’est le texte du centre d’opérations, des rapports et du risque par tronçon.

Le délai moyen n’est pas calculé quand aucune durée de réparation n’a été mesurée. Sur Analytique, la ligne « Délai moyen de résolution » affiche alors **Non calculé**. Le taux d’achèvement, s’il n’est pas mesuré, affiche le même mot.

## L’assistant

L’assistant est sur l’accueil, sous le titre « Assistant intelligent », et il a aussi sa page « Assistant IA ». C’est le même panneau : « Recommandation technique ».

Il répond seulement à partir des six manuels indexés. La consigne du modèle est : utiliser uniquement le contexte, ne rien inventer, et dire clairement que l’information n’a pas été trouvée si elle n’est pas dans ce contexte. Une réponse vide est remplacée par « L'information n'a pas été trouvée dans les manuels. »

### Les modèles et l’index

Le modèle qui rédige est **Qwen2.5-7B-Instruct**, chargé en 4 bits (NF4, avec double quantification). Le notebook demande un GPU T4 : Exécution, Modifier le type d’exécution, GPU.

La recherche des passages utilise **BAAI/bge-m3**. Les vecteurs sont normalisés. L’index est un **FAISS IndexFlatIP** : produit scalaire, ce qui revient ici à une similarité cosinus. L’index qui correspond aux six manuels réels a **431 vecteurs**, de **dimension 1024**.

Le texte est découpé en morceaux de 800 caractères, avec un recouvrement de 100. L’index n’est recalculé que s’il n’y a pas déjà un index réutilisable. Un index est réutilisé seulement s’il est un IndexFlatIP, si sa dimension est 1024, si le modèle d’embedding est BAAI/bge-m3, si le nombre de vecteurs égale le nombre de morceaux, et si les sources sont exactement les six fichiers ci-dessous.

Les six manuels ne sont pas dans le dépôt Git. Ils sont sur la session Colab, avec l’index, sous `/content/road_damage_rag/` quand le notebook tourne dans Colab. S’ils sont déjà là, la cellule ne redemande pas de les envoyer. S’il en manque, elle ouvre le sélecteur une fois. Sans ces fichiers, et sans GPU, le script s’arrête avant de calculer des embeddings.

### Les six noms de fichiers

La cellule n’accepte que ces noms :

- `Arya_2024_RDD2022_Geoscience_Data_Journal (2).txt`
- `Benjelloun_Cours_Routes_EPA_Agadir_Chapitres_1-2 (2).txt`
- `Cours_Pathologies_et_entretien_des_routes_et_ouvrages_dart_4geniecivil (2).txt`
- `FHWA_HRT-13-092_Distress_Identification_Manual_LTPP (2).txt`
- `MTQ_Manuel_identification_degradations_chaussees_flexibles_PROJET (2).txt`
- `Pathologie_des_routes_clean (3).txt`

Les noms qui finissent par `_contenu_organise.txt` appartiennent à une autre description, celle d’un index de 479 vecteurs. Ce n’est pas l’index utilisé ici. Il ne faut pas chercher un index de 479 vecteurs. Il n’est pas l’index de cette soutenance, et il n’est pas à télécharger.

### La question sur le prix de l’enrobé

Parmi les cinq questions de démonstration du notebook, la dernière est :

« Quel est le prix d'une tonne d'enrobé bitumineux en dinars tunisiens ? »

Ce prix n’est pas dans les manuels. La question sert à montrer le refus. Le modèle doit dire que l’information n’a pas été trouvée. Une réponse qui donnerait un montant en dinars serait une erreur. Les quatre autres questions de démonstration portent sur les types de dégradations, l’aspect visuel, les principes de réparation d’une fissure, et les causes des fissures.

### Ce que le tableau de bord envoie

Le panneau a un champ **Adresse de l'API Colab** et un bouton **Enregistrer**. L’adresse est gardée dans le navigateur, clé `tariqmap_rag_url`. On peut y coller la ligne entière `URL_DASHBOARD=https://…` : le tableau de bord en retire l’adresse.

Deux façons de poser une question, et les deux appellent la même API :

- écrire dans **Question** puis **Envoyer** ;
- retenir une observation, puis **Demander une recommandation**.

Le corps envoyé est seulement `{ question, k }`. `k` vaut 5. Il est borné de 1 à 8. Il n’y a pas de photo, pas de coordonnées, pas d’identifiant d’appareil, pas d’adresse de fichier.

**Observation retenue** et **Demander une recommandation** utilisent cette même API. La carte à l’écran peut montrer un lieu et une date, déduits pour l’affichage. La question envoyée, elle, ne contient que la classe, la priorité et le statut connus, sous la forme d’une demande de recommandation d’entretien, « uniquement à partir des manuels de pathologie routière ». Exemple de forme : un désordre de type « code RDD2022 D40 », de priorité élevée, au statut « Non confirmé ».

Pour retenir :

- Visiteur : cliquer une maille. L’infobulle dit que c’est le centre d’une maille d’environ 1 km, pas la position mesurée, et propose « Retenir cette observation ». C’est un agrégat, pas un dossier.
- Compte connecté : cliquer une ligne des derniers incidents, ou un agrégat sur la carte. L’infobulle d’un agrégat du compte a le bouton « Recommandation technique ».

Si l’adresse n’est pas enregistrée, ou si l’API ne répond pas, le texte affiché est « l'API ne répond pas ». Le tableau de bord ne substitue pas une réponse enregistrée à l’avance. Quand une réponse arrive, il affiche le texte, le nom du manuel le mieux classé et son score, puis « Réponse rédigée à partir des manuels indexés. »

Si la question tapée contient un lien, une image, le mot latitude, longitude ou device_id, ou une paire de coordonnées, le tableau de bord ne l’envoie pas. Le message dit que l’assistant n’accepte qu’une question technique sur la pathologie routière.

### Où tourne l’API

L’API n’écoute que `127.0.0.1:8000`, et seulement à l’intérieur de la machine Colab. Le tableau de bord tourne dans le navigateur, sur l’ordinateur qui affiche `http://127.0.0.1:4317`. Pour ce navigateur, `127.0.0.1` est son propre ordinateur, pas Colab. Un appel direct au port 8000 ne peut donc pas atteindre le modèle.

Le fichier à ouvrir dans Colab est `rag/soutenance/assistant_colab.ipynb`, sur la branche `cursor/rag-free-local-prototype-4fb6`. Le même code est dans `rag/soutenance/colab_assistant.py`.

Après le démarrage, la cellule ouvre un tunnel HTTPS et imprime une ligne `URL_DASHBOARD=https://…`.

- Si le secret Colab `NGROK_AUTHTOKEN` est présent, ou la variable d’environnement du même nom, le tunnel est ngrok (`https://….ngrok-free.app`).
- Sinon, la cellule installe `cloudflared` si besoin et ouvre un tunnel Cloudflare vers `http://127.0.0.1:8000`. Elle imprime `URL_DASHBOARD=https://….trycloudflare.com`. Aucun jeton n’est nécessaire pour cette voie, et aucun jeton n’est écrit dans le fichier.

On colle cette ligne dans **Adresse de l'API Colab**, on clique **Enregistrer**, puis on pose une question.

`GET /health` et `GET /` renvoient l’état, le nom du modèle, le nom de l’embedding, le nombre de vecteurs, la dimension et la présence d’un GPU. `POST /ask` attend le JSON `{ question, k }`.

Si une exécution précédente répond déjà sur le port 8000 avec ce JSON, la cellule ne recharge pas Qwen : elle ouvre seulement le tunnel. Si le port sert encore une ancienne API qui refuse ce JSON et attend un paramètre d’URL nommé `request`, il faut redémarrer l’environnement d’exécution, puis relancer la cellule. L’index déjà construit est conservé.

Il ne faut pas faire une réinitialisation d’usine de Colab. Elle efface les six manuels et l’index. Un redémarrage de l’environnement d’exécution n’est pas une réinitialisation d’usine.

Le tunnel public sert à donner au tableau de bord l’adresse à coller. Cette adresse ne doit pas être diffusée au-delà de la démonstration.

## L’application mobile

Le téléphone est le dossier `app/`. Il y a un projet Android (`app/android`) et un projet iOS (`app/ios`). Le `pubspec.yaml` s’appelle `tariqmap`, version `0.1.0+1`, description « Offline-first road damage inspection for Tunisia ». Le SDK Flutter demandé est au moins 3.4 et strictement inférieur à 4. L’application se verrouille en portrait.

Les écrans du téléphone sont en anglais. Le fichier `app/README.md` est encore le texte vide d’un projet Flutter neuf. Les commandes qui existent sont dans le README à la racine du dépôt :

```bash
cd app
flutter pub get
flutter test test/unit/
flutter run
```

Un téléphone Android ou iOS physique est l’appareil prévu : la caméra et le modèle en ont besoin. Le navigateur n’est pas l’outil d’inspection. La caméra en direct y est refusée, avec le message « Live camera is not supported in browser. »

### Ce que le téléphone montre

Au premier lancement, s’il n’y a pas d’organisation choisie, l’application demande d’en choisir une. Elle essaie de lire la table `organizations` dans Supabase. Si cette lecture échoue, elle propose une liste intégrée de trois autorités : Municipality (Commune), Ministry of Equipment (Ministère de l’Équipement), Tunisia Autoroutes (Tunisie Autoroutes). Le choix est gardé sur le téléphone et peut être changé plus tard.

L’accueil s’intitule TariqMap, sous-titre « Road Inspection ». Trois actions :

- **Take Photo** — « Capture & analyse road defects with AI » ;
- **Record Video** — « Extract & detect anomalies frame by frame » ;
- **Drive Awareness** — « Real-time road hazard alerts centered on your route ».

En dessous : la carte des anomalies déjà sur le téléphone, puis « RECENT INSPECTIONS ». Un bandeau de synchronisation indique l’état (par exemple « pending sync » ou « All observations synced ») et, s’il reste quelque chose à envoyer, un bouton **Sync** ou **Retry**. Les réglages sont l’écran **Settings**.

### La capture d’une photo

Take Photo ouvre un choix : **Open Camera** ou **Choose from Gallery**.

L’écran caméra est un aperçu. Il renvoie le chemin de la photo. Il ne lance pas la détection et il n’enregistre rien.

Ensuite vient **Confirm Photo**. Le texte dit « Is this photo ready for analysis? » et « Nothing is saved until you choose Analyse. » Deux boutons : **Retake** et **Analyse**. Retake reprend une photo. Rien n’est écrit tant qu’on n’a pas choisi Analyse.

Analyse demande la position GPS si le téléphone l’autorise. Il lit la taille de l’image, fait tourner le modèle sur l’appareil, puis enregistre l’observation dans la base locale SQLite. L’écran de résultat lit cette ligne locale, pas un objet encore en mémoire. Si le GPS manque, la latitude et la longitude enregistrées sont 0 et 0. Le tableau de bord ne dessine pas le point 0, 0 : ces observations ne deviennent pas une épingle au large.

### Le modèle sur le téléphone

Le modèle actif par défaut est le fichier `assets/models/road_damage.tflite`, version de lot `2026.09.23-rdd2022`. L’entrée fait 640 par 640. Les quatre codes sont **D00**, **D10**, **D20** et **D40**. Le seuil de confiance par défaut est 0,35, le seuil de recouvrement 0,45.

Un second fichier, `road_damage_roadsense.tflite`, est présent comme modèle expérimental. Il reste éteint tant que la compilation ne passe pas le drapeau `USE_ROADSENSE_MODEL`. La démonstration et le comportement par défaut n’utilisent que `road_damage`.

L’écran de résultat affiche le code, par exemple D40. Sous un code connu, il ajoute le nom anglais du fichier de constantes et la phrase « plain-language name is unconfirmed ». Un code inconnu reste « Unknown class ». Il ne faut donc pas défendre un nom français de dégradation comme un libellé vérifié : le tableau de bord ne le montre pas, et le téléphone marque le nom en clair comme non confirmé.

La priorité est un score calculé sur le téléphone à partir de la classe. Ce n’est pas un prix et ce n’est pas un délai de réparation.

### La vidéo et la conduite

Record Video a deux modes écrits dans l’écran :

- **Fast Scan** : une image toutes les 5 secondes, jusqu’à 12 images ;
- **Accurate Scan** : une image toutes les 2 secondes, jusqu’à 25 images.

Chaque image analysée est enregistrée dans la base locale au fur et à mesure. Arrêter ou interrompre garde les observations déjà terminées. L’assemblage d’une vidéo annotée est une étape à part, sur le téléphone.

Drive Awareness prévient d’anomalies déjà connues devant le véhicule. L’écran le dit dans le code : alertes sans inférence continue du modèle, et sans envoi du trajet. Ce n’est pas une nouvelle capture. Les alertes peuvent s’appuyer sur un cache local quand le réseau manque.

### Ce que la synchronisation écrit dans Supabase

Analyse n’envoie rien tout seul. L’envoi part du bouton **Sync** (ou **Retry**). Au démarrage, l’application remet seulement en attente les envois qui étaient restés bloqués sur « uploading ».

Dans Settings, « Wi-Fi only uploads » est activé par défaut. Tant que ce réglage est actif, Sync et Retry n’envoient rien sur les données mobiles ni sur une connexion inconnue. Le nombre de tentatives s’arrête à 5. La ligne locale est conservée.

Pour chaque observation en attente, le téléphone appelle d’abord la fonction `submit_observation`, avec l’observation, le lieu, les passages du modèle, les détections et une clé d’idempotence. Cette fonction est dans les migrations du dépôt. Si le serveur répond qu’elle n’existe pas, le téléphone écrit les tables lui-même. Une lecture de la base le 15 novembre 2026 ne trouvait pas cette fonction : tant qu’elle n’est pas déployée, c’est l’écriture directe qui a lieu. Il ne faut pas présenter `submit_observation` comme déjà en service sur la base publique.

Les champs écrits, dans le code :

- **observations** : identifiants, organisation choisie, `source` fixé à `camera`, date, taille de l’image, score et libellé de priorité, `anomaly_type` égal au code de la première détection, version du modèle, `is_demo` faux, `status` `unconfirmed`. Le champ `device_id` est envoyé à `null`.
- **locations** : latitude, longitude, précision en mètres, date.
- **agent_runs** et **detections** : code de classe, confiance, boîte, et le fait que le passage est ou non un essai simulé.
- **media_files** et le seau `observation-images` : la photo d’origine, compressée, chemin stable. Ce seau n’est pas le seau public.
- **media_files** et le seau `public-photos` : une vignette, seulement s’il y a au moins une détection et si le partage public est allumé. Il est allumé par défaut, et Settings peut le couper. La vignette est un recadrage autour de la détection, marge de 25 %, le reste du recadrage fortement flouté, WebP, grand côté au plus 800 pixels, fichier sous 250 ko. Sans détection, il n’y a pas de vignette publique. L’application n’a pas de modèle de visages ni de plaques : le flou vient uniquement de ce recadrage.

L’identifiant d’appareil existe sur le téléphone, clé locale `tariqmap_device_id`. Il n’est pas envoyé dans les tables lisibles sans compte.

Un reçu de synchronisation n’est écrit par le téléphone, sur le chemin direct, qu’une fois la photo d’origine et l’étape de vignette terminées. Un succès de la fonction atomique n’est pas, à lui seul, la preuve que la photo est arrivée : le téléphone vérifie l’objet.

### Ce que le tableau de bord montre ensuite

Une observation synchronisée avec `is_demo` faux entre dans les 31 lignes réelles du catalogue, pas dans les 36 de démonstration.

Le compte connecté peut la voir dans les incidents et, si les coordonnées sont utilisables, dans un agrégat d’environ 20 m. Les quatre lignes réelles sans coordonnées, et un point resté à 0, 0, ne donnent pas d’épingle.

Le visiteur ne voit toujours pas le dossier. Si le point est réel, non rejeté et localisé, il peut rejoindre une maille d’environ 1 km. Le centre affiché n’est pas le GPS mesuré.

La vignette publique, si elle a été produite, est la seule image prévue pour une lecture sans compte. La photo d’origine reste dans `observation-images`.

## Comment les trois parties se relient

1. Le téléphone crée l’observation. La photo est confirmée, le modèle `road_damage` pose un code parmi D00, D10, D20 et D40, la ligne est écrite dans SQLite, puis **Sync** l’envoie à Supabase avec le lieu, les détections et, selon les réglages, la photo et une vignette floutée. L’identifiant d’appareil ne part pas.

2. Le tableau de bord lit Supabase. Le visiteur voit le total public de substitution, 21 signalements en 15 mailles, et pas les dossiers. Le compte connecté voit au moins ce compte public tant que la vue n’est pas filtrée, et il voit les lignes. Les deux fonctions officielles `public_damage_summary` et `public_map_cells` répondent encore 404 : le total officiel est absent. Le coût reste Indisponible, le délai moyen reste Non calculé quand il n’a pas été mesuré, et 128 ne revient pas.

3. L’assistant explique la pathologie à partir des six manuels, via Qwen2.5-7B-Instruct en 4 bits, BGE-M3 et l’index FAISS de 431 vecteurs. **Observation retenue** et **Demander une recommandation** appellent la même API que la question libre. Ils n’envoient ni la photo, ni les coordonnées exactes, ni l’identifiant d’appareil. L’assistant ne lit pas la photo qui vient d’être prise. Si on lui demande le prix d’une tonne d’enrobé, il doit refuser, parce que ce prix n’est pas dans les manuels.
