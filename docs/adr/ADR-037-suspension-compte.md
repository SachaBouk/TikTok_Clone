# ADR-037 — Suspension de compte

## Statut
Accepté

Complète [ADR-019](ADR-019-backoffice-role-perimetre-session.md), sans le remplacer.

## Contexte
L'ADR-019 a reporté la suspension de compte : « nouvelles notions dans tout le backend ». Jusqu'ici, la modération ne pouvait que supprimer des vidéos et des commentaires, un par un. Un compte abusif restait en ligne et pouvait recommencer.

Une suspension touche deux choses qui relèvent de modules différents :
- **l'accès** du compte : connexion, sessions, jetons, WebSocket ;
- **la visibilité** de ses contenus pour les autres : feed, profil, commentaires, listes, messagerie, notifications.

Les dépendances entre modules (ADR-003) imposent aussi une contrainte. `auth` ne peut pas dépendre de `users`, sinon le cycle `realtime` → `auth` → `users` → `videos` → `realtime` se forme.

## Décision
Choix du développeur, parmi les options proposées :
- **Jusqu'à la levée** par un administrateur, sans date de fin.
- **Message générique** pour la personne suspendue (« Ton compte est suspendu. »). Le motif, obligatoire (500 caractères au plus), reste interne au backoffice.
- **Effet immédiat** : sessions révoquées, WebSocket fermés, et chaque access token du compte est refusé dès la suspension.
- **Contenus masqués pour tous**, invités compris. Rien n'est supprimé : tout revient à la levée.

Mise en œuvre :
- **Données** : colonnes `users.suspended_at`, `suspension_reason`, `suspended_by`, propriété du module `auth`, comme le rôle (ADR-019).
  - `suspended_by` passe à `NULL` si l'administrateur supprime son compte.
  - Contraintes CHECK écrites à la main : date et motif sont remplis ensemble, l'auteur n'est renseigné que pour un compte suspendu, et jamais soi-même.
  - Index partiel sur les comptes suspendus.
- **Registre partagé** `src/suspension`, sur le modèle du limiteur de l'ADR-030 :
  - un port `SuspendedAccounts` sans NestJS, avec des adaptateurs Redis (ensemble `suspended:accounts`) et en mémoire, et un module global ;
  - la base fait foi : `auth` écrit dans le registre à chaque suspension et le reconstruit au démarrage de l'API ;
  - aucune requête n'a ainsi à lire la base pour savoir si un compte est suspendu ;
  - Redis indisponible : aucun compte n'est considéré comme suspendu, et c'est journalisé, comme pour les limites de débit.
