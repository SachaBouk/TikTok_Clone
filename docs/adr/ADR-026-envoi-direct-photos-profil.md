# ADR-026 — Envoi direct des photos de profil

## Statut
Accepté

Complète [ADR-007](ADR-007-upload-video-direct.md), sans le remplacer.

## Contexte
L'ADR-007 fait envoyer les vidéos directement au stockage objet par URL pré-signée. Les photos de profil posent la même question, avec des fichiers petits mais non traités par un worker.

## Décision
- **Bucket `avatars`**, en lecture anonyme des seuls objets (pas de listage), servi par le CDN en production.
- **Un seul PUT signé** (pas de multipart), URL valable 15 minutes, clé `<userId>/<avatarId>`.
- **Type et taille signés** dans l'URL : le stockage refuse un autre fichier.
- L'app recadre en carré (512 px) et encode en JPEG ou PNG, 5 Mio au plus ; **aucun traitement côté serveur**.
- À la confirmation, l'API revérifie le type, la taille et les premiers octets du fichier (signature JPEG ou PNG). Un fichier invalide est supprimé.
- Après chaque changement, les autres fichiers du compte (ancienne photo, envois abandonnés) sont supprimés.

Pour les vidéos, l'app garde l'état de chaque envoi multipart et le **reprend après une relance** (ADR-017).

## Alternatives
- Envoi de la photo à l'API : simple, mais l'API reçoit des fichiers, ce que l'ADR-007 évite. Rejeté.
- Redimensionnement côté serveur : une bibliothèque d'image et un traitement de plus. Rejeté pour la première version.
- Multipart comme les vidéos : inutile pour 5 Mio au plus. Rejeté.

## Conséquences
### Positives
- Même principe que les vidéos : l'API ne reçoit aucun octet.
- Un fichier qui n'est pas une image est refusé, même si l'URL est détournée.

### Négatives
- Les dimensions de l'image ne sont pas vérifiées.
- Un envoi jamais confirmé reste stocké jusqu'au prochain changement de photo du compte.

## Liens
- ADR-007 — Upload vidéo direct via URL pré-signée
- ADR-015 — Hébergement
- ADR-017 — Application iOS : choix d'implémentation
