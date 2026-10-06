# ADR-019 — Backoffice : rôle administrateur, périmètre et session

## Statut
Accepté

Complète [ADR-004](ADR-004-architecture-backoffice.md), sans le remplacer.

## Contexte
L'ADR-004 fixe la pile du backoffice (Next.js, MVC, shadcn/ui) et impose de passer uniquement par l'API. Il ne dit ni qui peut s'y connecter, ni ce qu'il contient, ni comment la session est gardée.

## Décision
Rôle administrateur :
- Colonne `users.role` (`user` | `admin`), propriété du module `auth`.
- **Aucune route n'attribue le rôle** : script `pnpm admin:grant <email | @pseudo>` (et `admin:revoke`, `admin:list`), lancé par l'exploitant.
- Décorateur `@AdminOnly()` lu par la garde globale : access token exigé, puis **rôle relu en base à chaque requête** (403 sinon). Un rôle retiré prend effet aussitôt.

Périmètre de la première version :
- Tableau de bord : comptes, vidéos par statut, commentaires (totaux et 7 derniers jours), liens vers PostHog.
- Comptes : recherche (pseudo, nom, identifiant), fiche.
- Vidéos : liste filtrée (statut, auteur), lecture HLS, suppression.
- Commentaires : liste filtrée (vidéo, auteur), suppression.
- Une suppression par modération est la même que par l'auteur (cascade, nettoyage des fichiers) ; l'auteur n'est pas prévenu.

Session :
- Connexion par `POST /auth/login`, puis `GET /admin/me` : un compte sans rôle est refusé et sa session API révoquée.
- Jetons de l'API dans des **cookies `httpOnly`**, lus seulement par le serveur Next.js.
- Rafraîchissement dans le **proxy** de Next.js, avec **un seul appel par refresh token** : l'API révoque toute la session si un refresh token déjà utilisé revient (ADR-010), or le navigateur envoie plusieurs requêtes à la fois.

## Alternatives
- Comptes administrateurs dans une table séparée : un second système d'authentification à maintenir. Rejeté.
- Rôle dans le JWT : pas de requête en base, mais un rôle retiré resterait valable jusqu'à 15 minutes. Rejeté.
- Jetons gardés par le navigateur (stockage local) : exposés à tout script de la page. Rejeté.
- Suspension de compte et file de signalements dès la première version : nouvelles notions dans tout le backend. Reportées.
- Copie des données PostHog dans l'API : une clé personnelle PostHog côté serveur. Liens seulement pour commencer.

## Conséquences
### Positives
- Retirer un administrateur est immédiat.
- Aucun jeton n'est visible du navigateur.

### Négatives
- Une requête en base de plus par appel d'administration.
- Le rafraîchissement dédupliqué est propre au processus : plusieurs instances du backoffice demanderaient un magasin partagé.
- Pas de journal des actions de modération.

## Liens
- ADR-004 — Architecture backoffice
- ADR-010 — Authentification
- ADR-018 — Modules messaging, push et admin
- Complété par [ADR-032](ADR-032-backoffice-portefeuille.md) — Backoffice : portefeuille et journal des jetons
- Complété par [ADR-037](ADR-037-suspension-compte.md) — Suspension de compte
- Complété par [ADR-038](ADR-038-signalements.md) — Signalements
