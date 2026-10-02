# ADR-040 — Durée maximale d'une vidéo

## Statut
Proposé

Complète [ADR-007](ADR-007-upload-video-direct.md) et [ADR-008](ADR-008-pipeline-video-hls.md), sans les remplacer.

## Contexte
L'ADR-007 limite la taille d'un envoi (1 Gio), pas sa durée. Une vidéo très longue mais peu volumineuse passait donc : le worker la transcodait en trois résolutions, ce qui pouvait l'occuper de longues minutes, et le stockage HLS grossissait d'autant. Le format de l'app est celui des vidéos courtes (ADR-016).

L'API ne reçoit aucun octet vidéo (ADR-007) : elle ne peut pas mesurer la durée. Seuls l'app (avant l'envoi) et le worker (avant le transcodage) le peuvent.

## Décision
Choix du développeur, parmi les options proposées :
- **3 minutes au plus**, à une seconde près pour les arrondis du conteneur (une vidéo affichée « 3:00 » dure souvent un peu plus de 180 s).
- **Vérifiée dans l'app et dans le worker** :
  - l'app mesure la vidéo choisie dans la galerie et la refuse aussitôt, avant tout envoi : « Cette vidéo dure plus de 3 minutes. Choisis-en une plus courte. » Une durée illisible est laissée au worker ;
  - le worker revérifie juste après l'analyse (`probe`), avant tout transcodage, contre un client modifié ou un script. Une vidéo trop longue lève `InvalidMediaError` : échec définitif immédiat, sans relance, comme un fichier illisible (ADR-012).
- **Motif non exposé** : la vidéo passe en `failed`, et son auteur voit « Échec du traitement », comme pour tout fichier invalide. Le motif précis n'est que dans les journaux du worker et de l'API. Avec le contrôle de l'app, ce cas n'arrive qu'avec un client modifié.

La règle existe en deux exemplaires, qui doivent rester identiques : `apps/worker/src/media/rules.ts` (`MAX_VIDEO_DURATION_SECONDS`) et `UploadRules.maxDuration` dans l'app.

## Alternatives
- **10 minutes** (envoi depuis la galerie de TikTok aujourd'hui) ou **60 minutes** : plus de liberté, mais des transcodages bien plus longs et un stockage plus coûteux. Écarté.
- **Worker seulement** : un seul endroit, mais la vidéo est envoyée en entier avant d'être refusée (jusqu'à 1 Gio pour rien). Écarté.
- **App seulement** : contournable ; le worker transcoderait quand même. Écarté.
- **Motif précis** (colonne `failure_reason`, exposée dans l'API et l'app) : plus clair, mais touche la base, le contrat, le worker et l'app pour un cas rare. Écarté.
- **Couper la vidéo à 3 minutes** au lieu de la refuser : la fin serait perdue sans que l'auteur l'ait choisi, et l'ADR-016 exclut l'édition. Écarté.

## Conséquences
### Positives
- Le temps de transcodage et le stockage d'une vidéo sont bornés.
- La personne apprend tout de suite, avant l'envoi, que sa vidéo est trop longue.

### Négatives
- Une vidéo de plus de 3 minutes doit être raccourcie hors de l'app (pas d'édition, ADR-016).
- Deux copies de la règle à garder alignées (worker et app).
- Une vidéo refusée par le worker ne dit pas pourquoi à son auteur.

## Liens
- ADR-007 — Upload direct des vidéos
- ADR-008 — Pipeline vidéo HLS
- ADR-012 — Traitement asynchrone
- ADR-016 — Périmètre
