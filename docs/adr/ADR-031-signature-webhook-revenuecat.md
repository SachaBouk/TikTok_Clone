# ADR-031 — Signature HMAC du webhook RevenueCat

## Statut
Accepté

Complète [ADR-021](ADR-021-portefeuille-journal-credit.md), sans le remplacer.

## Contexte
L'ADR-021 authentifie le webhook RevenueCat par l'en-tête `Authorization` configuré dans RevenueCat. C'est un secret fixe, envoyé tel quel à chaque appel : il ne protège pas le contenu de la requête, et reste valable indéfiniment s'il fuit (journaux d'un proxy, capture). Or ce webhook crédite des jetons achetés. RevenueCat propose aussi une signature HMAC de chaque envoi.

## Décision
- **Signature vérifiée** quand `REVENUECAT_WEBHOOK_SIGNING_SECRET` est configuré (16 caractères au moins). L'en-tête `X-RevenueCat-Webhook-Signature: t=<unix>,v1=<hex>` est un HMAC-SHA256 calculé avec le secret tel quel pour clé, sur `<t>.<corps brut>`, selon la documentation de RevenueCat.
- **Corps brut** : la signature porte sur les octets reçus. L'API garde donc le corps brut à côté du JSON lu (`rawBody` de NestJS). Un JSON relu puis réécrit ne donnerait pas la même signature.
- **Fraîcheur** : `t` doit être à **5 minutes** au plus de l'horloge de l'API, dans les deux sens, comme le recommande RevenueCat. Celui-ci recalcule la signature à chaque envoi, relances comprises : la tolérance ne couvre que le décalage d'horloge et la durée de l'envoi. Un rejeu dans ce délai est sans effet, car l'événement est idempotent (ADR-021).
- **Comparaison en temps constant**. Si l'en-tête porte plusieurs `v1`, il suffit que l'une d'elles corresponde (rotation du secret).
- **Protections cumulables** : chaque protection configurée est exigée (`Authorization` et signature), 401 sinon ; sans aucune, 503 comme avant. La raison d'un refus (`missing`, `malformed`, `expired`, `mismatch`) est journalisée, jamais renvoyée. **En production : les deux.**

## Alternatives
- **Signature seule, en abandonnant l'en-tête** : suffisant en théorie, mais garder l'en-tête ne coûte rien et protège si le secret de signature n'est pas encore configuré. Les deux restent possibles.
- **Tolérance plus large** (couvrir les relances de 5 à 80 min) : inutile, puisque chaque relance est signée à nouveau, et cela allonge la fenêtre de rejeu. Rejeté.
- **Signature obligatoire au démarrage** : empêcherait de développer sans compte RevenueCat. Rejeté ; elle reste recommandée en production.

## Conséquences
### Positives
- Une requête modifiée, ancienne ou forgée sans le secret de signature est refusée, même si l'en-tête `Authorization` a fuité.
- Aucune dépendance nouvelle (HMAC de Node).

### Négatives
- L'API garde le corps brut de toutes les requêtes JSON pendant leur traitement (mémoire en plus, bornée par la taille maximale du corps).
- L'horloge du serveur doit être à l'heure (NTP), sinon les webhooks sont refusés.
- Simuler le webhook en local demande de signer la requête si le secret est configuré (voir `apps/ios/README.md`).

## Liens
- ADR-009 — Paiement et jetons avec RevenueCat
- ADR-021 — Portefeuille : journal et règles de crédit
