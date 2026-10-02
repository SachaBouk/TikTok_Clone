# ADR-039 — Limites de débit : inscription, réactions, commentaires, follows, vues et envois de vidéos

## Statut
Proposé

Prolonge [ADR-030](ADR-030-limites-debit-connexion-partage.md) (proposé), sans le remplacer.

## Contexte
L'ADR-030 a limité la connexion et les partages ; la messagerie (ADR-028) et les signalements (ADR-038) ont leurs propres limites. Le reste des actions écrites restait sans limite :
- **inscription** : un script pouvait créer des comptes en masse, et contourner ainsi toute limite par compte ;
- **likes, favoris, republications, follows** : un like retiré puis remis crée une nouvelle notification et une notification push à chaque fois ; un script pouvait inonder un compte ;
- **commentaires** : rien n'empêchait d'en publier des milliers ;
- **vues** : `views_count` ne compte qu'une vue par compte et par vidéo (ADR-016), mais chaque appel écrit en base ;
- **envois de vidéos** : chacun réserve jusqu'à 1 Gio de stockage et un transcodage.

## Décision
Choix du développeur, parmi les options proposées (valeurs « modérées ») :

| Action | Clé | Limites |
|---|---|---|
| Inscription par email (`POST /auth/register`) | adresse IP | 5 par heure, 20 par jour |
| Like, favori, republication (ensemble) | compte | 60 par minute, 600 par heure |
| Commentaire | compte | 10 par minute, 100 par heure |
| Follow | compte | 30 par minute, 200 par jour |
| Vue | compte | 600 par heure |
| Envoi de vidéo (`POST /videos/upload-url`) | compte | 10 par heure, 30 par jour |

- **Seuls les ajouts comptent** pour les réactions et les follows : retirer un like, une republication ou un abonnement reste toujours possible. Ce sont les ajouts qui notifient.
- **Au-delà : 429 avec `Retry-After`**, comme la connexion et la messagerie. L'app affiche « Trop de … Réessaie dans N min. » et annule son affichage optimiste.
- **Vues : ignorées sans erreur** au-delà de la limite (204, ni comptées ni ajoutées à l'historique), comme un partage en double (ADR-030) : l'app les envoie seule, elle n'a rien à afficher.
- **Inscription** : seules les créations réussies comptent (un pseudo déjà pris ne coûte rien). Sign in with Apple n'est pas limité (le jeton est vérifié par Apple, comme pour la connexion).
- **Envois de vidéos** : chaque `upload-url` compte, même si l'envoi est abandonné ou repris de zéro par l'app.
- Une tentative refusée, par la limite ou par un autre contrôle (vidéo introuvable, blocage, requête invalide), n'est pas comptée.

Mise en œuvre : le limiteur partagé de l'ADR-030 (`src/rate-limit`, fenêtres fixes, clés `ratelimit:<action>:<compte>:…`), reçu par les services d'`auth`, d'`interactions` et de `videos` par leur factory. Les règles sont des constantes du domaine de chaque module (`login-rules.ts`, `interaction.ts`, `upload-rules.ts`). Le décorateur `ApiTooManyRequests` documente le 429 et son en-tête dans la spec : le client Swift en tire un cas par route. Redis indisponible : action permise, et journalisée.

## Alternatives
- **Valeurs strictes** (3 inscriptions par heure, 5 commentaires par minute…) : plus sûr, mais un réseau partagé (école, NAT d'opérateur) bute vite sur l'inscription. Écarté.
- **Valeurs larges** (10 inscriptions par heure, 120 réactions par minute…) : ne gêne jamais, mais freine peu. Écarté.
- **Compter aussi les retraits** : plus simple, mais retirer un like pourrait être refusé. Écarté.
- **429 pour les vues** : même comportement partout, mais l'app devrait ignorer une erreur sur une action qu'elle fait seule. Écarté.
- **Pas de limite des vues** : une vue est déjà comptée une fois par compte et par vidéo ; seule la charge en base restait. Écarté.
- **Photo de profil** : 5 Mio, un seul fichier gardé par compte. Non limitée.
- **CAPTCHA à l'inscription** : plus efficace contre les robots, mais un service externe. Reporté.

## Conséquences
### Positives
- Plus aucune action écrite n'est sans limite : un script ne peut plus créer des comptes, inonder de notifications, de commentaires ou de vidéos.
- Un seul mécanisme, déjà éprouvé, et un seul format de réponse (429, `Retry-After`) que l'app sait afficher.

### Négatives
- Les personnes derrière une même adresse IP partagent la limite d'inscription. En développement aussi : le seed, puis les comptes jetables des tests de bout en bout, comptent sur `localhost` (supprimer les clés `ratelimit:signup-ip:*`).
- Ce sont des fenêtres fixes, alignées sur l'horloge : à cheval sur deux fenêtres, jusqu'au double de la limite est possible, et le délai annoncé peut être court (fin de la fenêtre en cours).
- Une réaction ou un follow rejoué (PUT idempotent sur un état déjà actif) compte comme un ajout.
- Une vue ignorée au-delà de la limite ne revient pas : elle manque à l'historique.

## Liens
- ADR-030 — Limites de débit : connexion et partages
- ADR-028 — Règles produit de la première version (limites de la messagerie)
- ADR-016 — Périmètre (vues, interactions)
- ADR-007 — Upload direct des vidéos
