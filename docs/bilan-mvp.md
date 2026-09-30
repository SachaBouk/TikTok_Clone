# Bilan de la première version (MVP) face à l'ADR-016

État au 30 septembre 2026 (branche `main`).

## En bref

Toutes les fonctionnalités retenues par l'[ADR-016](adr/ADR-016-perimetre-mvp.md) sont en place, de l'API à l'app iOS. Elles ont été vérifiées par des tests automatisés, des tests de bout en bout contre l'infrastructure locale et une relecture des parcours complets dans le simulateur. Aucune fonctionnalité reportée par l'ADR-016 n'a été développée.

Trois points dépendent de comptes externes que le projet n'a pas encore :
- le paywall n'a été éprouvé qu'avec des achats simulés, faute de projet RevenueCat et App Store Connect ;
- les notifications push et Sign in with Apple sont prêts côté API, mais bloqués côté app, faute de compte Apple Developer ;
- la mesure d'audience fonctionne, mais sans projet PostHog configuré.

## Méthode

- **Tests automatisés** : 248 tests pour l'API, 13 pour le worker (FFmpeg réel), 10 pour le backoffice et 198 pour l'app iOS (Swift Testing), tous verts.
- **Intégration continue** : deux workflows GitHub Actions.
  - `ci.yml` : typecheck, tests, build, contrat OpenAPI, migrations sur une base vierge, images Docker.
  - `ios.yml` : app iOS sur l'image Xcode 27, avec les versions du `Package.resolved`.
- **Tests de bout en bout** à chaque étape, contre PostgreSQL, Redis et MinIO locaux, avec des comptes jetables. L'état de la base est restauré ensuite.
- **Relecture des parcours** (étape 4) dans le simulateur, iPhone 18 Pro sous iOS 27 :
  - deux comptes jetables : l'un créé et piloté dans l'app, l'autre piloté par l'API pour réagir, commenter, suivre et écrire ;
  - la base, le stockage et Redis sont revenus exactement à leur état initial à la fin.

## Couverture du périmètre

| Fonctionnalité retenue (ADR-016) | État | Où | Vérifié par |
|---|---|---|---|
| Feed aléatoire, sans recommandation | Fait | module `feed` (photo du catalogue en cache Redis, ordre mélangé par session, sans doublon) ; lecteur HLS de l'app | tests, parcours 1 et 3 |
| Publication depuis la galerie, sans édition | Fait | envoi direct par parties vers le stockage (ADR-007), reprise après relance, transcodage HLS par le worker (ADR-008), suivi en temps réel | tests, parcours 4 |
| Script de seed (local, démo) | Fait | `pnpm seed` : comptes, vidéos et interactions via l'API, même pipeline que l'app | exécution |
| Like, favori, commentaire, partage, republication, follow | Fait | module `interactions` ; colonne d'actions du lecteur, feuille de commentaires, partage par lien d'app | tests, parcours 3 |
| Messagerie directe | Fait | module `messaging` : demandes, « Vu », « en train d'écrire », vidéo partagée, limites d'envoi | tests, parcours 6 |
| Activité (notifications) | Fait | module `notifications` : regroupement, badge et arrivées en direct | tests, parcours 5 |
| Compte : nom, pseudo, photo, bio, abonnés, abonnements | Fait | module `users` ; écran de profil, modification, photo recadrée et envoyée directement au stockage | tests, parcours 7 |
| Centre d'activités : historiques de visionnage et de commentaires | Fait | modules `feed` et `interactions` ; écrans des paramètres | tests, parcours 9 |
| Connexion, déconnexion, accès réduit en invité | Fait | module `auth` (JWT et refresh tokens rotatifs, ADR-010) ; mode invité dans l'app | tests, parcours 1, 2 et 10 |
| Paywall : achat de jetons crédités au portefeuille | Fait, en simulation | module `wallet` (webhook RevenueCat idempotent, signature HMAC) ; paywall iOS | tests, parcours 8 (`-fakePurchases` et webhook simulé) |

Suppression du compte (exigence Apple) : faite, et vérifiée au parcours 11. Elle efface les données et les fichiers du stockage, et anonymise le journal des jetons.

### Au-delà du périmètre

Ajouts décidés pendant la réalisation (ADR 017 à 034) :
- **Backoffice** (Next.js, ADR-004 et ADR-019) : tableau de bord, comptes, vidéos, commentaires, modération, jetons en lecture seule (ADR-032).
- **Blocage** : actions interdites dans les deux sens, contenus masqués (ADR-029, proposé).
- **Sécurité** : limites de débit de la connexion et des partages (ADR-030), signature HMAC du webhook (ADR-031).
- **Notifications push** côté API (APNs, testées contre un faux serveur).
- **Mesure d'audience et test A/B** (PostHog, consentement opt-in, ADR-013 et ADR-024).
- **Images Docker** et CI iOS (ADR-027 et ADR-033), `Package.resolved` versionné (ADR-034).

### Reporté, et non développé

Enregistrement et édition vidéo ; Live, Stories et réponses vidéo ; For You, feed des abonnements, recherche et hashtags ; dépense des jetons (cadeaux) et Shop. Les jetons achetés n'ont donc pas encore d'usage, comme l'ADR-016 l'annonçait.

## Parcours relus dans le simulateur

