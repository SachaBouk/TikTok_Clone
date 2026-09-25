# ADR-013 — Analytics et A/B testing avec PostHog

## Statut
Accepté

## Contexte
L'application doit intégrer des analytics et de l'A/B testing.
Métriques clés : taux de complétion, durée de visionnage, moment du swipe, engagement (likes, commentaires, partages), rétention D1 / D7 / D30, funnel d'onboarding.

## Décision
PostHog : un seul SDK iOS pour les événements, les feature flags et les expériences A/B.
Hébergement cloud (EU) ou auto-hébergé, selon l'hébergement retenu (ADR-015).

## Alternatives
- Firebase Analytics : gratuit, mature, aucune infrastructure à gérer, mais données sur l'infrastructure Google.
- Amplitude : analyse comportementale plus poussée, mais A/B testing en option payante séparée.

## Conséquences
### Positives
- Une seule intégration pour deux besoins (analytics et A/B testing).
- Données hébergeables en Europe ou chez soi.

### Négatives
- En auto-hébergement, une brique d'infrastructure de plus à maintenir.

## Liens
- ADR-004 — Architecture backoffice (dashboard)
- ADR-015 — Hébergement
