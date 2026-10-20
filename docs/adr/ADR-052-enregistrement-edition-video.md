# ADR-052 — Enregistrement et édition vidéo dans l'app

## Statut
Accepté

Complète [ADR-016](ADR-016-perimetre-mvp.md) (périmètre) sans le remplacer : l'enregistrement et l'édition vidéo, reportés par l'ADR-016 (« Création et édition »), entrent dans le périmètre (décision du développeur). Complète aussi l'[ADR-035](ADR-035-metadonnees-personnelles-videos.md) (métadonnées retirées dans l'app) et l'[ADR-040](ADR-040-duree-maximale-video.md) (durée maximale), dont il précise l'application aux vidéos filmées ou modifiées.

## Contexte
Jusqu'ici, une vidéo ne pouvait venir que de la galerie, publiée telle quelle (ADR-016). Une vidéo de plus de 3 minutes était refusée dès le choix (ADR-040), sans moyen de la raccourcir dans l'app. Les stories (ADR-051) suivent le même chemin, avec une limite de 60 s.

L'ADR-016 annonçait que la création et l'édition viendraient « enrichir l'upload simple ». Le pipeline existant n'a pas à changer : l'API ne reçoit jamais d'octet vidéo (ADR-007), le worker transcode tout fichier reçu (ADR-008) et revérifie sa durée (ADR-040). Il suffit que l'app produise le fichier à envoyer.

Contraintes :
- le simulateur iOS n'a pas de caméra : la capture ne peut se vérifier que sur un iPhone ;
- la position GPS ne doit jamais quitter le téléphone (ADR-035), y compris pour une vidéo filmée dans l'app ;
- une musique ajoutée poserait la question des droits d'auteur.

## Décision
Choix du développeur, parmi les options proposées :
- **pas de musique** : seul le son capté par le micro, ou celui de la vidéo importée, est gardé. Les sons tendances restent reportés (ADR-016) ;
- **édition** : découpage du début et de la fin, filtres de couleur, texte superposé, vitesse de 0,5× à 2× ;
- **enregistrement par segments**, comme TikTok ;
- **partout** : la caméra sert aux vidéos et aux stories, et l'éditeur s'ouvre aussi pour une vidéo de la galerie.

### Caméra (`AVCaptureSession`)
- Plein écran depuis l'onglet « Publier », bouton « Filmer ».
- **Segments** : toucher le déclencheur démarre, toucher à nouveau arrête. Plusieurs segments peuvent s'enchaîner, avec un changement de caméra possible entre deux. On peut retirer le dernier segment.
- La durée totale est bornée : **3 minutes** pour une vidéo, **60 s** pour une story. L'enregistrement s'arrête seul à la limite, et une barre de progression montre le total.
- Réglages :
  - caméra avant ou arrière ;
  - lampe (caméra arrière seulement) ;
  - minuteur de 3 s avant le démarrage.
- Format : 1080p, 30 i/s, portrait ; l'image de la caméra avant est en miroir.
- **Story** : sélecteur « Vidéo | Photo » sous le déclencheur. Une photo prise passe par la préparation existante des photos de story (recadrage 9:16, réencodage sans métadonnées, ADR-051).
- **Autorisations** :
  - **caméra refusée** : un message propose les Réglages ou la galerie ;
  - **micro refusé** : l'enregistrement se fait **sans son** ;
  - **aucune caméra** (simulateur) : « Caméra indisponible », la galerie reste proposée.
- Quitter la caméra avec des segments enregistrés demande une confirmation, puis les supprime.

### Éditeur
- Il s'ouvre **après un enregistrement**, ou par « Modifier la vidéo » sur une vidéo choisie dans la galerie.
- Il s'ouvre d'office quand la vidéo de la galerie est trop longue (voir « Durée »). Une vidéo de la galerie peut donc être publiée sans passer par l'éditeur.
- **Aperçu** : lecture en boucle, filtre et vitesse appliqués en direct par la même composition que l'export ; textes affichés par-dessus. Si le lecteur refuse la composition vidéo, l'aperçu se relit sans elle (« Aperçu simplifié »).
- **Découpage** : début et fin choisis sur une frise de miniatures ; **1 s au moins**.
- **Vitesse** : 0,5×, 1×, 1,5×, 2×, appliquée à toute la vidéo. **La hauteur du son est gardée** : algorithme `spectral` d'AVFoundation, en aperçu comme à l'export.
- **Filtres** : sept filtres Core Image et « Aucun », appliqués à toute la vidéo :
  - Noir et blanc ;
  - Chaud ;
  - Froid ;
  - Vif ;
  - Vintage ;
  - Fondu ;
  - Instantané.
- **Textes** :
  - jusqu'à **5**, de 1 à **80** caractères chacun ;
  - déplacés au doigt ;
  - 6 couleurs, 3 tailles ;
  - visibles pendant toute la vidéo ;
  - la taille est relative à la largeur de l'image : identique en aperçu et à l'export.
- **Réouvrir l'éditeur** repart des fichiers d'origine, pas de la vidéo déjà exportée : pas de double réencodage. Les fichiers d'origine sont supprimés à la publication ou à l'abandon.
- **Photos de story** : ni filtre ni texte pour l'instant.

### Export, sur l'iPhone
- **Sans réencodage** quand c'est possible : un seul fichier d'origine, aucun filtre, aucun texte, vitesse 1×. Dans ce cas, seul le découpage s'applique. C'est la ré-écriture de l'ADR-035 (préréglage `Passthrough`), limitée à l'intervalle choisi. La qualité et les couleurs HDR d'origine sont gardées, et le worker les convertit (ADR-047).
- **Sinon, réencodage** :
  - composition AVFoundation : segments mis bout à bout, intervalle choisi, vitesse ;
  - **compositeur personnalisé** (`AVVideoCompositing`), qui applique dans l'ordre la rotation de chaque segment, le filtre et les textes (Core Image) ;
  - vidéo en H.264, petit côté de 1080 px au plus (jamais agrandi), cadence de la source (60 i/s au plus) ;
  - son en AAC.
- **Toujours** au format QuickTime (`.mov`), avec le filtre de partage (`AVMetadataItemFilter.forSharing()`) : aucune position, aucun appareil (ADR-035).
- Le fichier exporté suit ensuite la publication existante : description, file d'envoi, reprise après relance.

### Durée
- **La règle porte sur la vidéo finale**, après découpage et vitesse : 3 minutes au plus pour une vidéo (ADR-040), 60 s pour une story (ADR-051), à une seconde près. Le worker revérifie le fichier reçu ; il ne change pas.
- **Galerie** : une vidéo plus longue que la limite n'est plus refusée. L'éditeur s'ouvre, l'intervalle est réglé sur le début de la vidéo, à la durée maximale, et « Terminé » reste bloqué tant que la vidéo finale dépasse la limite. Le message rappelle la limite.
- **Ralenti** : il allonge la vidéo, et la même règle s'applique.

### Mesure d'audience (ADR-013)
- `video_upload_started` et `story_upload_started` portent la source du média : `source` (`camera` ou `gallery`).
- Ils portent aussi les modifications :
  - `segments` ;
  - `trimmed` ;
  - `filter` (identifiant du filtre, ou `none`) ;
  - `text_count` ;
  - `speed`.
- Jamais le texte saisi.

### Architecture (ADR-002)
- **Domaine** :
  - règles pures, testées sans AVFoundation : `RecordingSession` (segments, durée restante, limite) et `EditPlan` (sources, découpage, vitesse, filtre, textes ; durée finale, validité, besoin de réencodage) ;
  - ports `VideoCamera` (capture) et `VideoEditor` (export) ;
  - cas d'usage `ExportEditedVideoUseCase`.
- **Données** :
  - `AVFoundationVideoCamera` ;
  - `AVFoundationVideoEditor` : composition, compositeur et rendu des textes.
- **Présentation** :
  - `CameraView` et `CameraViewModel` ;
  - `VideoEditorView` et `VideoEditorViewModel` ;
  - le brouillon de l'onglet « Publier » garde ses sources et son plan d'édition.
- **API, worker et contrat OpenAPI inchangés.**

## Alternatives
- **Édition par le worker** : l'app envoie les fichiers d'origine et un plan d'édition (JSON), et FFmpeg applique découpage, filtres et textes. Un seul brut gardé, réutilisable par un autre client. Mais :
  - l'aperçu (Core Image) et le résultat (FFmpeg) différeraient ;
  - le contrat, la base, le worker et l'app changeraient tous ;
  - les segments devraient être envoyés séparément.

  Rejeté.
- **SDK d'édition tiers** (IMG.LY, Banuba…) : interface complète tout de suite, mais licence payante, dépendance lourde et métadonnées moins maîtrisées. Rejeté.
- **Filtres pendant l'enregistrement** (`AVCaptureVideoDataOutput` et `AVAssetWriter`) : on verrait le filtre en filmant. Mais il faudrait deux chemins de rendu (capture et galerie), et le filtre ne pourrait plus changer après coup. Rejeté : les filtres s'appliquent dans l'éditeur.
- **Vitesse choisie avant l'enregistrement**, comme TikTok : elle ne s'appliquerait pas aux vidéos de la galerie. Rejeté au profit de l'éditeur.
- **Musique** :
  - pistes libres de droits embarquées : pistes à trouver, app plus lourde ;
  - bibliothèque de l'appareil : titres Apple Music protégés (DRM), donc inexportables.

  Écartées par le développeur.
- **Une seule prise** au lieu des segments : plus simple, moins proche de TikTok. Écarté par le développeur.
- **Toujours réencoder** : un seul chemin, mais qualité perdue et couleurs HDR converties sans besoin pour un simple découpage. Rejeté.
- **Garder le refus d'une vidéo de galerie trop longue** (ADR-040) : maintenant que le découpage existe, mieux vaut le proposer. Rejeté.

## Conséquences
### Positives
- **Vidéos filmées dans l'app** : on peut filmer, découper, ralentir ou accélérer, colorer et légender sans quitter l'app.
- **Pipeline inchangé** : le serveur ne change pas (API, worker, contrat), et le pipeline vidéo garde un seul point d'entrée.
- **Aperçu fidèle** : il utilise la même composition que l'export.
- **Métadonnées** : la règle de l'ADR-035 s'applique à chaque fichier produit, filmé ou importé.
- **Galerie** : une vidéo trop longue peut être raccourcie au lieu d'être refusée.

### Négatives
- **Réencodage sur l'iPhone** : il prend du temps (de l'ordre de la durée de la vidéo) et de la batterie, et la vidéo perd un peu de qualité avant même le transcodage du serveur.
- **HDR** : une vidéo HDR filtrée, légendée ou accélérée est convertie en SDR par Core Image dans l'app, et non par le tone mapping du worker. Ce rendu n'est vérifiable que sur un iPhone.
- **Vérifications sur iPhone seulement** : la capture (caméra, micro, lampe, miroir, rotation, autorisations) ne se vérifie que sur un iPhone. Le simulateur ne teste que les règles, l'éditeur et l'export, sur des fichiers générés.
- **Aperçu dans le simulateur** : un `AVPlayerLayer` n'y affiche aucune composition vidéo, même celle de Core Image d'Apple. L'aperçu s'y relit donc sans filtre ni rotation (« Aperçu simplifié »). L'aperçu filtré ne se vérifie que sur un iPhone ; l'export, lui, est complet partout.
- **Espace disque** : les fichiers d'origine sont gardés jusqu'à la publication, en plus du fichier exporté.
- **Photos de story** : pas encore de filtre ni de texte.
- **Brut non éditable** : le brut stocké est la vidéo déjà éditée, sans retour possible aux fichiers d'origine.

## Liens
- ADR-002 — Architecture mobile
- ADR-007 — Upload vidéo direct
- ADR-008 — Pipeline vidéo HLS
- ADR-013 — Mesure d'audience
- ADR-016 — Périmètre de la première version
- ADR-035 — Métadonnées personnelles des vidéos
- ADR-040 — Durée maximale d'une vidéo
- ADR-047 — Tone mapping HDR
- ADR-051 — Stories
- Complété par [ADR-062](ADR-062-creation-video-facon-tiktok.md) — Création vidéo façon TikTok : caméra, galerie, éditeur par clips, commentaires désactivables
- Complété par [ADR-063](ADR-063-filtres-autocollants-effets.md) — Éditeur vidéo : filtres en catégories, autocollants, effets
