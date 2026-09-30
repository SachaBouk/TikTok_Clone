# ADR-009 — Paiement et jetons avec RevenueCat

## Statut
Accepté

## Contexte
TikTok n'a pas d'abonnement plateforme : la monétisation repose sur des jetons achetés et des cadeaux envoyés en live.
Un cadeau transfère des jetons d'un utilisateur à un autre.

## Décision
- RevenueCat (virtual currency) gère l'achat des packs de jetons (produits consommables).
- RevenueCat valide l'achat auprès de l'App Store, puis envoie un webhook au backend.
- Le backend crédite le `WALLET` en PostgreSQL, qui reste la source de vérité du solde.
- La dépense des jetons (cadeaux) est vérifiée et débitée côté backend, puis enregistrée dans `GIFT_SENT`.

## Alternatives
- Solde géré uniquement par RevenueCat : les transferts entre utilisateurs sortent de RevenueCat et le solde se désynchroniserait. Rejeté.
- Modèle d'abonnement (`SUBSCRIPTION`) : ne correspond pas au modèle de TikTok. Rejeté.

## Conséquences
### Positives
- Validation des achats déléguée à RevenueCat.
- Logique des cadeaux entièrement maîtrisée côté backend.

### Négatives
- Deux systèmes à garder cohérents (RevenueCat et `WALLET`).
- Le crédit des soldes dépend de la réception du webhook RevenueCat.

## Liens
- ADR-006 — Persistance
- Complété par [ADR-021](ADR-021-portefeuille-journal-credit.md) — Portefeuille : journal et règles de crédit
