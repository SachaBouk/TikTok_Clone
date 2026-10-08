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
- Échecs de connexion limités par l'API (ADR-030) : 429 → « Trop de tentatives de connexion. Réessaie dans N min. ». L'adresse du navigateur est transmise dans `X-Forwarded-For` ; l'API ne s'en sert pour sa limite par IP que si `TRUST_PROXY` désigne le backoffice (sinon, tous les administrateurs partagent l'adresse du serveur Next).
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

- **Tableau de bord** : comptes (dont suspendus), vidéos, commentaires et jetons vendus (totaux et 7 derniers jours), vidéos par
  statut, alerte s'il y a des achats de jetons à rapprocher, liens vers PostHog.
- **Comptes** : recherche par pseudo (avec ou sans `@`), nom ou identifiant, solde de jetons ; fiche avec rôle, compteurs,
  vidéos récentes et derniers mouvements de jetons.
- **Suspension** (ADR-037) : bouton « Suspendre » de la fiche d'un compte (pas pour un administrateur), avec un motif interne
  obligatoire (500 caractères au plus, jamais montré à la personne). Le compte est déconnecté de ses appareils, ne peut plus
  se connecter, et ses contenus disparaissent pour les autres jusqu'à la levée ; rien n'est supprimé. Encadré « Compte
  suspendu » (date, auteur, motif) et « Lever la suspension » ; badge « Suspendu » dans la liste, et filtre « Suspendus » de
  la page Comptes : du plus récemment suspendu au plus ancien, avec date, motif et administrateur.
- **Vidéos** : tous statuts, filtre par statut et par auteur ; page avec lecture HLS (native dans Safari, hls.js ailleurs),
  compteurs, commentaires récents et suppression.
- **Commentaires** : tous, du plus récent au plus ancien, filtrables par vidéo ou par auteur ; suppression.
- **Signalements** (ADR-038) : file des vidéos, commentaires, messages, stories (ADR-051) et comptes signalés, groupés par cible (aperçu,
  compte visé, nombre, motifs), de la plus récemment signalée à la plus ancienne ; alerte sur le tableau de bord. Page d'une
  cible : « Supprimer la vidéo / le commentaire / le message / la story », « Suspendre », « Classer sans suite », et l'historique des
  signalements avec la décision (date, administrateur). Toute décision clôt les signalements ouverts de la cible (une
  suspension, ceux de tout le compte) et est annoncée aux personnes qui les ont envoyés. Un contenu supprimé par son
  auteur, ou un compte supprimé, quitte la file de lui-même. Rien n'est masqué avant décision. D'un message, seul son
  texte est visible : jamais la conversation. Une story s'affiche (photo, ou vidéo en HLS) tant qu'elle est en ligne : à
  examiner avant son expiration (24 h), après laquelle elle quitte la file d'elle-même (« Supprimé hors modération »).
- **Journal** (ADR-038) : chaque suppression, suspension, levée et classement sans suite, avec l'administrateur, le compte
  visé, le contenu, le motif et le nombre de signalements clos ; filtrable par compte (lien depuis sa fiche).
- **Jetons** (ADR-032, lecture seule) : vendus, remboursés, ajustés et en circulation (production ; achats de test à part),
  journal complet filtrable par compte ou « à rapprocher » (client RevenueCat inconnu de l'API : rien n'a été crédité).
  Montant annoncé et appliqué, solde après, identifiants RevenueCat et store. Un crédit manuel passe par un ajustement
  dans RevenueCat (il revient par le webhook).
- **Cadeaux** (ADR-050, lecture seule) : jetons dépensés (total, 7 jours), gains des créateurs (non dépensables), journal de
  chaque cadeau (expéditeur, créateur, vidéo, prix, solde après), filtrable par compte (bouton « Ses cadeaux » de la fiche,
  qui affiche aussi les gains). Carte « Jetons offerts » sur le tableau de bord.

Suppressions confirmées dans une alerte, avec un **motif** de la liste des signalements (le plus signalé est proposé depuis
un signalement) : l'auteur reçoit « Contenu retiré » avec ce motif, dans son activité et en notification push. Une vidéo est
supprimée comme par son auteur (cascade, fichiers nettoyés par l'API) ; un commentaire emporte sa notification ; un message
disparaît pour les deux participants ; une story est supprimée comme par son auteur (vues comprises, fichiers nettoyés).

## Limites

- Pas de contestation d'une décision par l'auteur ; le rôle administrateur (script `admin:grant`) n'est pas journalisé.
- Rafraîchissement dédupliqué propre au processus : avec plusieurs instances du backoffice, il faudrait un magasin partagé (Redis via l'API, ou affinité de session).
- Pas de copie des données PostHog : liens seulement.
- Limite des échecs de connexion par IP (ADR-030) : sans `TRUST_PROXY` désignant le backoffice, tous les administrateurs partagent l'adresse du serveur Next.
- Portefeuille en lecture seule, sans chiffre d'affaires en euros (le prix payé n'est pas gardé).
