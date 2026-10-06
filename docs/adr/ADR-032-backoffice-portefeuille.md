# ADR-032 — Backoffice : portefeuille et journal des jetons

## Statut
Accepté

Complète [ADR-019](ADR-019-backoffice-role-perimetre-session.md), sans le remplacer.

## Contexte
L'ADR-019 limite le backoffice aux comptes, vidéos et commentaires. Le portefeuille (ADR-009, ADR-021) n'était visible qu'en base : ni le solde d'un compte, ni ses mouvements, ni les jetons vendus. Surtout, les achats d'un client inconnu de l'API, gardés « pour rapprochement », n'étaient visibles nulle part.

## Décision
- **Lecture seule** : le backoffice affiche le portefeuille, mais ne le modifie pas. Un crédit ou un débit manuel passe par un ajustement dans le tableau de bord RevenueCat, qui revient par le webhook : RevenueCat et l'API restent d'accord.
- **Comptes** : le solde de jetons figure dans la liste et sur la fiche d'un compte, avec ses 10 derniers mouvements.
- **Tableau de bord** : jetons vendus en production (total et 7 derniers jours), et une alerte s'il y a des mouvements à rapprocher.
- **Page « Jetons »** :
  - totaux de production : vendus, remboursés, ajustés, et en circulation (somme des soldes) ;
  - achats de test (sandbox) comptés à part, car ils ne sont jamais payés ;
  - journal complet, filtrable par compte ou « à rapprocher ».
- **Jetons vendus** : c'est le montant **annoncé** par RevenueCat, clients inconnus compris, puisque le store a encaissé. Le montant appliqué au solde est affiché à part quand il diffère (remboursement plafonné au solde, client inconnu).
- **« À rapprocher »** : mouvement sans portefeuille touché (`balance_after` nul). Une ligne anonymisée par la suppression d'un compte garde son solde après : elle apparaît comme « Compte supprimé », pas « à rapprocher ».
- **Identifiants exposés aux administrateurs** : l'événement RevenueCat, la transaction du store et l'identifiant client RevenueCat, pour retrouver un achat chez RevenueCat ou chez Apple. Ils ne sont jamais exposés à l'app.
- **API** : `GET /admin/wallet-transactions?userId=&unmatched=&cursor=&limit=`, `tokenBalance` dans les comptes, `tokens` dans `GET /admin/stats`. Le tout passe par `WalletService`, sans que le module `admin` lise la table (ADR-003).

## Alternatives
- **Créditer ou débiter depuis le backoffice** : l'API divergerait de RevenueCat, qui tient aussi un solde. Rejeté ; l'ajustement RevenueCat fait la même chose et reste cohérent.
- **Jetons vendus = montants appliqués** : sous-estime les ventes quand le client est inconnu (0 appliqué alors que le store a encaissé). Rejeté.
- **Chiffre d'affaires en euros** : le journal ne garde pas le prix payé ; il faudrait l'API RevenueCat ou App Store Connect. Reporté (les chiffres de vente restent dans RevenueCat).

## Conséquences
### Positives
- Un achat mal rattaché se voit tout de suite, avec de quoi le retrouver chez RevenueCat.
- Le support peut répondre à « je n'ai pas reçu mes jetons » sans accès à la base.

### Négatives
- Les totaux sont recalculés à chaque affichage (somme sur tout le journal) : à revoir si le journal devient très grand.
- Le filtre « à rapprocher » n'a pas d'index dédié (peu de lignes attendues).

## Liens
- ADR-004 — Architecture backoffice
- ADR-009 — Paiement et jetons avec RevenueCat
- ADR-019 — Backoffice : rôle administrateur, périmètre et session
- ADR-021 — Portefeuille : journal et règles de crédit
