# ADR-038 — Signalements

## Statut
Proposé

Complète [ADR-019](ADR-019-backoffice-role-perimetre-session.md), sans le remplacer.

## Contexte
L'ADR-019 a reporté la file de signalements. Sans elle, un administrateur ne découvre un contenu abusif que s'il tombe dessus. La suspension de compte (ADR-037) et la suppression de contenus existent, mais rien ne les déclenche.

Une première version écartait les messages privés, ne prévenait personne de la décision, et ne gardait que les décisions sur des signalements. Le développeur a ensuite demandé de lever ces limites : la décision ci-dessous les intègre.

## Décision
Choix du développeur, parmi les options proposées :
- **Cibles** : une vidéo, un commentaire, un compte, **un message reçu**. Pour un message, seul son texte est copié dans le signalement : le reste de la conversation n'est jamais transmis ni lisible par les administrateurs.
- **Motif** : un choix dans une liste fixe (spam, harcèlement, contenu haineux, violence, nudité ou contenu sexuel, usurpation d'identité, autre), plus une précision facultative de 500 caractères au plus.
- **Rien n'est masqué** avant la décision d'un administrateur : un signalement abusif ne peut pas faire disparaître un contenu. Après un signalement de compte, l'app propose de le bloquer.
- **Retour à la personne qui signale** : « Merci » à l'envoi, puis **la décision** dans son centre d'activité et en notification push (« Signalement examiné » : contenu retiré, compte suspendu, ou aucune infraction constatée).
- **L'auteur d'un contenu retiré est prévenu**, avec un motif choisi par l'administrateur dans la liste des motifs de signalement (« Contenu retiré : Ta vidéo a été retirée. Motif : spam. »). La suspension, elle, reste annoncée à la connexion seulement (ADR-037).
- **Journal de modération** : chaque suppression, suspension, levée et classement sans suite est inscrit, avec l'administrateur, le compte visé, le contenu et le motif.
- **Compte supprimé** : ses signalements sont **gardés, anonymisés et clos** (« compte supprimé »), comme le journal.

Mise en œuvre :
- **Nouveau module `reports`**, ajouté à la liste de l'ADR-003, comme `messaging`, `push` et `admin` (ADR-018). Il possède les tables `reports` et `moderation_actions`, vérifie les cibles via `UsersService`, `VideosService`, `InteractionsService` et `MessagingService`, prévient par `NotificationsService`, et exporte `ReportsService` pour `admin`. Aucun module ne dépend de `reports`, sauf `admin`.
- **Données** : une ligne par signalement.
  - `target_type` et `target_id`, **sans clé étrangère vers le contenu** : le signalement survit à la suppression de la vidéo ou du commentaire, et la file l'indique comme « supprimé » ;
  - `target_user_id` : le compte visé, passé à `NULL` s'il est supprimé ; `target_username` garde son pseudo d'alors ;
  - `reporter_id` et `resolved_by` passent à `NULL` si ces comptes sont supprimés ; l'historique reste ;
  - `excerpt` : copie du texte signalé (commentaire, description de la vidéo, message) au moment du signalement ;
  - `resolution` (contenu supprimé, compte suspendu, sans suite ; et, sans décision, supprimé par son auteur ou compte supprimé), `resolved_at` ;
  - contraintes CHECK écrites à la main : décision complète ou absente, pas de signalement de soi-même, précision de 500 caractères au plus.
- **Règles du signalement** :
  - on ne signale que ce qu'on peut voir : vidéo publiée, commentaire existant, compte existant, message d'une de ses conversations (pas ceux masqués par « supprimer pour soi »). Le contenu d'un compte suspendu est introuvable (404). On ne signale ni son compte ni son propre contenu (400) ;
  - **un seul signalement ouvert par personne et par cible** (index unique partiel `WHERE resolution IS NULL`) : un doublon renvoie 204 et ne change rien. On peut signaler de nouveau après une décision ;
  - **limite de débit** : 10 par heure et 50 par jour et par personne (limiteur de l'ADR-030), sinon 429 avec `Retry-After`. Un doublon ne compte pas.
- **Routes** :
  - `POST /reports` (compte connecté, 204) ;
  - `GET /admin/reports` : file **groupée par cible**, de la plus récemment signalée à la plus ancienne, avec le nombre de signalements ouverts et leurs motifs ;
  - `GET /admin/reports/:targetType/:targetId` : une cible et ses signalements, ouverts et clos ;
  - `POST /admin/reports/:targetType/:targetId/dismiss` : classement sans suite ;
  - `reports.openTargets` dans les statistiques ;
  - `DELETE /admin/messages/:id` : retrait d'un message, pour les deux participants, comme par son expéditeur ;
  - `?reason=` **obligatoire** sur `DELETE /admin/videos/:id`, `/admin/comments/:id` et `/admin/messages/:id` (400 sans motif de la liste) ;
  - `GET /admin/moderation-actions?userId=` : le journal, du plus récent au plus ancien.
- **Décisions**, qui closent tous les signalements ouverts concernés, préviennent les personnes qui les ont envoyés (une notification par personne et par cible) et s'inscrivent au journal :
  - supprimer la vidéo, le commentaire ou le message → « contenu supprimé » ; l'auteur reçoit « contenu retiré » avec le motif ;
  - suspendre le compte (ADR-037) → « compte suspendu », pour toutes ses cibles (compte, vidéos, commentaires, messages) ;
  - classer sans suite → « sans suite », le contenu reste en ligne.

  Les signalements sont clos **avant** la suppression : sinon les triggers ci-dessous les cloraient comme « supprimé par son auteur ». Si la suppression échoue, rien n'est annoncé ni journalisé.
- **Clôture par la base**, sans décision ni notification (triggers écrits à la main, migration `moderation`) :
  - suppression d'une vidéo, d'un commentaire ou d'un message par son auteur → « supprimé par son auteur » (`content_deleted`) ;
  - suppression du compte visé → « compte supprimé » (`account_deleted`), avant que `target_user_id` passe à `NULL`.
- **Notifications de modération** (module `notifications`) : deux types, `reportResolved` et `contentRemoved`, **sans auteur** (`actor_id` nul, CHECK par type), avec `moderation` (type de cible, motif ou décision, texte copié). Jamais regroupées, jamais masquées par la suspension d'un compte. Push : « Signalement examiné » ou « Contenu retiré ».
- **Journal** (`moderation_actions`) : action, administrateur, cible, compte visé, motif (liste) ou note (motif interne d'une suspension), texte copié, nombre de signalements clos. Pseudos copiés, identifiants passés à `NULL` à la suppression des comptes : le journal survit à tout. Une suspension déjà en place ou une levée sans effet ne sont pas journalisées.
- **App iOS** :
  - menu « … » du lecteur sur la vidéo d'un autre compte (« Signaler ») ;
  - geste « Signaler » sur le commentaire d'un autre ;
  - « Signaler » dans le menu « … » d'un profil ;
  - « Signaler » à l'appui long sur un message reçu ; la feuille précise que seul ce message est transmis.

  Une même feuille sert aux quatre : motifs, précision, confirmation, et « Bloquer » après un signalement de compte. En invité, la connexion s'ouvre. Événement PostHog `report_submitted` (type de cible et motif, jamais la précision). Les décisions apparaissent dans le centre d'activité, avec un bouclier à la place de la photo et le texte concerné.
- **Backoffice** : page « Signalements » (la file, messages compris), page d'une cible avec ses actions et l'historique, alerte sur le tableau de bord. Toute suppression demande le motif (le plus signalé est proposé depuis un signalement). Page « Journal », filtrable par compte (lien depuis la fiche).

## Alternatives
- **Messages non signalables** : rien d'une conversation n'est vu par les administrateurs, mais le harcèlement privé échappe à la modération. Retenu d'abord, puis écarté par le développeur : seul le message signalé est copié.
- **Transmettre toute la conversation** : plus de contexte pour décider, mais une conversation privée entière devient lisible. Écarté.
- **Masquer pour la personne qui signale, ou pour tous au-delà d'un seuil** : plus réactif, mais une notion de plus à filtrer partout, et une prise pour les signalements coordonnés. Écarté.
- **Ne pas annoncer la décision** (première version) : rien de plus à construire, mais la personne qui signale ne sait jamais si cela a servi. Écarté.
- **Motif saisi librement pour l'auteur** : plus précis, mais un texte à rédiger à chaque fois, et un risque de ton. Remplacé par la liste des motifs.
- **Supprimer les signalements avec le compte visé** (cascade, première version) : l'historique des décisions disparaissait. Écarté.
- **Clé étrangère vers la vidéo ou le commentaire** : le signalement disparaîtrait avec le contenu, et l'historique des décisions avec lui. Rejeté.
- **Une table par type de cible** : trois fois les mêmes requêtes pour la file. Rejeté.

## Conséquences
### Positives
- La modération dispose d'une file triée et groupée, d'un historique des décisions et d'un journal de toutes ses actions.
- Les actions existantes (suppression, suspension) closent d'elles-mêmes les signalements ; un contenu supprimé par son auteur, ou un compte supprimé, quitte la file sans intervention.
- La personne qui signale et l'auteur sanctionné savent ce qui a été décidé.

### Négatives
- Un message signalé devient lisible par les administrateurs (lui seul).
- Une notification « signalement examiné » révèle la décision, pas son auteur ; mais une personne seule à avoir signalé un contenu peut déduire que sa suppression vient de son signalement.
- Les notifications de modération n'ont pas d'auteur : `notifications.actor_id` devient nullable, et les règles de regroupement et de masquage le prennent en compte.
- Le journal ne couvre que les actions passées par l'API ; le rôle administrateur (script `admin:grant`) n'y figure pas.
- L'auteur d'un contenu retiré ne peut pas contester la décision depuis l'app.

## Liens
- ADR-003 — Architecture backend
- ADR-018 — Modules messaging, push et admin
- ADR-019 — Backoffice : rôle administrateur, périmètre et session
- ADR-030 — Limites de débit
- ADR-037 — Suspension de compte
- ADR-016 — Périmètre (messagerie, centre d'activité)
