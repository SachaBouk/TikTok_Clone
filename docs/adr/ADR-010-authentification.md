# ADR-010 — Authentification : JWT maison + Sign in with Apple

## Statut
Accepté

## Contexte
L'application doit gérer la connexion, la déconnexion et un mode invité aux fonctionnalités réduites.
Apple impose une option de connexion équivalente (type Sign in with Apple) si un login tiers comme Google est proposé.
Apple impose la suppression du compte depuis l'application si celle-ci permet d'en créer un.

## Décision
- JWT gérés dans NestJS (Passport) : access token de 15 minutes et refresh token rotatif, stocké haché.
- Connexion par email / mot de passe et Sign in with Apple. Pas de connexion Google au MVP.
- Côté iOS, les tokens sont stockés dans le Keychain.
- Mode invité : le feed est lisible sans compte ; liker, commenter, publier ou suivre nécessite d'être connecté.
- Suppression du compte possible depuis l'application.

## Alternatives
- Supabase Auth ou Clerk : service géré, moins de code, mais dépendance externe. Rejetés.
- Connexion Google : reportée après le MVP.

## Conséquences
### Positives
- Authentification maîtrisée, sans dépendance externe.
- Exigences Apple anticipées.

### Négatives
- Rotation, révocation des tokens et stockage des mots de passe à implémenter soi-même.

## Liens
- ADR-003 — Architecture backend
- ADR-011 — Temps réel
