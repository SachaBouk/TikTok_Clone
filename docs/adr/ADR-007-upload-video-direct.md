# ADR-007 — Upload vidéo direct via URL pré-signée

## Statut
Accepté

## Contexte
Faire transiter les vidéos par l'API bloquerait des connexions et de la mémoire pendant toute la durée de l'upload, et ralentirait les autres requêtes (feed, likes).
Retour de l'intervenant : alléger l'API principale pour l'upload, en s'inspirant de Mux et Cloudflare.

## Décision
- `POST /videos/upload-url` génère une URL pré-signée temporaire et crée la vidéo en statut `uploading`.
- L'application iOS envoie le fichier directement au stockage objet (PUT), en multipart pour les gros fichiers afin de reprendre après une coupure.
- La fin de l'upload est notifiée (`PATCH /videos/:id/uploaded`), ce qui déclenche le transcodage (ADR-012).
- L'API ne reçoit aucun octet vidéo.

## Alternatives
- Upload via l'API (client → NestJS → stockage) : simple, mais l'API absorbe la bande passante et la durée de chaque upload. Rejeté.
- Direct Upload de Mux ou Cloudflare Stream : tout est délégué, mais coût récurrent et dépendance à un tiers. Rejeté au profit d'un pipeline maison inspiré de ces services (ADR-008).

## Conséquences
### Positives
- L'API ne traite que des métadonnées.
- La charge de l'upload est portée par le stockage objet.

### Négatives
- Les uploads abandonnés laissent des vidéos en statut `uploading` à nettoyer.
- La sécurité repose sur la génération et la durée de validité des URLs signées.

## Liens
- ADR-008 — Pipeline vidéo
- ADR-012 — Traitement asynchrone
- ADR-015 — Hébergement
- Complété par [ADR-026](ADR-026-envoi-direct-photos-profil.md) — Envoi direct des photos de profil
