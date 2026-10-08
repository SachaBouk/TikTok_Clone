# ADR-050 — Cadeaux en jetons

## Statut
Accepté

Complète [ADR-016](ADR-016-perimetre-mvp.md) (périmètre) et [ADR-009](ADR-009-paiement-jetons.md) (jetons), sans les remplacer : la dépense des jetons, reportée par l'ADR-016, entre dans le périmètre (décision du développeur). L'ADR-016 la prévoyait « en live » ; elle arrive d'abord **sur les vidéos**. Le Live (plus tard) réutilisera la même dépense.

## Contexte
Depuis l'ADR-009 et l'ADR-021, on peut acheter des jetons. L'API tient le solde (`wallets.balance`), crédité par le webhook RevenueCat, avec un journal des mouvements (`wallet_transactions`). Mais les jetons n'ont encore aucun usage.

L'ADR-009 prévoit déjà que la dépense soit vérifiée et débitée par l'API, puis enregistrée dans `GIFT_SENT`. La table `gifts_sent` existe depuis la migration initiale (expéditeur, destinataire, montant > 0), mais n'est jamais écrite. À la suppression d'un compte, ses lignes sont gardées et anonymisées (`SET NULL`).

Le développeur lève la réserve de l'ADR-016 et exclut tout retrait d'argent.

## Décision
### Ce que reçoit le créateur
- **Des gains à part, non dépensables** (choix du développeur, comme les « diamants » de TikTok) : `wallets.earned`, total des jetons reçus en cadeaux. Il s'affiche dans le portefeuille avec l'historique des cadeaux reçus. Il ne s'ajoute pas au solde, ne se dépense pas et ne se retire pas.
- Le solde (`balance`) ne contient donc que des jetons achetés : pas de circuit fermé achat → cadeau à un second compte → dépense. Un remboursement après un cadeau reste plafonné à 0, comme aujourd'hui (ADR-021) ; les gains du créateur ne sont pas repris.

### Catalogue
- **Dans le code de l'API** (choix du développeur, `wallet/domain/gift-catalog.ts`) : un code, un nom, un emoji, un prix.
  - Rose 🌹 1 jeton, Cœur ❤️ 5, Étoile ⭐ 10, Couronne 👑 50, Fusée 🚀 100, Diamant 💎 500.
  - Publié par `GET /gifts/catalog` (public).
- Chaque cadeau envoyé garde son code et le prix payé : un changement de catalogue ne réécrit pas l'historique. Un code retiré depuis s'affiche « 🎁 Cadeau ».

### Envoi
- **Route** : `POST /videos/:id/gifts` (compte connecté) avec `{ gift, clientGiftId }`. Elle répond **201** avec le cadeau, le **nouveau solde** et la date.
- **Identifiant d'envoi** (`clientGiftId`, UUID choisi par l'app, comme `clientMessageId` de l'ADR-044) :
  - un renvoi avec le même identifiant rend le cadeau déjà créé, sans débiter deux fois ;
  - le même identifiant pour une autre vidéo ou un autre cadeau donne **409** ;
  - index unique `(sender_id, client_gift_id)`.
- **Règles**, dans cet ordre :
  - vidéo publiée, auteur ni suspendu, ni bloqué dans un sens ou dans l'autre. Sinon **404** (vidéo indisponible) ou **403** (blocage), comme les réactions ;
  - pas sur sa propre vidéo (**400**) ;
  - cadeau du catalogue (**400** sinon) ;
  - limite de débit ;
  - solde suffisant (**402** « Solde insuffisant »).
- **Atomicité** (`PrismaWalletRepository.sendGift`), dans une seule transaction :
  - portefeuilles des deux comptes créés si besoin, puis verrouillés **dans l'ordre des identifiants** (`FOR UPDATE`), pour éviter l'interblocage de deux cadeaux croisés ;
  - solde de l'expéditeur vérifié puis débité, gains du destinataire crédités ;
  - ligne `gifts_sent` écrite.
  - CHECK ajoutés à la main : gains ≥ 0, code non vide, solde après ≥ 0.