- **Accès** (module `auth`) :
  - la connexion par email ou par Apple renvoie 403 « Compte suspendu », **seulement après vérification de l'identité** : la suspension n'est révélée qu'au titulaire ;
  - le rafraîchissement est refusé ;
  - `JwtStrategy` refuse l'access token d'un compte suspendu : 401 sur une route protégée, invité sur une route publique ;
  - le handshake WebSocket est refusé de la même façon ;
  - un administrateur ne peut pas être suspendu (retirer d'abord son rôle), ni soi-même (409).
- **Fermeture des connexions** : `RealtimeService.disconnectUser` publie un ordre de fermeture sur le bus Redis. Chaque instance ferme les connexions du compte avec le code 4001. L'app tente alors de rafraîchir sa session, échoue et repasse en invité. C'est le module `admin` qui l'appelle, car `auth` ne dépend pas de `realtime`.
- **Masquage**, toujours à la lecture :
  - `InteractionsService.getHiddenAccountIds(viewerId?)` donne les comptes suspendus (pour tous) et les comptes bloqués du lecteur (ADR-029). Il sert au feed, aux grilles, à la vidéo seule (404), aux commentaires, aux listes d'abonnés, à l'historique des commentaires et aux vidéos partagées par message ;
  - **profil public** (`GET /users/:username`) : **410** pour un compte suspendu. Les autres modules le trouvent toujours par son pseudo et décident de ce qu'ils en montrent ;
  - **actions** vers un compte suspendu : réagir, commenter ou partager sur ses vidéos renvoie 404, comme le suivre. Retirer une réaction, se désabonner et débloquer restent possibles ;
  - **messagerie** : un compte suspendu compte comme un compte qui a bloqué le lecteur. On ne peut plus lui écrire, ses demandes disparaissent, l'historique reste lisible. Rien ne dit à l'autre qu'il s'agit d'une suspension ;
  - **notifications** : celles d'un compte suspendu ne sont ni listées, ni regroupées, ni comptées dans le badge. Elles sont exclues en SQL ; le module ne lit pas la table `users`.
- **Backoffice** :
  - routes `PUT /admin/users/:id/suspension` (`{ reason }`) et `DELETE /admin/users/:id/suspension`, qui renvoient le compte ;
  - `suspension` (date, motif, administrateur auteur) sur la fiche d'un compte, et `users.suspended` dans les statistiques ;
  - côté app web : bouton « Suspendre » avec saisie du motif, encadré de suspension avec « Lever la suspension », badge dans la liste, compteur sur le tableau de bord ;
  - liste des comptes suspendus : `GET /admin/users?suspended=true`, du plus récemment suspendu au plus ancien (pagination par clé sur la date de suspension et l'identifiant, curseur = identifiant du dernier compte lu), avec date, motif et administrateur ; filtre « Suspendus » de la page Comptes.
- **App iOS** : `AppError.accountSuspended` à la connexion (403) et `AppError.profileSuspended` pour un profil (410).

## Alternatives
- **Contenus visibles, accès seul coupé** : beaucoup plus simple, mais un profil abusif reste en ligne. Écarté par le développeur.
- **Suspension temporaire avec levée automatique** : dates et tâche planifiée en plus. Écarté pour l'instant.
- **Motif montré à la personne** : il faudrait rédiger des motifs publics. Écarté.
- **Effet sous 15 minutes** (sessions révoquées, access token valable jusqu'à expiration, comme une suppression de compte) : un compte qui spamme pourrait continuer un quart d'heure. Écarté.
- **Lecture de la base à chaque requête** (comme le rôle administrateur) : une requête de plus sur toutes les routes authentifiées. Remplacée par le registre Redis.
- **Suspension portée par `users`** : `auth` devrait dépendre de `users`, ce qui crée un cycle (voir le contexte). Rejeté.

## Conséquences
### Positives
- Un compte abusif est arrêté net et disparaît pour les autres, sans perte de données.
- Le registre partagé réutilise le masquage de l'ADR-029 : feed, commentaires, listes et messagerie n'ont pas eu à changer de logique.

### Négatives
- Une lecture Redis de plus par requête authentifiée (`SISMEMBER`), et une lecture du registre entier par liste (`SMEMBERS`). Peu de comptes sont suspendus, donc c'est léger.
- Pendant une panne de Redis, les comptes suspendus ne sont plus masqués ni bloqués par jeton. La connexion, qui lit la base, reste refusée.
- `GET /videos/:id` (module `videos`, qui ne dépend ni de `users` ni du registre) renvoie encore la vidéo publiée d'un compte suspendu à qui connaît son identifiant. Les fichiers HLS restent servis par le CDN.
- Après la levée, un access token encore valide (moins de 15 minutes) fonctionne de nouveau. Les sessions, elles, restent révoquées.
- Les compteurs (abonnés, likes, commentaires) comptent toujours les contributions du compte suspendu.
- Le badge des notifications n'est pas renvoyé en direct au moment de la suspension : il est relu ensuite.
- Dans la liste des comptes suspendus, le curseur d'un compte dont la suspension a été levée entre deux pages donne une page vide (revenir au début). Suspensions et levées sont inscrites au journal de modération (ADR-038).
- Une personne suspendue ne peut pas supprimer elle-même son compte : une demande de suppression passe par l'exploitant.

## Liens
- ADR-003 — Architecture backend
- ADR-010 — Authentification
- ADR-011 — Temps réel
- ADR-019 — Backoffice : rôle administrateur, périmètre et session
- ADR-029 — Blocage : contenus masqués
- ADR-030 — Limites de débit (registre partagé sur le même modèle)