| # | Parcours | Résultat |
|---|---|---|
| 1 | Invité : feed, like qui ouvre la connexion | Conforme |
| 2 | Inscription dans l'app | Conforme : feuille fermée, feed rechargé en mode connecté |
| 3 | Like, favori, republication, suivi, commentaire, partage | Conforme ; le partage est compté une fois |
| 4 | Publication d'une vidéo de la galerie | Conforme : « Publiée » en moins de 2 s pour 6 s de vidéo, lecture HLS |
| 5 | Activité reçue d'un autre compte | Conforme : badge en direct, trois notifications, marquées lues à l'affichage |
| 6 | Demande de message, acceptation, réponse | Conforme : « Vu » et réponse reçue en direct |
| 7 | Profil : grilles, bio, photo | Conforme : photo appliquée tout de suite |
| 8 | Paywall : achat de 500 jetons | Conforme en simulation : « +500 jetons ajoutés », historique à jour |
| 9 | Paramètres : historiques de visionnage et de commentaires | Conforme |
| 10 | Déconnexion puis reconnexion | Conforme : plus aucune session active après la déconnexion, profil retrouvé ensuite |
| 11 | Suppression du compte | Conforme : retour en invité, vidéo et photo supprimées du stockage |

## Constats de la relecture

Aucun défaut bloquant. Cinq points relevés ; les quatre premiers sont corrigés et vérifiés dans le simulateur :

1. **Démarrage** (corrigé) : l'écran restait blanc environ 3 s au lancement. Mesure faite à partir des journaux horodatés :
   - l'essentiel du délai précède notre code : le processus démarre environ 3,3 s après la commande de lancement du simulateur (build Debug) ;
   - il faut ensuite environ 1,4 s jusqu'à la première requête du feed ;
   - le blanc venait de l'écran de lancement système, vide, puis de l'attente de reprise de session sur fond blanc.

   L'écran de lancement et cette attente ont maintenant le fond noir du feed (couleur `LaunchBackground`, `LaunchView`) : plus d'éclair blanc. La durée elle-même sera à mesurer sur un iPhone, en build Release.
2. **Partage par « Copier »** (corrigé) : le texte et le lien étaient deux éléments séparés, et un collage perdait le lien. Pour « Copier », le texte contient désormais le lien. Pour les autres actions, le lien reste un élément à part, que Messages ou Mail affichent comme un vrai lien.
3. **Confirmation de déconnexion** (corrigé) : elle s'ancrait en haut de l'écran, sur la liste entière. Elle est maintenant attachée au bouton « Se déconnecter » et s'affiche juste au-dessus.
4. **Dates relatives** (corrigé) : « il y a 16 secondes » restait affiché tant que l'écran était ouvert. Les dates des commentaires, de l'activité, des conversations et de l'historique des commentaires utilisent maintenant le style de date relative du système (iOS 18), qui se met à jour seul à l'écran : « maintenant » sous 30 s, puis « il y a 1 minute », « il y a 2 heures », « hier », « il y a 8 jours », et la date au-delà d'un mois.
5. **Position GPS** : le sélecteur de la galerie d'iOS 27 propose « Lieu inclus ». La dette connue (position gardée dans le fichier brut) peut donc être contournée par l'utilisateur, mais l'app ne le guide pas et le serveur ne retire pas ces métadonnées.

## Ce qui reste bloqué, et pourquoi

| Sujet | Bloqué par | Ce qui est prêt |
|---|---|---|
| Achats réels de jetons | Projet RevenueCat, monnaie `TKN`, packs, webhook ; produits dans App Store Connect | SDK, paywall, webhook signé et idempotent, journal, backoffice |
| Notifications push de l'app | Compte Apple Developer (clé APNs, signature) | Envoi APNs de l'API, appareils, déclencheurs, routeur de l'app |
| Sign in with Apple côté app | Compte Apple Developer | Vérification de l'identity token par l'API |
| Mesure d'audience réelle | Projet PostHog Cloud UE, flag `guest-signup-prompt` | SDK derrière consentement, catalogue d'événements, expérience A/B |
| Mise en production | Choix de l'hébergeur (ADR-015) | Trois images Docker, migrations en conteneur, `TRUST_PROXY` |

## Dettes connues

Consignées au fil des étapes, détaillées dans `CLAUDE.md` :
- **Médias** :
  - HDR converti sans ajustement des couleurs ;
  - pas de purge du CDN à la suppression d'une vidéo ;
  - position GPS gardée dans le fichier brut ;
  - envoi en arrière-plan pas testé sur un vrai iPhone.
- **Compte** :
  - révocation des jetons Apple à la suppression d'un compte ;
  - deux confirmations de photo simultanées peuvent se gêner.
- **Messagerie** :
  - « en train d'écrire » limité par instance ;
  - retirer un message d'une demande libère une place ;
  - pas de cache hors ligne, de recherche de destinataire ni de renvoi d'un message en échec.
- **Profil et activité** :
  - profil relu seulement à l'ouverture ;
  - pas de « Suivre en retour » dans l'activité ;
  - groupe de notifications non recalculé après un retrait.
- **Mesure d'audience** :
  - le premier lancement n'est pas compté ;
  - le temps de chargement est compté dans le temps de visionnage.
- **Backoffice** : pas de suspension de compte, de signalements ni de journal de modération.
- **Infrastructure** : image Docker de l'API lourde (environ 850 Mo).

## Pour une démonstration

```bash
pnpm infra:up
pnpm dev                          # api :3000, worker, backoffice :3001
pnpm seed                         # comptes de démo (<pseudo>@demo.local / demo-password) et vidéos
pnpm admin:grant lea.martin@demo.local   # accès au backoffice
```

App iOS : `cd apps/ios && xcodegen generate`, puis lancer dans le simulateur. Pour montrer le paywall sans RevenueCat, ajouter l'argument de lancement `-fakePurchases` et simuler le webhook avec la commande curl de `apps/ios/README.md`. L'API doit alors être lancée avec `REVENUECAT_WEBHOOK_AUTHORIZATION`.
