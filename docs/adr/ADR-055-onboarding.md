# ADR-055 — Onboarding : écran de lancement, introduction, connexion par email ou pseudo

## Statut
Proposé

Complète [ADR-010](ADR-010-authentification.md) (authentification) et [ADR-017](ADR-017-app-ios-choix-implementation.md) (app iOS), sans les remplacer : le développeur veut un parcours d'arrivée inspiré de TikTok (écran de lancement avec logo, introduction, puis écrans « Connexion » et « Inscription » qui listent les moyens de se connecter).

## Contexte
Aujourd'hui :
- au lancement, un écran noir avec le nom de l'app et un indicateur (`LaunchView`) pendant la reprise de session, puis le feed, en invité si personne n'est connecté (ADR-010) ;
- la connexion est une feuille (`AuthFlowView`) ouverte par une action d'invité : formulaire email et mot de passe, puis « Créer un compte » ;
- `POST /auth/login` n'accepte qu'un **email**.

Les maquettes fournies (TikTok) montrent : un écran noir avec le logo, un écran blanc « It starts on TikTok. », puis « Log in to TikTok » et « Sign up for TikTok », chacun avec une liste de boutons (téléphone, email, pseudo, Facebook, Apple, Google…), un texte légal et un lien vers l'autre écran.

## Décision
Choix du développeur, parmi les options proposées :
- **Moyens de connexion** : un seul pour l'instant, par écran.
  - **Connexion** : « Email ou nom d'utilisateur ». L'API accepte désormais **l'email ou le pseudo**. Pas de téléphone : il faudrait l'envoi de codes SMS par un service payant.
  - **Inscription** : « Email » (formulaire existant : nom, pseudo, email, mot de passe).
  - Facebook, Google, Instagram, Twitter : non. Apple : reporté (compte Apple Developer, ADR-010).
- **Quand** :
  - **écran de lancement** à chaque ouverture, pendant la reprise de session : fond noir, logo et nom de l'app ;
  - **au premier lancement seulement**, si personne n'est connecté : introduction (« Tout commence sur TikTok Clone. ») puis l'écran « Connexion », avec **« Continuer sans compte »** : le mode invité reste (ADR-010, expérience A/B « invitation invité » de l'ADR-013) ;
  - ensuite, la feuille de connexion ouverte par une action d'invité prend **le même design** (écran « Connexion », puis le formulaire), avec « Fermer ».
  - Un compte déjà connecté au premier lancement de cette version ne voit pas l'introduction.
- **Logo** : logo maison « TikTok Clone » (note de musique décalée en cyan et rose, dessinée en SwiftUI), **pas le logo ni le nom de TikTok** (marque déposée).
- **Textes** en français (« Connexion à TikTok Clone », « Inscription à TikTok Clone », « Pas encore de compte ? S'inscrire »). Pas de texte légal ni de liens vers des conditions d'utilisation : elles n'existent pas encore.

### Connexion par email ou pseudo (API)
- `POST /auth/login` : le champ **`email` devient `identifier`** (email ou pseudo ; un `@` initial devant un pseudo est ignoré). Les clients (app, backoffice, seed) sont mis à jour ensemble.
- Un identifiant qui contient `@` ailleurs qu'en tête est un email, sinon un pseudo (les pseudos ne contiennent jamais `@`).
- **Limite des échecs** (ADR-030) : comptée **par compte** quand l'identifiant correspond à un compte, sinon par empreinte de l'identifiant. Alterner email et pseudo du même compte ne double pas les essais. Clés `ratelimit:login-account:*` (au lieu de `login-email:*`). La limite par adresse IP ne change pas.
- La réponse ne dit toujours pas si le compte existe (401 « Identifiant ou mot de passe incorrect. »).

### App iOS
- `LaunchView` : logo et nom sur fond noir.
- `OnboardingView` (premier lancement) : introduction 2 s (ou toucher), puis l'écran « Connexion » ; « Continuer sans compte » ferme le parcours ; une connexion ou une inscription aussi. Préférence `onboardingCompleted` (UserDefaults, `PreferencesStore`) posée à la fin.
- Écrans « Connexion » et « Inscription » (`AuthWelcomeView`) : titre en gros, bouton à contour avec icône, lien vers l'autre écran en bas. Ils ouvrent les formulaires existants.
- Le consentement à la mesure d'audience (ADR-013) est demandé **après** l'onboarding, pas par-dessus.
- Mesure d'audience : `auth_sheet_shown` porte `source` (`onboarding` ou `prompt`).

## Alternatives
- **Email seulement** (aucun changement d'API) : écarté par le développeur.
- **Connexion par téléphone** : codes SMS (service externe payant, table des codes, limites anti-abus). Écarté pour l'instant.
- **Onboarding à chaque lancement sans compte**, ou **connexion obligatoire** : écartés par le développeur (gênant pour l'invité, contraire à l'ADR-010).
- **Garder `email` comme nom du champ** en y acceptant un pseudo : nom trompeur dans le contrat. Écarté.

## Conséquences
### Positives
- Un parcours d'arrivée plus soigné, proche de TikTok, sans perdre le mode invité.
- La connexion par pseudo, plus simple à retenir.
- Les écrans « Connexion » et « Inscription » sont prêts pour d'autres moyens (Apple plus tard).

### Négatives
- **Changement du contrat** de `POST /auth/login` (`identifier`) : une ancienne version de l'app ne peut plus se connecter (sans conséquence : pas encore publiée).
- Clés de limite de débit renommées : les compteurs en cours repartent de zéro au déploiement.
- Un écran de plus avant le formulaire de connexion.

## Liens
- ADR-010 — Authentification
- ADR-013 — Analytics et A/B testing
- ADR-017 — Application iOS : choix d'implémentation
- ADR-030 — Limites de débit : connexion et partages
