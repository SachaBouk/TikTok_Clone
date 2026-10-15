# ADR-055 — Onboarding : écran de lancement, introduction, connexion par email ou pseudo, inscription par étapes

## Statut
Accepté

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
  - **Inscription** : « Email », en plusieurs étapes (voir « Inscription par étapes »).
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

### Inscription par étapes
Ajouté à partir des maquettes de l'inscription de TikTok (« Use phone or email »), choix du développeur parmi les options proposées. Le formulaire unique (nom, pseudo, email, mot de passe) est remplacé par un écran par étape, poussé dans la pile de l'inscription (bouton retour natif, titre « Inscription ») :

1. **Date de naissance** : « Quelle est ta date de naissance ? », « Elle ne sera pas affichée publiquement. », sélecteur en roues (mois, jour, année). « Suivant » actif une fois la date choisie.
   - **13 ans au moins**, vérifié par l'app **et par l'API** (âge calculé à la date du jour, en UTC ; date future ou avant 1900 refusée) : 400 sinon.
   - **Gardée** : colonne privée `users.birth_date` (`date`, nulle pour les comptes existants et ceux de Sign in with Apple), propriété du module `auth` comme l'email ; **jamais exposée** (ni profil, ni backoffice pour l'instant). Elle servira à réserver plus tard certaines fonctions aux majeurs.
2. **Email** : champ avec suggestions de domaines (`@gmail.com`, `@icloud.com`, `@outlook.com`, `@yahoo.com`) au-dessus du clavier, « Continuer » actif quand le format est valide. La disponibilité n'est **pas** vérifiée à cette étape (pas de route qui dirait si un email a un compte) : un email déjà pris est signalé à la création (409), qui ramène à cette étape.
3. **Mot de passe** : « Crée un mot de passe », bouton œil, liste cochée en direct et jauge de solidité.
   - **Règles, vérifiées par l'API et l'app** (`PASSWORD_RULES`, domaine d'`auth`, à garder alignées) : 8 à 128 caractères, **au moins une lettre et un chiffre**. Pas de maximum à 20 (déconseillé). Seulement à l'inscription : la connexion ne vérifie aucun format (comptes existants inchangés).
   - **Jauge** (indicative, dans l'app) : « Faible » tant que les règles ne sont pas remplies, « Moyen » quand elles le sont, « Fort » avec en plus un caractère spécial ou 12 caractères. Le caractère spécial est conseillé, pas exigé.
4. **Pseudo** : « Crée ton pseudo », compteur, règles du profil (`profile-rules.ts` : 2 à 24 caractères `a-z 0-9 . _`, `me` réservé), **disponibilité vérifiée pendant la saisie** (300 ms sans frappe) par une route publique du module `users` (`GET /users/username-availability?username=` → `{ available, reason? }` : `invalid`, `reserved`, `taken` ; déclarée avant `/users/:username`). Les pseudos étant publics (profils), la route ne révèle rien de plus. « Confirmer » **crée le compte** et connecte.
   - **Nom affiché = pseudo par défaut** : `displayName` devient facultatif dans `POST /auth/register` ; il se change ensuite dans le profil. Pas d'étape « nom ».
5. **Centres d'intérêt** (compte créé) : « Choisis tes centres d'intérêt », pastilles avec emoji (sélection multiple), « Passer » et « Suivant ».
   - **Liste fixe dans le code** de l'API (codes stables, libellés français et emoji : animaux, humour, voyage, cuisine, sport, beauté et mode, art, jeux vidéo, sciences et éducation, danse, DIY, auto et moto, musique, astuces, satisfaisant, plein air, fandoms), servie par une route publique (`GET /interests/catalog`), comme le catalogue des cadeaux.
   - **Enregistrés par l'API**, privés : table `user_interests` (`user_id`, `interest_code`, `created_at`, clé composite, cascade avec le compte), `PUT /users/me/interests` (`{ interests: [...] }`, remplace la liste ; code inconnu → 400) et `GET /users/me/interests`, module `users`. Modifiables ensuite dans les paramètres (ligne « Centres d'intérêt »).
   - **Sans effet sur le feed** : l'algorithme For You reste reporté (ADR-016). Le texte ne promet donc pas de recommandations (« Dis-nous ce que tu aimes. »).
6. **Tutoriel** : « Balaie vers le haut », « Fais glisser vers le haut pour passer à la vidéo suivante. », téléphone dessiné avec une main animée, bouton « Commencer à regarder ». Pas de « vidéos personnalisées » (il n'y a pas de personnalisation).

Ensuite, le feed s'ouvre avec une **indication par-dessus** la première vidéo (« Balaie vers le haut pour en voir plus », main animée, fond assombri), effacée au premier défilement ou au premier toucher. Elle est montrée **une fois par installation** (préférence `feedSwipeHintShown`), à tout le monde : après l'inscription, une connexion ou « Continuer sans compte ».

Pendant les attentes (création du compte, reprise de session sur `LaunchView`), un **indicateur à deux points** rose et cyan, aux couleurs du logo maison.

Hors de cette étape : l'onglet « Téléphone » (codes SMS, voir « Alternatives »), le bouton d'aide « ? » (aucune page d'aide), l'option « Enregistrer dans le trousseau » (iOS la propose de lui-même grâce aux types de contenu des champs).

Mesure d'audience : `signup_step_viewed` (`step` : `birthday`, `email`, `password`, `username`, `interests`, `tutorial`), pour l'entonnoir de l'inscription ; `interests_selected` (`count`, `skipped`, `interests` : codes choisis). Jamais la date de naissance, l'email ni le pseudo.

## Alternatives
- **Email seulement** (aucun changement d'API) : écarté par le développeur.
- **Connexion par téléphone** : codes SMS (service externe payant, table des codes, limites anti-abus). Écarté pour l'instant.
- **Onboarding à chaque lancement sans compte**, ou **connexion obligatoire** : écartés par le développeur (gênant pour l'invité, contraire à l'ADR-010).
- **Date de naissance vérifiée dans l'app seulement**, ou pas d'étape : écartés par le développeur (contournable ; âge utile plus tard).
- **Comme TikTok, nom facultatif et pseudo généré** : écarté (un pseudo `user1234567890` rend inutile la connexion par pseudo).
- **Centres d'intérêt envoyés à PostHog seulement**, ou pas d'écran : écartés (perdus sans consentement ; données utiles à un futur For You).
- **Règles de TikTok exactes** (8 à 20, caractère spécial exigé) ou **règles actuelles avec jauge indicative** : écartées (maximum de 20 déconseillé ; règles qui n'engagent que l'app).
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
- **Contrat de `POST /auth/register` changé** : `birthDate` exigé, `displayName` facultatif, mot de passe avec une lettre et un chiffre.
- Une donnée personnelle de plus (date de naissance), à supprimer avec le compte (cascade) et à mentionner dans les futures conditions d'utilisation.
- Des centres d'intérêt enregistrés sans encore servir à rien.
- Six écrans avant le feed pour une inscription (deux facultatifs : intérêts, tutoriel).
- Sign in with Apple, quand il viendra, ne donne pas de date de naissance : il faudra la demander après coup.
- Le mot de passe des comptes de démo du seed (`demo-password`, sans chiffre) ne respecte plus les règles : les nouveaux comptes de démo prennent `demo-password1`, les anciens gardent le leur.

## Liens
- ADR-010 — Authentification
- ADR-013 — Analytics et A/B testing
- ADR-017 — Application iOS : choix d'implémentation
- ADR-030 — Limites de débit : connexion et partages
