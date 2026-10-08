# ADR-008 — Pipeline vidéo HLS inspiré de Mux

## Statut
Accepté

## Contexte
Le feed doit rester fluide en scroll continu.
Les App Store Review Guidelines (2.5.7) imposent HLS pour la vidéo diffusée sur réseau cellulaire au-delà de 10 minutes.
AVPlayer lit le HLS nativement, avec adaptation du débit au réseau.
L'API ne doit pas servir les octets vidéo.

## Décision
- Le worker transcode chaque vidéo en HLS multi-résolutions (par exemple 360p, 720p, 1080p) et génère une miniature.
- Cycle de statuts : `uploading` → `processing` → `ready` / `failed`.
- La fin du traitement est notifiée à l'application via WebSocket (ADR-011).
- La lecture passe uniquement par le CDN.
- MVP : vidéos publiques uniquement. URLs de lecture signées plus tard pour les vidéos privées.

## Alternatives
- Mux ou Cloudflare Stream : transcodage, stockage et CDN gérés, mais coût récurrent et dépendance à un tiers.
- HLS en une seule résolution : simple pour un POC, sans adaptation du débit.
- Téléchargement progressif MP4 : pas d'adaptation du débit, limité par les règles Apple.

## Conséquences
### Positives
- Débit adaptatif selon la connexion.
- API déchargée de la diffusion vidéo.
- Pipeline maîtrisé, sans coût par vidéo.

### Négatives
- Un pipeline FFmpeg multi-résolutions à construire et à maintenir.
- Un délai entre la fin de l'upload et la disponibilité de la vidéo.
- Les vidéos privées ne sont pas couvertes au MVP.

## Liens
- ADR-007 — Upload vidéo direct
- ADR-011 — Temps réel
- ADR-012 — Traitement asynchrone
- ADR-015 — Hébergement
- Complété par [ADR-040](ADR-040-duree-maximale-video.md) — Durée maximale d'une vidéo : 3 minutes
- Complété par [ADR-047](ADR-047-tone-mapping-hdr.md) — Tone mapping des vidéos HDR
- Complété par [ADR-051](ADR-051-stories.md) — Stories
