# ADR-024 — Mesure d'audience : consentement, identification et première expérience

## Statut
Accepté

Complète [ADR-013](ADR-013-analytics-ab-testing.md), sans le remplacer.

## Contexte
L'ADR-013 retient PostHog (événements, feature flags, A/B) et laisse ouvert l'hébergement. Restaient à fixer le consentement, l'identification des comptes et la première expérience.

## Décision
- **PostHog Cloud UE** (`eu.i.posthog.com`), hôte configurable. Le jeton du projet n'est pas versionné ; sans jeton, l'app journalise les événements sans rien envoyer.
- **Consentement opt-in** (RGPD) : demandé au premier lancement, modifiable dans les paramètres. **Le SDK n'est initialisé qu'après l'accord** ; un retrait l'arrête sans aucune requête.
- **Identification par le seul UUID du compte**, sans nom, pseudo ni email. Les événements d'invité sont rattachés au compte à la connexion ; nouvel identifiant anonyme à la déconnexion.
- **Aucune donnée personnelle** dans les événements : jamais de texte saisi, pas de capture automatique d'écrans ni d'enregistrement de session. Catalogue d'événements défini en un seul endroit de l'app (visionnage, réactions, onboarding, publication, messagerie, paywall, cycle de vie).
- Événements envoyés par l'app seulement, pas par l'API.
- **Première expérience, `guest-signup-prompt`** (variantes `control` et `prompt`) : en variante, la connexion est proposée après 5 vidéos regardées en invité. Le flag n'est lu qu'à ce moment, une fois par installation ; sans consentement, l'utilisateur reste dans le groupe témoin. Mesure : exposition → feuille de connexion affichée → inscription.

## Alternatives
- Auto-hébergement de PostHog : une machine d'au moins 4 vCPU et 16 Go (ClickHouse, Kafka), trop lourd pour le projet à ce stade. Écarté pour l'instant.
- Consentement implicite (opt-out) : non conforme au RGPD pour une mesure d'audience non exemptée. Rejeté.
- Identification avec des propriétés de personne (pseudo, email) : inutile pour les analyses visées. Rejeté.
- Événements côté API : un second SDK et une double source de vérité. Rejeté.

## Conséquences
### Positives
- Aucune donnée n'est envoyée sans accord, et aucune donnée personnelle n'est envoyée.
- L'expérience est mesurable de bout en bout dans PostHog.

### Négatives
- Les utilisateurs qui refusent n'apparaissent pas dans les mesures.
- Le premier « Application Opened » d'une installation manque (le SDK démarre après l'accord).

## Liens
- ADR-013 — Analytics et A/B testing avec PostHog
- ADR-015 — Hébergement
