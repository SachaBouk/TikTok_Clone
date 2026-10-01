# ADR-038 — Signalements

## Statut
Proposé

Complète [ADR-019](ADR-019-backoffice-role-perimetre-session.md), sans le remplacer.

## Contexte
L'ADR-019 a reporté la file de signalements. Sans elle, un administrateur ne découvre un contenu abusif que s'il tombe dessus. La suspension de compte (ADR-037) et la suppression de contenus existent, mais rien ne les déclenche.

## Décision
Choix du développeur, parmi les options proposées :
- **Cibles** : une vidéo, un commentaire, un compte. Les messages privés ne sont pas signalables : leur contenu deviendrait lisible par les administrateurs.
- **Motif** : un choix dans une liste fixe (spam, harcèlement, contenu haineux, violence, nudité ou contenu sexuel, usurpation d'identité, autre), plus une précision facultative de 500 caractères au plus.
- **Rien n'est masqué** avant la décision d'un administrateur : un signalement abusif ne peut pas faire disparaître un contenu. Après un signalement de compte, l'app propose de le bloquer.
- **Retour à la personne qui signale** : « Merci, ton signalement sera examiné. » à l'envoi, et rien ensuite.

Mise en œuvre :
- **Nouveau module `reports`**, ajouté à la liste de l'ADR-003, comme `messaging`, `push` et `admin` (ADR-018). Il possède la table `reports`, vérifie les cibles via `UsersService`, `VideosService` et `InteractionsService`, et exporte `ReportsService` pour `admin`. Aucun module ne dépend de `reports`, sauf `admin`.
- **Données** : une ligne par signalement.
  - `target_type` et `target_id`, **sans clé étrangère vers le contenu** : le signalement survit à la suppression de la vidéo ou du commentaire, et la file l'indique comme « supprimé » ;
  - `target_user_id` : le compte visé. Sa suppression emporte ses signalements (cascade) ;
  - `reporter_id` et `resolved_by` passent à `NULL` si ces comptes sont supprimés ; l'historique reste ;
  - `excerpt` : copie du texte signalé (commentaire, description de la vidéo) au moment du signalement ;
  - `resolution` (contenu supprimé, compte suspendu, sans suite), `resolved_at` ;
  - contraintes CHECK écrites à la main : décision complète ou absente, pas de signalement de soi-même, précision de 500 caractères au plus.
- **Règles du signalement** :
  - on ne signale que ce qu'on peut voir : vidéo publiée, commentaire existant, compte existant. Le contenu d'un compte suspendu est introuvable (404). On ne signale ni son compte ni son propre contenu (400) ;
  - **un seul signalement ouvert par personne et par cible** (index unique partiel `WHERE resolution IS NULL`) : un doublon renvoie 204 et ne change rien. On peut signaler de nouveau après une décision ;
  - **limite de débit** : 10 par heure et 50 par jour et par personne (limiteur de l'ADR-030), sinon 429 avec `Retry-After`. Un doublon ne compte pas.
- **Routes** :
  - `POST /reports` (compte connecté, 204) ;
  - `GET /admin/reports` : file **groupée par cible**, de la plus récemment signalée à la plus ancienne, avec le nombre de signalements ouverts et leurs motifs ;
  - `GET /admin/reports/:targetType/:targetId` : une cible et ses signalements, ouverts et clos ;
  - `POST /admin/reports/:targetType/:targetId/dismiss` : classement sans suite ;
  - `reports.openTargets` dans les statistiques.
- **Décisions**, qui closent tous les signalements ouverts concernés :
  - supprimer la vidéo ou le commentaire (routes existantes) → « contenu supprimé » ;
  - suspendre le compte (ADR-037) → « compte suspendu », pour toutes ses cibles (compte, vidéos, commentaires) ;
  - classer sans suite → « sans suite », le contenu reste en ligne.
- **App iOS** :
  - « … » du lecteur sur la vidéo d'un autre compte (« Signaler ») ;
  - geste « Signaler » sur le commentaire d'un autre ;
  - « Signaler » dans le menu « … » d'un profil.

  Une même feuille sert aux trois : motifs, précision, confirmation, et « Bloquer » après un signalement de compte. En invité, la connexion s'ouvre. Événement PostHog `report_submitted` (type de cible et motif, jamais la précision).
- **Backoffice** : page « Signalements » (la file), page d'une cible avec ses actions et l'historique, alerte sur le tableau de bord.

## Alternatives
- **Signaler les messages** : utile contre le harcèlement privé, mais expose des conversations privées aux administrateurs. Reporté.
- **Masquer pour la personne qui signale, ou pour tous au-delà d'un seuil** : plus réactif, mais une notion de plus à filtrer partout, et une prise pour les signalements coordonnés. Écarté.
- **Notifier la décision à la personne qui signale** : un nouveau type de notification (base, app, push). Écarté.
- **Clé étrangère vers la vidéo ou le commentaire** : le signalement disparaîtrait avec le contenu, et l'historique des décisions avec lui. Rejeté.
- **Une table par type de cible** : trois fois les mêmes requêtes pour la file. Rejeté.

## Conséquences
### Positives
- La modération dispose d'une file triée et groupée, et d'un historique des décisions.
- Les actions existantes (suppression, suspension) closent d'elles-mêmes les signalements.

### Négatives
- Les signalements d'un compte supprimé disparaissent avec lui.
- Un contenu supprimé par son auteur reste dans la file, marqué « supprimé », jusqu'à son classement.
- L'auteur d'un contenu supprimé, ou le compte suspendu, n'est pas prévenu (comme le prévoyait déjà l'ADR-019).
- Pas encore de journal des actions de modération : seules les décisions sur des signalements sont gardées.

## Liens
- ADR-003 — Architecture backend
- ADR-018 — Modules messaging, push et admin
- ADR-019 — Backoffice : rôle administrateur, périmètre et session
- ADR-030 — Limites de débit
- ADR-037 — Suspension de compte
