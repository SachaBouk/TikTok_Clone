# ADR-062 — Création vidéo façon TikTok : caméra, galerie, éditeur par clips, réglages de publication

## Statut
Accepté

Complète [ADR-052](ADR-052-enregistrement-edition-video.md) (enregistrement et édition vidéo), [ADR-016](ADR-016-perimetre-mvp.md) (publication) et [ADR-060](ADR-060-commentaires-facon-tiktok.md) (commentaires), sans les remplacer.

## Contexte
La création passe aujourd'hui par un formulaire (onglet « Publier » : « Filmer », « Choisir dans la galerie », description, « Publier »), puis un éditeur réduit (découpage du début et de la fin, une vitesse de 0,5× à 2× pour toute la vidéo, filtre, textes). Le développeur veut le parcours de TikTok, à partir de captures : caméra plein écran, galerie « Récents » à sélection numérotée, aperçu avec ses outils, éditeur par clips (frise, diviser, supprimer, vitesse, recadrage), écran de publication et ses réglages, dont « Autoriser les commentaires ».

## Décision
Choix du développeur, parmi les options proposées.

### Parcours (app)
- **Le bouton « + » de la barre d'onglets ouvre la caméra en plein écran**, par-dessus les onglets (comme TikTok) ; il ne change plus d'onglet. Modes en bas : « Caméra », « Story », « Live ».
- **Caméra** : ×, réglages à droite (changer de caméra, lampe, minuteur), durée maximale au-dessus du déclencheur (« 3 min », « 60 s », « 15 s ») en mode Caméra, « Vidéo | Photo » en mode Story ; à droite du déclencheur, « Importer » avec la dernière vidéo de la galerie en miniature (puis ✓ une fois des segments filmés). Mode Live : titre et « Lancer le live » sur l'aperçu de la caméra.
- **Galerie maison** (PhotoKit, autorisation d'accès aux Photos, accès limité compris) : « Récents ⌄ » (choix de l'album), onglets « Tout | Vidéos | Photos » en mode Story (vidéos seules en mode Caméra), grille avec durées, **sélection numérotée** de plusieurs vidéos (« Sélectionner plusieurs »), bandeau des vidéos choisies (× pour retirer), « Suivant (N) ». Les vidéos choisies deviennent les clips de l'éditeur, dans l'ordre de sélection. Une vidéo iCloud est téléchargée ; les métadonnées personnelles sont retirées comme avant (ADR-035).
- **Aperçu** : la vidéo en plein écran, outils à droite (Réglages, Modifier, Texte, Filtres), « Ta story » et « Suivant » en bas. « Ta story » publie directement en story (60 s au plus, ADR-051).
- **Éditeur par clips** (« Modifier ») : aperçu au format 9:16, durée « 00:01 / 00:19 », lecture, annuler / rétablir, frise des clips sous une tête de lecture fixe, « + » pour ajouter des vidéos, son coupé pour tous. Outils d'un clip : **Diviser** (à la tête de lecture), **Supprimer**, **Vitesse** (curseur de 0,1× à 10×, « Appliquer à tout »), **Recadrer** (Libre, 9:16, 16:9, 1:1, 3:4, 4:3), **Volume** (0 à 100 %, « Appliquer à tout »), **Rotation** (quart de tour) ; bords du clip sélectionné déplacés au doigt pour le découper.
- **Écran de publication** : description (2 200 caractères, suggestions de hashtags, bouton « # Hashtags »), couverture affichée (première image), ligne « Tout le monde peut voir cette publication › », bouton « Publier ».
- **Réglages de la publication** (feuille, depuis l'aperçu ou l'écran de publication) : « Qui peut voir cette publication » (Tout le monde, par défaut / Toi uniquement, ADR-061), « Définir comme audience par défaut » (gardé sur l'iPhone), « Autoriser les commentaires ».
- **Abandon** : ‹ de l'aperçu propose toujours « Abandonner la vidéo ? » (fichiers supprimés, retour à la caméra) ; ‹ de l'écran de publication rouvre l'éditeur sur le même plan.
- **Publications en cours** : une fois « Publier » touché, la création se ferme et l'onglet Profil s'ouvre (vignette « Publication… », ADR-056) ; la liste des publications (réessayer, annuler, voir) devient une page ouverte depuis ces vignettes.

### Rendu (app, précise l'ADR-052)
- **Plan d'édition par clips** : chaque clip garde son fichier d'origine, son intervalle, sa vitesse (0,1× à 10×), son volume (0 à 1), son recadrage (rectangle relatif) et sa rotation ; filtre et textes restent communs à toute la vidéo.
- **Image finale au format 9:16** (petit côté de 1080 px au plus, jamais agrandi) : chaque clip est tourné, recadré, puis **ajusté** dans l'image (bandes noires si ses proportions diffèrent, comme TikTok), avant le filtre et les textes.
- **Sans réencodage** quand rien n'a changé : un seul clip, sans recadrage, rotation, changement de vitesse ou de volume, ni filtre ni texte : seul l'intervalle est recopié, au format d'origine (qualité et HDR gardés, ADR-052).
- **Durée** : la règle de l'ADR-040 et de l'ADR-051 porte toujours sur la vidéo finale (somme des clips après vitesse) ; 0,1 s au moins par clip, 1 s au moins pour la vidéo.
- La hauteur du son est gardée à toute vitesse (`spectral`, de 1/32 à 32×).

### Commentaires désactivables (API)
- Colonne `videos.comments_enabled` (booléen, vrai par défaut, migration `video_comments_enabled`).
- **Choisi à l'envoi** (`POST /videos/upload-url` : `commentsEnabled` facultatif, vrai par défaut) et **changé par l'auteur** quel que soit le statut : `PATCH /videos/:id/comment-settings` `{ commentsEnabled }` → la vidéo (404 pour la vidéo d'un autre).
- **Commentaires coupés** : personne ne peut commenter, répondre ni aimer un commentaire (**403** « Les commentaires sont désactivés pour cette vidéo. »), l'auteur compris. Les commentaires existants sont **gardés mais cachés** à tous sauf à l'auteur de la vidéo (liste vide, réponses 404), qui peut encore les supprimer ; retirer un j'aime reste possible, et l'historique des commentaires de leur auteur les garde. Tout revient quand ils sont rétablis. `comments_count` ne change pas.
- `VideoDto`, `FeedItemDto` et la vidéo du backoffice portent `commentsEnabled`.
- App : la feuille des commentaires affiche « Les commentaires sont désactivés pour cette vidéo. » sans champ de saisie ; « Désactiver / Activer les commentaires » dans la feuille de partage de ses vidéos.

### Hors périmètre (décision du développeur)
Sons et musique (ADR-052), effets, modèles (« Template »), AutoCut, « Magic », superpositions, autocollants, voix off, lieu, liens, mentions dans la description (l'API ne les notifie pas), « Partager sur », divulgation de contenu et contenu généré par IA, **brouillons** et **choix de la couverture** (reportés), visibilité « Amis » (ADR-061).

## Alternatives
- **Sélecteur de photos du système** (`PhotosPicker`) : sans autorisation à demander, mais sans bandeau ni l'apparence des captures. Écarté par le développeur.
- **Garder l'image aux proportions du premier clip** (rognée pour remplir) : pas de bandes noires, mais un clip couché perd ses bords et un recadrage n'a plus de cadre stable. Rejeté au profit du 9:16 de TikTok.
- **Supprimer les commentaires existants quand on les coupe** : irréversible. Rejeté.
- **Laisser l'auteur commenter quand les commentaires sont coupés** : peu utile et source de confusion. Rejeté.

## Conséquences
### Positives
- Parcours de création proche de TikTok ; plusieurs vidéos assemblées, chacune avec sa vitesse, son volume, son cadre et sa rotation.
- Rien ne change pour le serveur côté vidéo (ADR-052) : l'app envoie toujours un seul fichier.
- Un créateur peut couper les commentaires sans rien perdre.

### Négatives
- L'app demande l'accès aux Photos (complet ou limité) ; refusé, seule la caméra reste.
- Une vidéo couchée modifiée est publiée en 9:16 avec des bandes noires ; non modifiée, elle reste couchée.
- Un réencodage à 10× ou 0,1× reste borné par la durée maximale ; le ralenti allonge l'export sur l'iPhone.
- Les commentaires coupés restent dans la base et comptent dans `comments_count`.

## Liens
- ADR-016 — Périmètre de la première version
- ADR-035 — Métadonnées personnelles des vidéos
- ADR-040 — Durée maximale d'une vidéo
- ADR-051 — Stories
- ADR-052 — Enregistrement et édition vidéo dans l'app
- ADR-060 — Commentaires façon TikTok
- ADR-061 — Vidéos privées
