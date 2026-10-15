# ADR-059 — Chats de groupe

## Statut
Accepté

Complète [ADR-016](ADR-016-perimetre-mvp.md) (périmètre : messagerie), [ADR-018](ADR-018-modules-messaging-push-admin.md) (module `messaging`) et [ADR-028](ADR-028-regles-produit-premiere-version.md) (règles de la messagerie), sans les remplacer.

## Contexte
La messagerie ne gère que les conversations à deux (ADR-018, ADR-020, ADR-028) : `findOrCreateDirect`, une vue de conversation construite autour de « l'autre participant », et le trigger `conversation_participants_cleanup`, qui supprime une conversation restée à moins de deux participants. Le modèle de l'ADR-006 (conversations à participants) permet pourtant plus.

Le développeur veut l'écran de TikTok « Créer un chat de groupe » : bouton en haut à gauche de l'onglet « Messages » (ADR-058), type Privé (« Pour les amis ») ou Public (« Pour les communautés »), recherche par nom ou pseudo, « Suggéré » avec des cases à cocher, bouton « Créer ».

## Décision
Règles produit (choisies par le développeur) :
- **Groupes privés seulement** : on n'y entre que si un membre nous ajoute. Les groupes publics (découverte, lien d'invitation, modération des groupes) sont reportés.
- **32 membres au plus**, créateur compris. Création avec **au moins 2 amis** (choix par défaut : un groupe de deux serait une conversation à deux).
- **On n'ajoute que ses amis** (abonnés mutuels, comme le feed des amis de l'ADR-054), **sans demande** : l'ajouté entre directement et peut quitter. Jamais un compte avec qui l'on a un blocage (dans un sens ou l'autre) ni un compte suspendu.
- **Administrateur** : le membre le plus ancien (date d'entrée), donc le créateur, puis, s'il quitte, le membre arrivé juste après. Rien n'est stocké : il se déduit des membres. Tout membre ajoute des amis ; **seul l'administrateur retire un membre**.
- **Nom facultatif** (50 caractères au plus, nettoyé), modifiable par tout membre ; sans nom, l'app affiche les noms des membres. **Pas de photo de groupe** : deux photos de membres superposées.
- **Quitter** : on n'est plus membre, ses messages restent. **Supprimer pour soi** : comme une conversation à deux (repère `cleared_up_to_message_id`, elle réapparaît au message suivant). Le groupe est supprimé quand il n'a plus de membre.
- **Un nouveau membre voit les messages à partir de son ajout** (repères de lecture et de suppression posés au dernier message existant).
- **Blocages et comptes suspendus** : deux membres qui se bloquent restent dans le groupe, mais **chacun ne voit plus les messages de l'autre** (ni dans la liste, ni dans l'aperçu, ni dans les non-lus, ni en direct, ni en push). Les messages d'un compte suspendu sont masqués pour tous ; il reste dans la liste des membres. Dans une conversation à deux, rien ne change (l'historique reste lisible).
- **« Vu » et « en train d'écrire »** : « Vu par Ines, Nathan » (ou « Vu par 5 ») sous son dernier message ; « Ines écrit… », « 2 personnes écrivent… ».
- **Lignes d'événement** dans la conversation : « … a créé le groupe », « … a ajouté … », « … a retiré … », « … a quitté le groupe », « … a renommé le groupe « … » ». Stockées comme des messages d'un type « événement » : jamais non lues, jamais en push, jamais trouvées par la recherche ni signalables.
- **Contenus** : texte, vidéo et live partagés, comme à deux ; la feuille « Envoyer à » propose aussi les groupes. Une réponse à une story reste dans la conversation à deux avec son auteur.
- **Push** : titre = nom du groupe (sinon noms des membres), texte « Ines : salut ». **Sourdine par groupe** : plus de push pour ce membre, le badge reste.
- Limites de débit : messages, ajouts et renommages comptent dans les limites des messages (ADR-028) ; **20 groupes créés par jour** et par compte.

