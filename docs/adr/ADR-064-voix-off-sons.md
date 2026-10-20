# ADR-064 — Éditeur vidéo : voix off, effets de voix, sons repris des vidéos

## Statut
Proposé

Complète [ADR-062](ADR-062-creation-video-facon-tiktok.md) (création vidéo), [ADR-052](ADR-052-enregistrement-edition-video.md) (édition vidéo, « sans musique ») et [ADR-016](ADR-016-perimetre-mvp.md) (sons reportés), sans les remplacer.

## Contexte
L'ADR-062 a laissé hors périmètre la voix off, et l'ADR-016 et l'ADR-052 les sons et la musique (droits d'auteur). Le développeur fournit des captures de TikTok : écran « Voix off » (frise sous une tête de lecture, micro, « Son d'origine »), effets de voix (« Magnetic », « Cave », « Church », « Telephone »…), bibliothèque de sons (« Recommended », « Favorites », « Recent », recherche, découpage ✂︎, favori), feuille « Volume » (son d'origine, son ajouté). Il demande de les ajouter ; pour les sons, de **reprendre le son des vidéos publiées dans l'app** (« Son original - @pseudo »), jamais de musique d'un catalogue extérieur.

## Décision
Choix du développeur, parmi les options proposées.

### Voix off et effets de voix (app)
- **Écran « Voix off »** : la vidéo, une frise sous une tête de lecture fixe, un micro rouge (l'enregistrement part de la tête de lecture pendant la lecture, un carré l'arrête ; il s'arrête seul à la fin de la vidéo ou au début de l'enregistrement suivant), ⌫ retire le dernier enregistrement, « Son d'origine » à cocher (le garder sous la voix), « Terminé ». Plusieurs enregistrements, sans chevauchement.
- **Effets de voix** (écran « Annuler / Enregistrer », onglets Tendances, Personnages, Améliorations) : une douzaine d'effets AVAudioEngine (réverbération, distorsion, hauteur, égaliseur) appliqués **à la voix off seulement** ; sans voix off, l'écran invite à en enregistrer une.
- Rendu à l'export sur l'iPhone, mêlé au son des clips : l'app envoie toujours un seul fichier (ADR-052).

### Sons repris des vidéos (API, worker, app)
- **Source** : toute vidéo **publique** avec du son fournit un son « Son original - @pseudo », sauf si son auteur décoche **« Autoriser l'utilisation de mon son »** (colonne `videos.sound_shared`, vraie par défaut ; choisie à l'envoi et changée par l'auteur : `PATCH /videos/:id/sound-settings`). Une vidéo privée, d'un compte masqué (suspendu, blocage dans un sens ou l'autre) ou qui ne l'autorise plus ne fournit plus son son ; il revient avec elle.
- **Worker** : pour une vidéo (pas une story) avec du son, il extrait la piste en AAC (`<videoId>/sound.m4a` dans le bucket HLS) ; le résultat `ready` porte `soundUrl` et sa durée. Seule l'API écrit en base (ADR-012).
- **Table `sounds`** (module `videos`, comme les hashtags) : un son par vidéo (`video_id` unique, cascade), auteur, URL et durée du fichier. Supprimée avec la vidéo ; une vidéo qui l'utilisait garde son son (incrusté dans son fichier) et perd seulement le lien (`videos.sound_id` à NULL).
- **Utilisation** : `POST /videos/upload-url` accepte `soundId` (son disponible, sinon 404) ; le nombre de publications d'un son compte les vidéos publiques publiées qui l'utilisent, à la lecture.
- **Favoris** sur le compte : table `sound_favorites` ; `PUT` / `DELETE /sounds/:id/favorite`.
- **Routes** (module `feed`, qui connaît les comptes masqués ; compte connecté) : `GET /sounds/recommended` (les plus utilisés, puis les plus récents), `GET /sounds/favorites`, `GET /sounds/search?q=` (pseudo, nom ou description de la vidéo), `GET /sounds?ids=` (« Récents », gardés sur l'iPhone).
- **App** : bandeau « ♫ Ajouter un son » en haut de l'aperçu ; panneau Recommandés, Favoris, Récents et recherche ; un son choisi est essayé aussitôt sur la vidéo ; ✂︎ choisit le passage ; favori ; « Son d'origine » à cocher (décoché quand un son est ajouté) ; feuille « Volume » (son d'origine, son ajouté : voix off et son). Le son est mêlé à la vidéo à l'export.

### Mesure d'audience
`video_upload_started` porte en plus `voiceover_count`, `voice_effect`, `sound_used` et `sound_shared`.

### Hors périmètre (décision du développeur)
Page d'un son dans le feed (bandeau ♫ sous les vidéos, vidéos qui l'utilisent ; reportée), musique d'un catalogue extérieur, sons « commerciaux », effets de voix sur le son d'origine, synthèse vocale, sons des stories et des lives.

## Alternatives
- **Musique sous licence** : demande des contrats et un fournisseur. Écarté (ADR-052).
- **Sons libres de droits embarqués dans l'app** : simple, mais une bibliothèque figée. Écarté par le développeur.
- **Favoris sur l'iPhone** : sans API, mais perdus en changeant d'appareil. Écarté.
- **Son réutilisable seulement si l'auteur accepte** : peu de sons au départ. Écarté au profit d'un refus explicite.

## Conséquences
### Positives
- Voix off, effets et sons sans service extérieur ; le son d'une vidéo circule dans l'app.
- Le serveur ne mixe rien : l'app envoie un fichier final, comme avant.

### Négatives
- Un fichier de son de plus par vidéo dans le stockage (AAC 128 kbit/s, 3 MiB au plus pour 3 min).
- Le son repris est copié dans chaque vidéo : le retirer de la source ne le retire pas des vidéos déjà publiées.
- Les vidéos publiées avant cette décision n'ont pas de son réutilisable (pas d'extraction rétroactive).

## Liens
- [ADR-062](ADR-062-creation-video-facon-tiktok.md), [ADR-052](ADR-052-enregistrement-edition-video.md), [ADR-016](ADR-016-perimetre-mvp.md), [ADR-012](ADR-012-traitement-asynchrone.md), [ADR-029](ADR-029-blocage-filtrage-contenus.md)
