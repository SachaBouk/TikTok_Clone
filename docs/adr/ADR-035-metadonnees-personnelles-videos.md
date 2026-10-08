# ADR-035 — Métadonnées personnelles des vidéos retirées dans l'app

## Statut
Accepté

Complète [ADR-007](ADR-007-upload-video-direct.md), sans le remplacer.

## Contexte
L'app envoie le fichier d'origine de la galerie (`PhotosPicker`, `preferredItemEncoding: .current`) directement au stockage (ADR-007). Une vidéo d'iPhone porte des métadonnées QuickTime qui identifient la personne : la position GPS du tournage (`com.apple.quicktime.location.ISO6709`), le modèle de l'appareil, la date. Le sélecteur d'iOS 27 propose « Lieu inclus », activé par défaut.

Vérifié avec le vrai code du worker (FFmpeg 8) : aucun fichier publié (segments HLS, manifestes, miniature JPEG) ne reprend ces métadonnées. Le **brut**, en revanche, les gardait. Il est conservé indéfiniment dans `videos-raw` pour pouvoir retranscoder. Rien n'était public, mais le projet stockait une donnée personnelle dont il n'a aucun usage, ce qui est contraire au principe de minimisation du RGPD. Le relevé de l'étape 4 l'avait noté (`docs/bilan-mvp.md`, constat 5).

## Décision
- **L'app retire ces métadonnées avant l'envoi**, dès l'import depuis la galerie, pendant la « Préparation de la vidéo… » du brouillon. La position ne quitte jamais le téléphone : ni le réseau, ni le stockage, ni l'hébergeur ne la voient.
- **Moyen** : ré-écriture sans réencodage (`AVAssetExportSession`, préréglage `AVAssetExportPresetPassthrough`) avec le filtre de partage d'AVFoundation (`AVMetadataItemFilter.forSharing()`). Il retire la position et les autres métadonnées qui identifient la personne, et garde ce qui sert à la lecture (rotation, couleurs HDR). La sortie est toujours en QuickTime (`.mov`, `video/quicktime`), qui accepte tous les codecs d'iPhone (HEVC, ProRes).
- **Port du domaine** `VideoMetadataCleaner`, adaptateur `AVFoundationVideoMetadataCleaner` (ADR-002), cas d'usage `PrepareVideoUseCase`. Une vidéo qu'on ne sait pas ré-écrire est **refusée** (« Impossible de préparer cette vidéo. ») plutôt qu'envoyée telle quelle.
- **Le seed** (`pnpm seed`) applique la même règle aux vidéos de `seed/videos/` : copie par FFmpeg sans réencodage (`-c copy -map_metadata -1 -map_chapters -1`, pistes vidéo et son seulement). La rotation, portée par la piste, est gardée.
- **Le serveur ne ré-écrit pas le brut** : l'app est le seul client.
- L'écran « Publier » l'annonce : « La vidéo est publiée telle quelle, sans sa position. »

## Alternatives
- **Retrait par le worker** (ré-écriture du brut avant le transcodage) : protège quel que soit le client. Mais la position transite et reste stockée jusqu'au traitement, et le worker se met à écrire dans `videos-raw`, avec l'idempotence des relances à gérer. Rejeté tant que l'app est le seul client.
- **Retrait dans l'app et dans le worker** : plus de code et de tests pour un seul client aujourd'hui. Rejeté pour l'instant ; à reconsidérer avec un deuxième client (Android, web).
- **Ne plus garder le brut après le transcodage** : ne règle pas le transit de la position, et empêche de retranscoder. Rejeté.
- **Laisser l'utilisateur choisir** (« Lieu inclus » du sélecteur) : la position n'est jamais utilisée par l'app ; la retirer d'office est plus simple et plus sûr. Rejeté.

## Conséquences
### Positives
- Aucune position, ni aucun modèle d'appareil, dans le stockage.
- Aucun réencodage : la qualité d'origine est gardée, et la préparation ne prend que le temps de recopier le fichier.

### Négatives
- Le fichier est recopié à l'import : quelques secondes pour une grosse vidéo, et le double d'espace disque le temps de la copie.
- La date de création du brut devient celle de la préparation.
- Un autre client devra appliquer la même règle, ou il faudra ajouter le retrait côté serveur.
- Vérifié avec des vidéos de synthèse au format d'un iPhone (position QuickTime, rotation), pas encore avec une vidéo tournée sur un vrai iPhone : les pistes de métadonnées temporelles (`mebx`) d'un vrai fichier sont à contrôler.

## Liens
- ADR-002 — Architecture mobile
- ADR-007 — Upload vidéo direct
- ADR-008 — Pipeline vidéo HLS
- ADR-016 — Périmètre de la première version (publication sans édition)
- Complété par [ADR-052](ADR-052-enregistrement-edition-video.md) — Enregistrement et édition vidéo dans l'app
