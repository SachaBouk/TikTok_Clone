# ADR-021 — Portefeuille : journal et règles de crédit

## Statut
Accepté

Complète [ADR-009](ADR-009-paiement-jetons.md), sans le remplacer.

## Contexte
L'ADR-009 fixe le principe : RevenueCat valide l'achat et prévient le backend par webhook, `WALLET` reste la source de vérité du solde. Il ne dit pas comment éviter un double crédit, ni comment traiter remboursements, achats de test et acheteurs inconnus.

## Décision
- Le backend applique les événements **`VIRTUAL_CURRENCY_TRANSACTION`** du webhook (monnaie virtuelle de RevenueCat) : achat (montant positif), remboursement (négatif), ajustement depuis le tableau de bord RevenueCat. Les autres événements et monnaies sont ignorés.
- **Journal `WALLET_TRANSACTION`** : une ligne par événement appliqué, avec l'identifiant de l'événement RevenueCat **unique**. Un webhook rejoué ne crédite pas deux fois. Chaque ligne garde le montant annoncé, le montant appliqué, le solde après, le produit, le store et l'environnement.
- Application **atomique** : ligne du portefeuille verrouillée, solde et journal écrits dans la même transaction.
- **Remboursement** : jamais sous 0, comme RevenueCat ; si des jetons ont été dépensés, seul le reste est retiré.
- **Acheteur** : l'app s'identifie chez RevenueCat avec l'UUID du compte ; le backend le cherche aussi parmi les alias. **Acheteur inconnu** : la ligne est gardée sans compte, pour un rapprochement à la main.
- **Achats de test (sandbox)** crédités par défaut (développement, TestFlight) ; une variable (`REVENUECAT_REJECT_SANDBOX`) les refuse en production.
- **Suppression du compte** : le portefeuille disparaît, le journal reste, anonymisé.
- Webhook authentifié par l'en-tête `Authorization` configuré dans RevenueCat, hors du contrat OpenAPI. Le solde à jour est poussé à l'app en temps réel.
- Côté app : le SDK RevenueCat n'est configuré qu'à l'ouverture du paywall, avec l'UUID du compte ; après un achat, l'app attend le crédit (temps réel, sinon relecture du solde).

## Alternatives
- Table des seuls achats : les remboursements et les futurs cadeaux auraient chacun leur table. Journal unique retenu.
- Événements `NON_RENEWING_PURCHASE` avec un barème de packs dans le backend : deux endroits où fixer les montants. Montants de la monnaie virtuelle RevenueCat retenus.
- Crédit déclenché par l'app après l'achat : falsifiable. Rejeté.
- Journal supprimé avec le compte : perd la trace nécessaire au rapprochement. Rejeté.

## Conséquences
### Positives
- Idempotence garantie par la base, y compris sous des livraisons simultanées.
- Historique complet des mouvements, pour l'utilisateur et pour le rapprochement.

### Négatives
- Le crédit dépend de la réception du webhook (déjà relevé par l'ADR-009) ; en local, il faut un tunnel pour recevoir les vrais webhooks.
- Le solde RevenueCat divergera de celui du backend quand les cadeaux seront dépensés côté backend.

## Liens
- ADR-009 — Paiement et jetons
- ADR-020 — Modèle de données : compléments
- Complété par [ADR-031](ADR-031-signature-webhook-revenuecat.md) — Signature HMAC du webhook RevenueCat