- **`gifts_sent` complétée** : `gift_code`, `video_id` (`SET NULL` à la suppression de la vidéo : l'historique reste), `client_gift_id`, `sender_balance_after`.
- **Limite de débit** (ADR-039, `GIFT_RATE_LIMITS`) : 30 cadeaux par minute et 500 par jour et par compte. **Seuls les cadeaux envoyés comptent** (`check` puis `hit`) : un solde insuffisant ne consomme rien. Au-delà, **429** avec `Retry-After`.
- **Après l'envoi**, au mieux et sans faire échouer la requête :
  - `walletUpdated` (`{ balance, earned }`) aux deux comptes ;
  - notification au créateur.

### Visibilité
- **Le créateur seulement** (choix du développeur) : rien de public sur la vidéo, aucun champ nouveau dans l'élément du feed.
- **Notification « cadeau »** (nouvelle valeur `gift` de `notification_type`), avec le code et le prix **copiés** (`gift_code`, `gift_amount`) : le module `notifications` ne lit pas les tables du portefeuille (ADR-003).
  - Regroupée **par vidéo**, comme les likes (clé `gift:<videoId>`), mais une notification par cadeau (pas d'index unique). Le nombre du groupe compte les cadeaux, et ses auteurs affichés sont **distincts** : un compte peut en envoyer plusieurs.
  - En direct (`notificationCreated`) et en push (« Léa t'a envoyé 🌹 Rose »).
  - Supprimée avec la vidéo ou le compte de l'expéditeur, comme les autres (ADR-043). Le cadeau, lui, reste.

### Portefeuille et historique
- `GET /wallet` : `{ balance, earned }`.
- `GET /wallet/transactions` ajoute les **cadeaux envoyés** (sorte `giftSent`, montant négatif, solde après, cadeau et destinataire) aux achats, remboursements et ajustements. Les deux tables sont fusionnées par identifiant (UUID v7), avec le même curseur.
- `GET /wallet/gifts/received` : **cadeaux reçus**, du plus récent au plus ancien (expéditeur, cadeau, prix, vidéo). Un expéditeur supprimé apparaît comme « compte supprimé ».

### Frontières (ADR-003)
Le module `wallet` reste propriétaire des soldes et de `gifts_sent`. Il passe par :
- `VideosService` pour la vidéo publiée et son auteur ;
- `InteractionsService` pour le masquage et les blocages ;
- `NotificationsService.notifyGift` pour la notification ;
- `UsersService` pour les comptes.

Aucun de ces modules ne dépend de `wallet` (seul `admin` le lit) : pas de cycle.

### Backoffice (lecture seule, comme l'ADR-032)
- `GET /admin/gifts?userId=&cursor=&limit=` : journal des cadeaux (envoyés ou reçus par un compte, ou tous), avec expéditeur, destinataire, vidéo, cadeau, prix et solde après.
- Statistiques : jetons dépensés en cadeaux (total et sur 7 jours) et gains totaux.
- Fiche d'un compte : gains, en plus du solde.
- Page « Cadeaux » et lien depuis la fiche d'un compte.

### App iOS
- **Bouton cadeau** 🎁 dans la colonne du lecteur (feed, lecteur d'une grille, vidéo seule), absent sur ses propres vidéos. En invité, il ouvre la connexion.
- **Feuille de cadeaux** :
  - solde et bouton « Recharger » (ouvre le paywall) ;
  - grille du catalogue (emoji, nom, prix) ; un cadeau trop cher propose de recharger ;
  - « Envoyer ». Pas d'optimisme : on attend la réponse de l'API, puisque de l'argent est en jeu.
- **Animation SwiftUI sobre** (choix du développeur), chez l'expéditeur seulement : l'emoji grossit et monte au-dessus de la vidéo, avec « Rose envoyée à @x ». Aucune dépendance nouvelle.
- **Portefeuille** : gains « Jetons reçus », historique en deux listes (« Mouvements », « Cadeaux reçus »).
- **Centre d'activité** : notifications « cadeau », regroupées par vidéo.
- **Mesure d'audience** (ADR-013) :
  - `gift_sent` (code, prix, vidéo, auteur) ;
  - `paywall_viewed` avec la nouvelle source `gift`.

## Alternatives
- **Jetons dépensables pour le créateur (100 % ou 50 %)** : les jetons circuleraient entre comptes, le solde ne correspondrait plus aux achats, et un achat remboursé après un cadeau laisserait les jetons chez le créateur. Écarté par le développeur.
- **Catalogue dans une table, géré au backoffice** : modifiable sans déploiement, mais une table, des routes d'administration et des visuels à héberger en plus. Écarté par le développeur.
- **Animations Lottie** : plus riches, mais une dépendance et des fichiers d'animation (droits). Écarté par le développeur. **Pas d'animation** : écarté.
- **Compteur public de cadeaux sur la vidéo** : un compteur dénormalisé et un champ du feed en plus. Écarté par le développeur.
- **Dépense dans `wallet_transactions`** (sorte `gift`) : le journal est taillé pour les événements RevenueCat (identifiant d'événement unique, client, store, environnement obligatoires). Écarté au profit de `gifts_sent`, prévue par l'ADR-009, fusionnée à la lecture.
- **Verrouiller le seul portefeuille de l'expéditeur** : deux cadeaux croisés (A → B et B → A) pourraient s'interbloquer en prenant les verrous dans l'ordre inverse. Écarté : verrous dans l'ordre des identifiants.
- **Débit optimiste dans l'app** : une erreur afficherait un solde faux. Écarté pour une dépense.

## Conséquences
### Positives
- Les jetons achetés servent enfin, avec une dépense atomique, idempotente et limitée.
- Le solde reste fait de jetons achetés, rapprochable avec RevenueCat ; les gains sont à part.
- Le Live pourra réutiliser la même dépense (`video_id` facultatif).

### Négatives
- Les gains ne servent à rien d'autre qu'à être affichés (pas de retrait, choix du développeur).
- Un changement de catalogue demande un déploiement de l'API et une version de l'app pour les nouveaux visuels (l'app affiche l'emoji reçu de l'API).
- Un remboursement après un cadeau ne reprend pas les gains du créateur.
- Pas de remboursement d'un cadeau (envoi définitif), ni d'annulation.
- Les cadeaux ne se voient pas publiquement.

## Liens
- ADR-003 — Architecture backend
- ADR-009 — Paiement et jetons
- ADR-013 — Analytics et A/B testing
- ADR-016 — Périmètre du MVP
- ADR-021 — Portefeuille : journal et règles de crédit
- ADR-029 — Blocage : contenus masqués
- ADR-032 — Backoffice : portefeuille
- ADR-039 — Limites de débit
- ADR-043 — Notifications supprimées en direct
- ADR-044 — Identifiant d'envoi
