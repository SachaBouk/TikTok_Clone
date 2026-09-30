# ADR-023 — Files asynchrones : compléments

## Statut
Accepté

Complète [ADR-012](ADR-012-traitement-asynchrone.md), sans le remplacer.

## Contexte
L'ADR-012 prévoit une file BullMQ, `video-transcode`, consommée par le worker. D'autres traitements ont eu besoin d'être asynchrones ou relancés.

## Décision
- **`video-transcode-results`** : le worker y publie ses résultats (`ready`, ou `failed` après la dernière tentative). **L'API est seule à écrire en base** : le worker n'accède jamais à PostgreSQL.
- **`video-cleanup`**, produite et consommée par l'API : suppression des fichiers d'une vidéo (brut, HLS, miniature) après sa suppression. Programmée **avant** la suppression en base, avec 30 s de délai, et sans effet si la vidéo existe encore.
- **`push-notifications`**, produite et consommée par l'API : un job par appareil, pour ne pas ralentir la requête qui déclenche l'envoi.
- **Maintenance** (job planifié toutes les 15 minutes, exécuté une seule fois même avec plusieurs instances) : suppression des envois jamais confirmés après 24 h, republication des vidéos bloquées en traitement depuis plus d'une heure.
- Transcodage : 3 tentatives ; nettoyage : 5 ; push : 3. Backoff exponentiel. Un fichier illisible échoue aussitôt, sans relance.

## Alternatives
- Le worker écrit lui-même le statut en base : il faudrait lui donner l'accès à PostgreSQL et dupliquer le modèle. Rejeté.
- Supprimer les fichiers pendant la requête : lent, et un échec du stockage laisserait la vidéo à moitié supprimée. Rejeté.
- Tâches planifiées hors de BullMQ (cron système) : exécutions en double avec plusieurs instances. Rejeté.

## Conséquences
### Positives
- Un seul écrivain en base ; résultats gardés dans Redis si l'API est arrêtée.
- Aucune vidéo ni aucun fichier perdu si une étape échoue.

### Négatives
- Des jobs en échec définitif (nettoyage épuisé) demandent une intervention manuelle.
- Un CDN garde en cache les fichiers déjà servis : il faudra une purge en production.

## Liens
- ADR-012 — Traitement asynchrone avec BullMQ
- ADR-008 — Pipeline vidéo HLS
- ADR-025 — Rôle de Redis
