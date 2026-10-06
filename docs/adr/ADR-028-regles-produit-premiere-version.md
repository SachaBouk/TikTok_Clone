# ADR-028 — Règles produit de la première version

## Statut
Accepté

Complète [ADR-016](ADR-016-perimetre-mvp.md), sans le remplacer.

## Contexte
L'ADR-016 fixe le périmètre de la première version. La réalisation de chaque fonctionnalité a demandé des règles précises, choisies avec le lead développeur et inspirées de TikTok.

## Décision
Compte et profil :
- Pseudo : 2 à 24 caractères parmi `a-z`, `0-9`, `.` et `_`, unique, **modifiable sans délai** (l'ancien est libéré aussitôt). Nom : 1 à 50 caractères. Bio : 80 caractères au plus.
- Listes d'abonnés et d'abonnements **publiques** ; **favoris et likes privés** ; historique de visionnage et historique des commentaires **privés**.
- **Suppression du compte** depuis l'app (exigence Apple), immédiate, après une alerte explicative, sans ressaisie du mot de passe. Vidéos, photos et données supprimées ; historique des jetons anonymisé.

Vidéos :
- Une vidéo pas encore publiée n'est visible que de son auteur.
- **Suppression d'une vidéo par son auteur**, quel que soit son statut ; suppression réelle, fichiers nettoyés ensuite.
- **Vues par comptes distincts** : une vue après environ 1 s de lecture, par un compte connecté ; ni les invités, ni les revisionnages, ni l'auteur ne comptent.
- Historique de visionnage **effaçable à la main** (une vidéo ou tout), sans purge automatique.
- Le seed de démo passe par l'API HTTP, comme l'app : il suit le même pipeline sans rien insérer directement en base.

Activité :
- **Notifications regroupées à la lecture** : likes et republications par vidéo, abonnements ensemble, chaque commentaire seul. Stockage : une ligne par action.
- Au plus une notification par like, republication et abonnement ; retirer l'action retire la notification. Personne n'est notifié de ses propres actions ; un favori ne notifie pas.

Messagerie :
- Conversation libre entre abonnés mutuels ; sinon **demande de message**, limitée à 3 messages avant acceptation. Répondre l'accepte ; un refus est silencieux pour l'expéditeur.
- Pas de « Vu » ni de « en train d'écrire » tant qu'une demande n'est pas acceptée.
- Un message est retiré pour les deux par son expéditeur ; une conversation est supprimée pour soi seulement.
- **Limites d'envoi** : 20 messages par minute, 300 par heure, 10 nouvelles demandes par jour.

Blocage :
- Dans les deux sens : ni abonnement, ni like, commentaire ou republication sur les vidéos de l'autre, ni message. Bloquer retire les abonnements mutuels et les notifications échangées.
- Le feed, les profils et les commentaires existants ne sont pas encore filtrés.

## Alternatives
- Délai entre deux changements de pseudo (comme TikTok, 30 jours) : protège l'identité, mais complique les tests et la démo. Rejeté pour la première version.
- Favoris publics : exposent les goûts sans consentement. Rejeté.
- Une notification par action, sans regroupement : boîte de réception illisible sur une vidéo populaire. Rejeté.
- Messagerie ouverte à tous : spam. Demandes retenues.
- Blocage étendu au feed et aux profils dès la première version : filtres dans toutes les listes. Reporté.

## Conséquences
### Positives
- Des règles explicites, identiques dans l'API et dans l'app.
- Protection des contenus privés et contre le spam de messages.

### Négatives
- Un compte bloqué reste visible dans le feed et les profils.
- Revoir une vidéo retirée de l'historique la compte à nouveau.

## Liens
- ADR-016 — Périmètre de la première version
- ADR-017 — Application iOS : choix d'implémentation
- ADR-020 — Modèle de données : compléments
- Complété par [ADR-029](ADR-029-blocage-filtrage-contenus.md) — Blocage : contenus masqués dans le feed, les profils et les commentaires
- Complété par [ADR-030](ADR-030-limites-debit-connexion-partage.md) — Limites de débit : connexion et partages
- Complété par [ADR-036](ADR-036-suivre-en-retour-activite.md) — « Suivre en retour » dans le centre d'activité
- Complété par [ADR-042](ADR-042-suppression-commentaires-auteur-video.md) — Suppression des commentaires par l'auteur de la vidéo
- Complété par [ADR-044](ADR-044-renvoi-message-identifiant-envoi.md) — Renvoi d'un message en échec : identifiant d'envoi
