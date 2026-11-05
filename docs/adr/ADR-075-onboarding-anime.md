# ADR-075 — Onboarding animé : mascotte, questions, tutoriels interactifs, sons, vibrations et paywall « Plus »

## Statut
Proposé

Complète [ADR-055](ADR-055-onboarding.md) (onboarding, inscription par étapes), [ADR-073](ADR-073-abonnement-plus.md) (abonnement « Plus ») et [ADR-013](ADR-013-analytics-ab-testing.md) (mesure d'audience, consentement), sans les remplacer.

## Contexte
L'onboarding de l'ADR-055 est court : écran de lancement, introduction « Tout commence sur TikTok Clone. » (2 s), écran « Connexion » avec « Continuer sans compte », puis, pour une inscription, quatre étapes, les centres d'intérêt et un tutoriel « Balaie vers le haut ». Pas de son, presque pas de vibrations, une seule animation (le téléphone du tutoriel), et le paywall « Plus » (ADR-073) n'apparaît qu'à la demande.

Le développeur veut un parcours **plus long (plus d'une dizaine d'écrans), animé, avec du sound design et des vibrations tout au long**, original « comme Duolingo », d'après des captures fournies :
- **Luma** : logo seul sur fond uni, puis un écran « Get Started » avec des icônes en orbite autour du logo ; écran d'amorce des notifications ;
- **Duolingo** : mascotte qui parle dans une bulle, barre de progression en haut, questions à choix (« How did you hear about Duolingo? »), gros bouton « Continuer » grisé tant que rien n'est choisi, écran d'attente animé (« Sit tight… ») ;
- **Headspace** : choix multiples à coches, écran qui reformule les choix, paywall en frise (« Today / In 12 days / In 14 days ») ;
- **Revolut** : écrans plein cadre en grosses capitales, barre segmentée façon stories ;
- **TikTok** : « Swipe up » avec un téléphone et une main animée, puis la même indication **par-dessus le vrai feed**.

Il veut garder le style de l'app (noir, rose `brandPink`, échos cyan et rose du logo) et de TikTok, avec à la fin le paywall « Plus ».

## Décision
Choix du développeur, parmi les options proposées (toutes celles recommandées).

### Mascotte « Tempo »
- La **note de musique du logo maison** (`AppLogo`, ADR-055) devient une mascotte : yeux, clignements, humeurs (`TempoMood` : contente, clin d'œil, surprise, fête, pensive, couronnée pour « Plus »), rebonds avec écrasement et étirement, échos cyan et rose qui s'écartent quand elle est contente. **Dessinée en SwiftUI**, sans image, comme le logo. Jamais le logo ni les personnages de TikTok ou de Duolingo.
- Elle parle dans une **bulle** (texte qui s'écrit lettre à lettre, ~30 ms par lettre, toucher = texte entier), en grand sur les écrans d'accueil, en petit en haut des questions et des étapes de l'inscription (« Promis, je ne le dirai à personne. » pour la date de naissance, « Solide ! » quand le mot de passe passe à « Fort »…).

### Parcours
Premier lancement sans compte seulement (règle de l'ADR-055 inchangée : un compte déjà connecté ne voit rien). Une **barre de progression** (dégradé cyan → rose, avancée avec un ressort) en haut des écrans 3 à 18 ; ‹ revient à l'écran précédent jusqu'à la création du compte.

| # | Écran | Animation, son, vibration |
|---|-------|---------------------------|
| 0 | **Lancement** (`LaunchView`, existant) : logo sur fond noir | animation existante ; petit accord à l'apparition du nom |
| 1 | **Accueil** (façon Luma) : logo au centre, **orbite** d'icônes de l'app (cœur, bulle, signet, cadeau, « LIVE », « + », avatars en dégradé) qui tourne lentement ; « Tes vidéos. Ton rythme. » ; boutons « C'est parti » (rose) et « J'ai déjà un compte » (contour) | icônes qui arrivent une à une (pop), lueur qui respire ; vibration légère au toucher |
| 2 | **Tempo se présente** : « Salut ! Moi c'est Tempo. » puis « Je vais te montrer comment ça marche. » | Tempo tombe, rebondit et salue ; confettis cyan et rose |
| 3 | **Question** « Comment as-tu connu TikTok Clone ? » : Amis ou famille, Réseaux sociaux, App Store, Recherche sur le web, Vidéo en ligne, Autre (un seul choix) | choix : pop + vibration de sélection ; « Continuer » s'allume (bouton en relief façon Duolingo, s'enfonce au toucher) |
| 4 | **Question** « Tu viens surtout pour… » : Regarder des vidéos, Créer et publier, Les deux | Tempo réagit au choix (humeur) |
| 5 | **Préparation** (façon Duolingo) : « Super ! Je prépare ton espace… » 1,5 s | Tempo danse, deux points rose et cyan (`DotsLoader`) ; arpège montant |
| 6–9 | **Inscription** (étapes existantes de l'ADR-055 : date de naissance, email, mot de passe, pseudo), même logique, **habillées** : barre de progression, Tempo en petit avec une réplique par étape | pop sur les suggestions de domaine, vibration à chaque critère du mot de passe coché, « Disponible » : petit son ; refus (pseudo pris, moins de 13 ans) : vibration d'erreur, champ secoué |
| 10 | **Bienvenue** « Bienvenue, @pseudo ! » (compte créé) | grande pluie de confettis, Tempo en fête, mélodie de réussite, vibration de succès |
| 11 | **Centres d'intérêt** (existant, habillé) | pastilles qui grossissent au toucher, pop + vibration |
| 12 | **Tuto « Balaie vers le haut »** : **interactif** — il faut vraiment faire glisser la vidéo du téléphone dessiné pour continuer (main animée tant que rien n'est fait) | whoosh au passage de la vidéo, vibration au calage de la page ; « Bravo ! » de Tempo |
| 13 | **Tuto « Touche deux fois pour aimer »** : interactif, double toucher sur la vidéo | cœur qui éclate à l'endroit touché, pop, vibration moyenne |
| 14 | **Tuto « Reste appuyé sur un côté : vitesse ×2 »** : interactif, appui long sur un côté (bandeau « ×2 » comme le vrai lecteur) | son qui monte en accéléré, vibration continue légère |
| 15 | **Tuto « Balaie vers la gauche : profil de l'auteur »** : interactif | le profil arrive sous le doigt ; whoosh |
| 16 | **Tuto « Touche + pour créer »** (seulement si « Créer et publier » ou « Les deux ») : démonstration animée (caméra, déclencheur rose, segments qui se remplissent) | tic à chaque segment |
| 17 | **Mesure d'audience** (ADR-013) : la feuille « Aider à améliorer l'app ? » devient un **écran du parcours** (façon Luma « Get Notified » : faux graphiques qui montent), « Oui, j'aide » / « Non merci » | même choix, même préférence qu'aujourd'hui ; plus de feuille après l'onboarding |
| 18 | **Paywall « Plus »** (façon Headspace) : Tempo couronné, bascule Annuel / Mensuel (économie « -33 % »), **frise** : « Aujourd'hui — badge + et 1 800 jetons offerts (150 en mensuel) », « Chaque mois — de nouveaux jetons », « Quand tu veux — résilie depuis les réglages d'Apple » ; avantages (cadeaux exclusifs, vidéos de 10 min, lives de 4 h, icônes) ; « S'abonner », « Restaurer les achats », × « Plus tard » | avantages qui entrent en cascade ; abonnement réussi : confettis dorés et mélodie ; aucun essai gratuit (ADR-073 : il n'y en a pas) |
| 19 | **Vrai feed** avec l'indication « Balaie vers le haut pour en voir plus » (ADR-055), redessinée comme la dernière capture de TikTok : fond assombri, téléphone translucide et main qui glisse | au premier vrai défilement : vibration (pas de son : la session audio des vidéos joue même en mode silencieux) |

**Branches** :
- **Inscription** : écrans 0 à 19 (16 seulement pour un créateur) — 18 à 19 écrans.
- **« J'ai déjà un compte »** (écran 1) : formulaire de connexion (`LoginView`), puis l'écran 17 et le feed (19). Ni questions, ni tutoriels, ni paywall.
- **Invité** : à l'étape 6, l'écran de l'inscription garde « Plus tard » (ex-« Continuer sans compte ») → tutoriels 12 à 16, écran 17, feed. Pas de paywall (l'achat demande un compte). Pas de centres d'intérêt (ils sont enregistrés sur le compte).
- **Inscription depuis la feuille d'un invité** (ADR-055, plus tard) : mêmes écrans à partir de la date de naissance (6 à 15, 16 selon les réponses gardées, 18), sans questions ni mesure d'audience déjà tranchée.

La session est annoncée **à l'arrivée sur le paywall** (`SignupFlowModel.announceSession`, une seule fois), pas à la création du compte : l'achat demande un compte connecté (ADR-073, `PlusModel`), et le parcours ne se ferme plus de lui-même à la connexion (il se termine après le paywall, ou après le consentement pour une connexion ou un invité). La feuille d'un invité ne se ferme plus à la connexion quand le compte vient d'y être créé : la fin du parcours la ferme. App tuée en cours : la session est reprise au lancement et le reste du parcours est sauté (comme avant).

### Questions gardées sur l'iPhone
- Réponses (`OnboardingAnswers` : `source`, `goal`) dans les préférences de l'appareil (`PreferencesStore`), **jamais envoyées à l'API** : pas de table, pas de route, pas de migration.
- `goal` sert dès maintenant : « Créer et publier » ou « Les deux » ajoutent le tutoriel de création (écran 16).
- Mesure d'audience : les événements d'avant le consentement sont perdus (ADR-013, SDK démarré après l'accord). Les réponses partent donc **une fois**, au moment du consentement (écran 17), dans `onboarding_completed` (`path` : `signup` | `login` | `guest`, `source`, `goal`, `duration_s`, `tutorials_completed`) ; refus : rien n'est envoyé. Chaque écran vu ensuite : `onboarding_step_viewed` (`step`). Les événements de l'ADR-055 (`signup_step_viewed`, `interests_selected`…) restent ; `plus_paywall_viewed` reçoit la source `onboarding`.

### Sons synthétisés dans le code
- **Aucun fichier audio** : les sons sont **générés au premier usage** (formes d'onde calculées dans des `AVAudioPCMBuffer` : sinus et triangles avec enveloppe, bruit filtré pour le whoosh, arpèges en gamme majeure) et joués par un `AVAudioEngine` avec quelques `AVAudioPlayerNode`. Sons originaux : pas de droits d'auteur.
- Catalogue (`UISound`) : `tap`, `select`, `toggle`, `whoosh`, `pop` (cœur), `speedUp` (×2), `tick`, `success` (accord), `celebrate` (arpège avec scintillement), `error` (deux notes descendantes), `typing` (bulle de Tempo, très discret, une lettre sur trois).
- Session audio **`.ambient`** : les sons **respectent le mode silencieux** et se mêlent à la musique en cours ; jamais de son par-dessus une vidéo qui joue (le feed reprend sa session `.playback`, ADR-002).
- Port `UISoundPlayer` (domaine), adaptateur `SynthesizedSoundPlayer` (`data/feedback`), `SilentSoundPlayer` pour les tests et les aperçus. Utilisés par l'onboarding seulement pour l'instant.

### Vibrations
- Générateurs d'UIKit (`UISelectionFeedbackGenerator`, `UIImpactFeedbackGenerator`, `UINotificationFeedbackGenerator`), qui suivent le réglage « Vibrations du système » de l'iPhone : sélection, impact léger / doux / moyen / fort, succès, erreur ; pour la pluie de confettis, trois impacts qui s'espacent. (Réalisation : plus simple qu'un `sensoryFeedback` lié à un état de vue, et appelable du modèle ; pas de Core Haptics.)
- Un seul point d'entrée (`OnboardingFeedback` : son + vibration ensemble), pour garder les deux alignés.

### Animations et accessibilité
- Transitions poussées avec ressort ; boutons en relief qui s'enfoncent ; confettis dessinés dans un `Canvas` (`TimelineView`), couleurs du logo.
- **« Réduire les animations »** : fondus seulement, pas de confettis ni d'orbite, Tempo immobile (il cligne). Les tutoriels interactifs proposent alors aussi « Continuer ».
- VoiceOver : chaque tutoriel interactif a un bouton « Passer » et une action d'accessibilité qui fait le geste ; bulles de Tempo lues en entier.
- **Paramètres › Activité › « Revoir la présentation »** : rejoue les tutoriels 12 à 16 (sans compte ni paywall). En Debug, l'argument de lancement **`-resetOnboarding`** remet l'onboarding à zéro (avec l'indication du feed, les réponses et le consentement à la mesure d'audience ; une session enregistrée le saute toujours) (pièges du simulateur de l'ADR-055 : trousseau et préférences qui survivent à la désinstallation).

### Code (app iOS seulement)
- Règles pures et testées : `domain/entities/OnboardingJourney.swift` (`OnboardingStep`, `OnboardingPath`, `OnboardingJourney.steps(path:goal:accountCreated:)`, progression, écran précédent possible ou non).
- `OnboardingFlowModel` (remplace `OnboardingView`, garde `OnboardingModel` et ses préférences), vues dans `presentation/onboarding/` (`TempoMascot`, `SpeechBubble`, `OrbitWelcomeView`, `OnboardingQuestionView`, `OnboardingTutorials`, `OnboardingConsentView`, `OnboardingPlusView`, `ConfettiView`, `ProgressHeader`, `ChunkyButton`). Les étapes de l'inscription (`SignupStepViews`) reçoivent l'habillage par un modificateur, sans changer `SignupFlowModel`.
- Paywall : réutilise `PlusModel` et le service d'achats existants (offres, achat, attente de l'activation).
- **Ni API, ni contrat OpenAPI, ni base, ni worker ne changent.**

### Hors de cette étape
- **Écran d'amorce des notifications** (Luma) : pas de push dans l'app (pas de compte Apple Developer, ADR-010).
- Essai gratuit de « Plus » (ADR-073 : aucun).
- Sons ailleurs dans l'app (feed, messagerie) : à décider plus tard, le port le permettra.
- Choix de la langue, objectifs quotidiens, séries (propres à Duolingo, sans objet ici).

## Alternatives
- **Pas de mascotte** (logo et illustrations, façon Luma ou Revolut), ou **nouveau personnage** : écartés par le développeur.
- **Fichiers audio libres de droits** ou **sons système d'iOS** : écartés (licences à suivre ; peu de choix et identifiants non documentés).
- **Réponses enregistrées par l'API** (table, route, backoffice) ou **pas de questions** : écartés.
- **Paywall et tutoriels aussi après une connexion**, ou **paywall pour l'invité** : écartés (une connexion revient sur un compte connu ; un invité ne peut pas acheter).
- **Tutoriels non interactifs** (animations à regarder) : plus simples, mais moins mémorisés ; le geste fait une fois vaut mieux (choix de conception, comme Duolingo qui fait agir).
- **Tutoriels dans le vrai feed seulement** (bulles par-dessus les vraies vidéos) : dépend du réseau et du contenu ; gardé pour le seul « Balaie vers le haut » final.

## Conséquences
### Positives
- Un parcours d'arrivée vivant et propre à l'app (Tempo, sons, vibrations), qui apprend les gestes clés (balayer, aimer, ×2, profil, créer) avant le feed.
- Le paywall « Plus » est vu par chaque nouveau compte, au moment le plus favorable.
- Le consentement à la mesure d'audience fait partie du parcours au lieu d'une feuille de plus.
- Aucun changement côté serveur.

### Négatives
- **Long** : 18 à 19 écrans pour une inscription (questions, tutoriels et paywall passables) ; plus de code d'interface à entretenir (et à revérifier à chaque version d'iOS).
- Sons et vibrations ne se vérifient pas dans le simulateur (vibrations absentes, son seulement s'il n'est pas coupé) : à vérifier sur un iPhone.
- Les réponses aux questions sont perdues si la mesure d'audience est refusée, et restent sur l'iPhone (perdues à la désinstallation).
- Le paywall dès l'inscription peut agacer : il se ferme d'un toucher et ne revient pas.
- Les comptes de démo et les testeurs devront remettre l'onboarding à zéro pour le revoir (`-resetOnboarding`, « Revoir la présentation »).

## Liens
- ADR-013 — Analytics et A/B testing
- ADR-055 — Onboarding
- ADR-073 — Abonnement « Plus »
