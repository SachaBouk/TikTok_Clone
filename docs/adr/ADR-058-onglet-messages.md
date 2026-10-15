# ADR-058 — Onglet « Messages » façon TikTok : activité filtrée, nouveaux followers, comptes suggérés, recherche dans les messages

## Statut
Proposé

Complète [ADR-016](ADR-016-perimetre-mvp.md) (périmètre : messagerie, activité), [ADR-018](ADR-018-modules-messaging-push-admin.md) (module `messaging`) et [ADR-028](ADR-028-regles-produit-premiere-version.md) (règles de la messagerie et du centre d'activité), sans les remplacer.

## Contexte
Le développeur veut que l'onglet « Boîte de réception » ressemble à l'onglet « Messages » de TikTok (captures fournies) :
- titre « Messages », loupe en haut à droite (« Compte et messages »), bouton de chat de groupe en haut à gauche ;
- la rangée de stories (« Créer », puis les comptes suivis) ;
- une ligne « Activité et nouveaux abonnés » avec la dernière activité ;
- les conversations (aperçu et date sur une ligne, nombre de messages non lus en rouge) ;
- l'écran d'activité en deux onglets : « Activité ▾ » (filtre par type) et « Nouveaux followers » (« Suivre en retour », « Message » pour un ami ; demandes d'abonnement pour un compte privé), chacun suivi de « Comptes suggérés » (« Suivre », ×).

Ce qui existe déjà : la boîte de réception (stories, ligne « Activité », demandes, conversations, ✎ « Nouveau message ») ; le centre d'activité regroupé (ADR-036, ADR-043) ; la recherche de comptes (ADR-049). L'API ne sait ni filtrer les groupes de notifications par type, ni suggérer des comptes, ni chercher dans le texte des messages, et la messagerie ne gère que les conversations à deux.

## Décision
- **Onglet renommé « Messages »** (icône de bulle), titre « Messages », loupe. Le ✎ « Nouveau message » disparaît : on écrit à quelqu'un depuis la recherche ou le bouton « Message » de son profil.
- **Ligne « Activité et nouveaux abonnés »** : la phrase du groupe le plus récent et le badge des notifications non lues ; la ligne « Demandes de message » reste en dessous.
- **Filtre par type des groupes de notifications** : `GET /notifications/groups?kind=…`, paramètre **répété** (`kind=like&kind=comment`) ; absent, tous les types. Menu de l'app : toute l'activité (tous les types **sauf les abonnements**, à part dans « Nouveaux followers »), J'aime, commentaires, republications, cadeaux, lives, modération.
- **Nouveaux followers** : les notifications d'abonnement, une ligne chacune ; « Suivre en retour », ou « Message » pour un ami (abonnés mutuels). Trois lignes, puis « Voir plus ». **Pas de demandes d'abonnement** : il n'y a pas de compte privé (ADR-016, ADR-057).
- **Comptes suggérés** (choix du développeur : amis d'amis) : `GET /users/me/suggestions?limit=` (module `interactions`, propriétaire des follows ; 20 par défaut, 50 au plus, sans pagination). Candidats : les comptes suivis par ceux que l'on suit, et ses abonnés que l'on ne suit pas ; jamais soi-même, un compte déjà suivi, bloqué (dans un sens ou l'autre) ou suspendu. Classement : ceux qui nous suivent d'abord (« Te suit »), puis le nombre de comptes suivis qui les suivent (« Suivi(e) par » avec 3 photos au plus), puis l'identifiant. Une requête SQL ; comptes lus par `UsersService`. Le **×** écarte une suggestion **sur l'appareil** (choix du développeur), oublié à chaque changement de session.
- **Recherche dans les messages** (choix du développeur) : `GET /conversations/search?q=&limit=` (module `messaging` ; `q` de 1 à 100 caractères ; 20 résultats par défaut, 50 au plus, du plus récent au plus ancien). Seulement les conversations du compte, sans les messages supprimés pour lui ni les demandes reçues qu'il a refusées ; une demande reçue en attente d'un compte bloqué ou suspendu est sautée (comme la liste des demandes). `ILIKE` sans casse, `%`, `_` et `\` échappés. Chaque résultat : conversation, message, texte, date, l'autre participant et l'expéditeur. Dans l'app : avant la saisie, les comptes des conversations récentes (« Suggéré ») ; pendant la saisie (300 ms), les comptes (recherche de l'ADR-049, 10 au plus) puis les messages ; toucher ouvre la conversation.
- **Chats de groupe** : reportés à l'étape suivante (choix du développeur), avec leur propre ADR ; le bouton n'apparaît qu'avec eux.
- **Hors périmètre** : demandes d'abonnement (compte privé), note « Vas-y, raconte » au-dessus de « Créer », bouton appareil photo des conversations (pièces jointes), statut en ligne.

## Alternatives
- **Suggestions écartées gardées par l'API** (nouvelle table) : retenues sur tous les appareils ; écarté par le développeur, au profit de l'appareil.
- **Recherche des comptes seulement** : aucun changement d'API, mais la loupe ne trouve pas les messages ; écarté.
- **Filtre dans l'app** (sur les groupes déjà chargés) : sans changement d'API, mais un filtre rare peut nécessiter des dizaines de pages ; écarté.
- **Chats de groupe dans cette étape** : une seule grosse étape, et un ADR plus large ; écarté par le développeur.

## Conséquences
### Positives
- Un onglet reconnaissable, avec trois petits ajouts d'API et aucune migration.
- Les suggestions viennent du graphe d'abonnements, sans algorithme de recommandation (ADR-016).

### Négatives
- **Recherche sensible aux accents** (« cine » ne trouve pas « cinéma »), comme la recherche de comptes (ADR-049) ; pas d'index plein texte (balayage des messages du compte).
- Suggestions calculées à chaque appel (deux niveaux de follows) ; elles comptent les comptes masqués dans « Suivi(e) par … » (nombre), qui ne sont jamais affichés.
- Les groupes d'un type filtré ne sont pas suivis en direct (relus en tirant pour actualiser).
- Toucher un message trouvé ouvre la conversation, sans aller jusqu'au message.

## Liens
- ADR-016 — Périmètre du MVP
- ADR-018 — Modules ajoutés hors ADR-003
- ADR-028 — Règles produit de la première version
- ADR-036 — « Suivre en retour » dans le centre d'activité
- ADR-049 — Recherche de comptes et hashtags
- ADR-051 — Stories