Modèle de données (une migration, contraintes écrites à la main) :
- `conversations.kind` (enum `conversation_kind` : `direct` | `group`, `direct` par défaut) et `conversations.name` (groupe seulement). Un groupe est accepté dès sa création (`accepted_at`), sans demande.
- `conversation_participants.joined_at` (administrateur, ordre d'entrée) et `muted_at` (sourdine).
- `messages.event` (enum `group_event` : `created` | `added` | `removed` | `left` | `renamed`) et `messages.event_user_id` (membre ajouté ou retiré, sans clé étrangère) ; le nouveau nom d'un renommage dans `content` (vide : nom retiré).
- Trigger `conversation_participants_cleanup` revu : une conversation à deux restée à moins de deux participants est supprimée (inchangé), un groupe seulement quand il n'a plus de participant.
- `findOrCreateDirect` ne trouve que des conversations `direct` (un groupe de deux membres n'est pas une conversation à deux).

API (module `messaging`) :
- `POST /conversations/groups` `{ userIds, name? }` (201) ; `PATCH /conversations/:id` `{ name }` (renommer ; vide : retirer le nom) ; `POST /conversations/:id/members` `{ userIds }` ; `DELETE /conversations/:id/members/:userId` (administrateur) ; `POST /conversations/:id/leave` (204) ; `PUT` / `DELETE /conversations/:id/mute` (204).
- `ConversationDto` : `kind`, `participant` **absent** pour un groupe, `group` (`name`, `adminId`, `muted`, `members` : compte, date d'entrée, dernier message lu). `MessageDto` : `sender` (compte) dans un groupe, `event` (`type`, `user`) pour une ligne d'événement. Résultat de recherche : `group` (nom, membres) pour un message de groupe.
- Temps réel : pas de nouvel événement. Une ligne d'événement arrive comme un message (`messageCreated`) et l'app relit la conversation ; un membre retiré, ou qui quitte, reçoit `conversationDeleted`.

## Alternatives
- **Tables séparées pour les groupes** : aucune requête existante à revoir, mais deux boîtes de réception à fusionner, deux suivis de lecture, deux recherches. Rejeté : le modèle à participants est fait pour ça.
- **Rôle d'administrateur stocké** (`role` par participant) : permet de nommer d'autres administrateurs, mais il faut le transmettre à chaque départ et à chaque suppression de compte (cascade). Rejeté au profit du plus ancien membre.
- **Événements de groupe hors des messages** (table à part, ou seulement en temps réel) : rien dans l'historique ; rejeté.
- **Groupes publics, demandes pour les non-amis, photo de groupe** : écartés par le développeur (voir « Décision »).

## Conséquences
### Positives
- Mêmes routes de messages, de lecture, de suppression et de recherche pour les deux sortes de conversations ; mêmes limites et même identifiant d'envoi (ADR-044).
- Aucun nouvel événement temps réel : l'app relit la conversation à chaque ligne d'événement.

### Négatives
- Les vues de conversation lisent les comptes masqués du lecteur à chaque requête (blocages et suspensions), et les messages masqués comptent encore dans la pagination (pages plus courtes).
- Un compte supprimé disparaît des groupes sans ligne « a quitté », et ses messages partent avec lui (cascade, comme à deux).
- Badges et événements calculés pour chaque membre à chaque message (32 au plus).
- Pas de transfert explicite du rôle d'administrateur, pas de plusieurs administrateurs, pas de lien d'invitation.

## Liens
- ADR-006 — Persistance
- ADR-016 — Périmètre du MVP
- ADR-018 — Modules ajoutés hors ADR-003
- ADR-020 — Modèle de données : compléments
- ADR-028 — Règles produit de la première version
- ADR-029 — Blocage : contenus masqués
- ADR-044 — Renvoi d'un message en échec : identifiant d'envoi
- ADR-054 — Feed des amis
- ADR-058 — Onglet « Messages »
