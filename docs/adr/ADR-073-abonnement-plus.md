# ADR-073 — Abonnement « Plus »

## Statut
Accepté

Complète [ADR-009](ADR-009-paiement-jetons.md) (RevenueCat, jetons), [ADR-016](ADR-016-perimetre-mvp.md) (périmètre), [ADR-050](ADR-050-cadeaux-jetons.md) (cadeaux), [ADR-040](ADR-040-duree-maximale-video.md) (durée des vidéos), [ADR-053](ADR-053-live-comparaison-diffusion.md) (durée des lives) et [ADR-003](ADR-003-architecture-backend.md) (modules), sans les remplacer.

## Contexte
Le développeur veut un **deuxième paywall** : un abonnement, mensuel ou annuel au choix, qui donne des avantages aux abonnés. Il a retenu cinq avantages parmi ceux proposés :
1. un **badge** à côté du pseudo ;
2. des **jetons offerts** chaque mois ;
3. des **cadeaux exclusifs** ;
4. des **vidéos et des lives plus longs** ;
5. des **icônes de l'app** au choix.

Les achats passent déjà par RevenueCat (SDK de l'app, webhook de l'API, Test Store en développement). L'API est la source de vérité du solde de jetons (ADR-009) : elle doit l'être aussi de l'abonnement, puisque trois avantages sur cinq se vérifient côté serveur (jetons, cadeaux, durées).

Écartés : statistiques des vidéos, modification après publication, publication programmée, limites relevées, visiteurs du profil (vie privée, ADR-070). Rien n'est retiré à ceux qui ne s'abonnent pas (ni publicité, ni qualité réduite).

## Décision
Choix du développeur : les cinq avantages et les valeurs proposées (nom, prix, montant des jetons, cadeaux, icônes).

### Nom
**« Plus »** et un badge **« + »** (rond rose, `brandPink`). Jamais « TikTok » : marque déposée, comme le logo (ADR-055).

