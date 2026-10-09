# ADR-015 — Hébergement : indépendance vis-à-vis de l'hébergeur

## Statut
Accepté

## Contexte
L'hébergeur n'est pas encore choisi.
Besoins identifiés : PostgreSQL et Redis managés, un worker FFmpeg capable d'exécuter des traitements longs, un stockage objet avec CDN, et l'hébergement du backoffice Next.js.

## Décision
Le choix de l'hébergeur est différé. En attendant, le projet reste indépendant de l'hébergeur :
- tout est dockerisé ;
- le stockage passe par une interface compatible S3 (MinIO en local, S3 ou R2 en production).

Critères pour le choix final :
- PostgreSQL et Redis managés ;
- worker sur un environnement acceptant les jobs longs (pas de serverless pour lui) ;
- stockage objet avec CDN (R2 n'a pas de frais de sortie de données) ;
- le backoffice Next.js peut être hébergé sur Vercel.

## Alternatives
- Candidats identifiés, non départagés : Railway, Fly.io, AWS.

## Conséquences
### Positives
- Aucune décision irréversible à ce stade.
- Environnement de développement local complet via Docker.

### Négatives
- La configuration de déploiement reste à écrire.
- Le choix devra être tranché avant la mise en production.

## Liens
- ADR-003 — Architecture backend
- ADR-007 — Upload vidéo direct
- ADR-012 — Traitement asynchrone
- Complété par [ADR-027](ADR-027-images-docker.md) — Images Docker des applications
- Complété par [ADR-053](ADR-053-live-comparaison-diffusion.md) — Live (serveur LiveKit)
