# ADR-077 — Expériences A/B : catalogue, groupe gardé sur l'appareil, variantes forcées en Debug

## Statut
Proposé

Complète [ADR-013](ADR-013-analytics-ab-testing.md) (PostHog) et [ADR-024](ADR-024-mesure-audience-consentement.md) (consentement et première expérience), sans les remplacer.

## Contexte
L'ADR-024 a lancé une seule expérience, `guest-signup-prompt`, codée à part : lecture du flag, préférence « déjà tranchée », témoin sans consentement. Pour en lancer d'autres sans recopier ce code, il faut un dispositif commun : où déclarer une expérience, quand tirer le groupe (exposition), que faire sans consentement ou tant que les flags ne sont pas chargés, comment essayer une variante sur son iPhone, comment le tester.

Points relevés :
- le SDK PostHog charge ses flags par le réseau au démarrage, donc **après le consentement** (ADR-024) : au tout premier lancement, ils ne sont pas encore là quand l'utilisateur arrive sur le feed ;
- à la connexion, l'identifiant PostHog change (`identify`) : sans précaution, un utilisateur peut changer de groupe en cours de route ;
- la variante ne se forçait que sans jeton PostHog (`-featureFlag.<flag>`), donc jamais sur le vrai PostHog.

## Décision
- **Catalogue dans l'app** (`domain/analytics/Experiments.swift`) : chaque expérience = clé du feature flag multivarié de PostHog, variantes, **variante témoin**, nom et explication. Une variante inconnue (flag mal configuré, booléen) est ignorée.
- **Groupe tiré au moment où l'expérience change ce qu'on voit** (`AnalyticsModel.decide`) et **gardé sur l'appareil** (préférence `experimentAssignments`) : il ne change plus, même si l'identifiant PostHog change. Exposition : `$feature_flag_called` (SDK) et `experiment_exposed` (`experiment`, `variant`), une fois par expérience et par installation.
- Dans l'ordre : variante forcée (Debug), groupe déjà tiré, **témoin sans consentement** (le flag n'est pas lu, rien n'est gardé), variante de PostHog, sinon témoin **pour cette fois** (flags pas chargés : réessayé à la prochaine occasion). Là où l'expérience ne se joue qu'une fois (indication du feed), l'app attend les flags 2 s au plus (`decideWhenLoaded`).
- **Variantes forcées dans le build Debug seulement** (port `ExperimentOverrides`, `UserDefaultsExperimentOverrides`, rien en Release) : argument de lancement `-experiment.<flag> <variante>`, ou écran **« Expériences »** en bas de Paramètres et confidentialité (variante par expérience, « Automatique (PostHog) », groupe tiré, « Oublier les groupes tirés »). Une variante forcée l'emporte même sans consentement et n'est **jamais** exposée ni gardée. Remplace `-featureFlag.<flag>`.
- **Expériences** (flags à créer dans PostHog, 50 / 50) :
  - `guest-signup-prompt` (ADR-024), inchangée, reprise dans le catalogue (une installation tranchée avant reste tranchée) ;
  - `feed-swipe-hint` : indication « Balaie vers le haut pour en voir plus » montrée (`shown`, témoin) ou jamais (`hidden`). Groupe tiré quand l'indication s'afficherait, **une fois la question du consentement tranchée** (sinon tout le monde serait témoin au premier lancement). Mesure : vidéos regardées pendant la première session, rétention D1 ;
  - `suggestion-carousel-slot` : premier carrousel de comptes suggérés du feed « Pour toi » après la 8e vidéo (`after-8`, témoin) ou la 4e (`after-4`), puis toutes les 30. Groupe tiré à l'arrivée des vidéos, pour un compte connecté seulement. Mesure : abonnements depuis le carrousel (`follow_changed`), vidéos regardées.
- Tests Swift Testing avec le service et les préférences en mémoire (catalogue, tirage, groupe gardé, sans consentement, flags absents puis chargés, forçage, oubli, chaque expérience).

## Alternatives
- Laisser PostHog seul décider à chaque lecture : un utilisateur change de groupe à la connexion. Rejeté.
- Écran de forçage aussi en Release : inutile pour une app personnelle, et un utilisateur pourrait choisir son groupe. Rejeté.
- Tirer tous les groupes au lancement : on exposerait des gens qui ne verront jamais la différence (un invité et le carrousel), ce qui dilue la mesure. Rejeté.

## Conséquences
### Positives
- Une nouvelle expérience = une entrée du catalogue, un appel à `decide` là où elle se joue, un flag dans PostHog.
- Chaque variante s'essaie sur l'iPhone, avec ou sans PostHog.

### Négatives
- Les personnes qui refusent la mesure d'audience sont toutes témoins, et absentes des mesures (comme avant).
- Un utilisateur dont les flags n'arrivent pas à temps voit le témoin sans être exposé.
- Les groupes sont gardés par installation : une réinstallation peut changer de groupe.

## Liens
- ADR-013 — Analytics et A/B testing avec PostHog
- ADR-024 — Mesure d'audience : consentement, identification et première expérience
- ADR-055 — Onboarding (indication « Balaie vers le haut »)
- ADR-058, ADR-068 — Comptes suggérés