### Produits RevenueCat
- Deux produits d'abonnement (Test Store en développement, App Store ensuite) : **`plus_monthly`** (4,99 € par mois) et **`plus_annual`** (39,99 € par an, environ 33 % d'économie).
- Une **entitlement** `plus`, accordée par les deux produits.
- Une **offre** `plus` (pas l'offre courante, qui reste celle des jetons), lue par son identifiant par l'app, avec les packages `$rc_monthly` et `$rc_annual`.

### État de l'abonnement (API, module `subscriptions`, nouveau)
- Table **`plus_subscriptions`** : `user_id` (clé, cascade), `product_id`, `period` (`monthly` | `annual`), `expires_at`, `will_renew`, `store`, `environment`, `updated_at`. Une ligne par compte, la dernière connue.
- **Mise à jour par le webhook RevenueCat** existant (`POST /webhooks/revenuecat`, même authentification, ADR-031) : les événements d'abonnement (`INITIAL_PURCHASE`, `RENEWAL`, `PRODUCT_CHANGE`, `CANCELLATION`, `UNCANCELLATION`, `EXPIRATION`, `BILLING_ISSUE`) ne sont pas appliqués tels quels. L'API **relit l'état du client chez RevenueCat** (`GET /v1/subscribers/{app_user_id}`, clé secrète `REVENUECAT_SECRET_API_KEY`, côté serveur seulement) et garde l'échéance de l'entitlement `plus`. Les webhooks peuvent arriver dans le désordre ou en double : relire l'état rend le traitement idempotent, sans ordre à reconstruire.
- **Abonné** = `expires_at` dans le futur. Une annulation laisse l'abonnement actif jusqu'à l'échéance ; un problème de paiement le laisse actif pendant la période de grâce annoncée par RevenueCat.
- **Achats de test** : même règle que les jetons (ADR-009, Test Store rangé en sandbox) ; avec `REVENUECAT_REJECT_SANDBOX=true`, ils n'ouvrent aucun abonnement.
- **Registre partagé** `src/plus/` (port `PlusMembers`, adaptateurs Redis et en mémoire, module global), sur le modèle des comptes suspendus (ADR-037) : la base fait foi, le registre est écrit à chaque changement et reconstruit au démarrage. Il est lu par `users`, `videos`, `live` et `wallet` **sans dépendance entre modules** : `users` dépend déjà de `videos`, qui ne peut pas dépendre d'un module qui dépendrait de `users`.
- `GET /users/me/plus` (connecté) → `{ active, period?, expiresAt?, willRenew? }`. Événement temps réel `plusChanged` (mêmes champs) à tous les appareils du compte.

### Avantages
1. **Badge « + »** : `UserSummaryDto.plus` (vrai pour un abonné), donc partout où un compte apparaît (profil, vidéos, commentaires, messages, chat des lives, listes) ; calculé par `UsersService` à partir du registre. Il disparaît à l'échéance.
2. **Jetons offerts** : accordés **par RevenueCat**, comme les packs (In-App Currencies, « Grant currency on ») : **150 jetons** à la souscription et à chaque renouvellement mensuel, **1 800 jetons** (12 × 150) à la souscription et à chaque renouvellement annuel. Ils arrivent par l'événement `VIRTUAL_CURRENCY_TRANSACTION` déjà traité. Nouvelle sorte `subscriptionGrant` dans le journal (produit `plus_*`), pour ne pas les compter comme des jetons vendus dans le backoffice. Ils vont dans le **solde** et se dépensent comme les autres.
3. **Cadeaux exclusifs** : deux cadeaux ajoutés au catalogue (ADR-050), réservés aux abonnés : 🦄 **Licorne** (20 jetons) et 🪐 **Planète** (200 jetons). `GET /gifts/catalog` les renvoie avec `plusOnly: true`. Les envoyer sans abonnement → **403** (`PlusRequiredError`), sur une vidéo comme dans un live. Un cadeau déjà envoyé reste acquis.
4. **Durées** :
   - vidéos de **10 minutes** au lieu de 3 (ADR-040). Le droit est lu au moment de `PATCH /videos/:id/uploaded`, et le job de transcodage porte la durée maximale (`maxDurationSeconds`) : le worker n'a pas à connaître l'abonnement. Taille maximale de l'envoi portée à **2 Gio** pour un abonné. Les stories restent à 60 s ;
   - lives de **4 heures** au lieu de 2 (ADR-053), durée fixée au lancement ;
   - une vidéo longue publiée reste en ligne après l'échéance.
5. **Icônes de l'app** : trois icônes de plus, dérivées du logo maison (**Or**, **Néon**, **Rétro**), au choix dans « Paramètres › Icône de l'app » (`UIApplication.setAlternateIconName`). Seul avantage vérifié par l'app seule (rien à protéger côté serveur) ; à l'échéance, l'icône d'origine revient au lancement suivant.

### App iOS
- **Paywall « Plus »** : depuis le menu ☰ (« Plus »), et depuis chaque avantage verrouillé (cadeau exclusif, vidéo trop longue, icônes). Liste des avantages, choix **Mensuel | Annuel** (prix du store, économie de l'annuel affichée), « S'abonner », « Restaurer les achats » (exigé par Apple pour un abonnement), conditions de renouvellement automatique sous le bouton.
- Abonné : page « Plus » avec l'échéance, « Gérer l'abonnement » (`showManageSubscriptions`, App Store) et la liste des avantages.
- **Après l'achat**, l'app attend l'état de l'API (événement `plusChanged`, ou `GET /users/me/plus` relu), comme l'attente du crédit des jetons.
- Éditeur : la limite de durée (`UploadRules.maxDuration`, `PublicationKind`) vient de l'état de l'abonnement ; caméra : « 10 min » en plus de « 3 min | 60 s | 15 s ».

## Conséquences
- Deuxième source de revenus, sans rien retirer aux autres comptes.
- L'API a besoin de la **clé secrète** RevenueCat (`REVENUECAT_SECRET_API_KEY`), à garder hors de l'app et du dépôt.
- Le badge ajoute un champ à `UserSummaryDto`, donc au client Swift et à toutes les réponses qui contiennent un compte.
- Les vidéos de 10 minutes coûtent plus cher à transcoder et à stocker.
- Hors périmètre : essai gratuit, offres promotionnelles, abonnement offert, partage familial, tableau de bord des abonnements au backoffice (le badge et la fiche d'un compte seulement).
