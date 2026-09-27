# Backoffice (ADR-004)

Application d'administration : Next.js 16 (App Router), React 19, Tailwind CSS v4 et shadcn/ui (préréglage Nova, Radix).
Le backoffice ne contacte jamais PostgreSQL ni Redis : il appelle uniquement l'API REST, depuis le serveur Next.

```bash
pnpm --filter backoffice dev    # http://localhost:3001 (ou `pnpm dev` à la racine, avec l'api et le worker)
pnpm --filter backoffice test   # Vitest : session, rafraîchissement, mise en forme
pnpm admin:grant <email | @pseudo>   # donner le rôle administrateur (à la racine)
```

Configuration (`.env` racine, lu par `next.config.ts`) : `API_URL` (défaut `http://localhost:3000`) et, facultatif,
`POSTHOG_PROJECT_URL` pour les liens vers PostHog.

## Organisation (MVC)

| Dossier | Rôle |
|---|---|
| `app/` | Vues : pages et gabarits (App Router). `(admin)/` regroupe les écrans protégés, `login/` la connexion, `auth/fin/` la fin de session. |
| `controllers/` | Server Actions (`'use server'`) : connexion, déconnexion, suppression d'une vidéo ou d'un commentaire. |
| `models/` | Appels à l'API, un fichier par ressource, avec les types de `@repo/shared`. |
| `components/` | Composants de vue ; `components/ui/` est généré par `shadcn add`. |
| `lib/` | Client d'API (`api-client.ts`, `server-only`), session (cookies), rafraîchissement des jetons, mise en forme. |
| `proxy.ts` | Proxy de Next 16 (ex-middleware) : rafraîchit la session avant chaque page ou Server Action. |

Ajouter un composant shadcn : `pnpm dlx shadcn@latest add <nom>` dans `apps/backoffice`.

## Session

- Connexion par `POST /auth/login`, puis `GET /admin/me` : un compte sans rôle `admin` est refusé et sa session API révoquée aussitôt.
- Jetons dans deux cookies `httpOnly` (`bo_access`, `bo_refresh`, `SameSite=Lax`, `Secure` en production) : le navigateur ne voit jamais un jeton.
  Le cookie de l'access token expire une minute avant lui ; la session dure 7 jours sans activité.
- **Rafraîchissement dans le proxy** : une page ne peut pas écrire de cookie pendant son rendu. Sans access token, le proxy appelle
  `POST /auth/refresh`, passe les nouveaux jetons à la requête en cours et au navigateur. API injoignable : 503, session gardée.
- **Un seul rafraîchissement par refresh token** (`lib/token-refresh.ts`) : l'API révoque toute la session si un refresh token déjà
  utilisé revient (ADR-010), or le navigateur envoie souvent plusieurs requêtes à la fois. Les requêtes simultanées partagent le même
  appel, et le résultat est resservi 30 s à celles qui portent encore l'ancien cookie.
- 401 de l'API pendant le rendu : `/auth/fin?raison=session` efface les cookies et renvoie à la connexion. 403 (rôle retiré) : idem
  avec `raison=acces`. Le rôle est relu en base par l'API à chaque requête : un `pnpm admin:revoke` prend effet aussitôt.

## Écrans

- **Tableau de bord** : comptes, vidéos et commentaires (totaux et 7 derniers jours), vidéos par statut, liens vers PostHog.
- **Comptes** : recherche par pseudo (avec ou sans `@`), nom ou identifiant ; fiche avec rôle, compteurs, vidéos récentes.
- **Vidéos** : tous statuts, filtre par statut et par auteur ; page avec lecture HLS (native dans Safari, hls.js ailleurs),
  compteurs, commentaires récents et suppression.
- **Commentaires** : tous, du plus récent au plus ancien, filtrables par vidéo ou par auteur ; suppression.

Suppressions confirmées dans une alerte. Une vidéo est supprimée comme par son auteur (cascade, fichiers nettoyés par l'API) ;
un commentaire emporte sa notification. L'auteur n'est pas prévenu.

## Limites

- Pas de suspension de compte, de signalement, ni de journal des actions de modération.
- Rafraîchissement dédupliqué propre au processus : avec plusieurs instances du backoffice, il faudrait un magasin partagé (Redis via l'API, ou affinité de session).
- Pas de copie des données PostHog : liens seulement.
- Pas de protection contre la force brute sur la connexion (comme `/auth/login` de l'API).
