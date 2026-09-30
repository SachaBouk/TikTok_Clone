# ADR-020 — Modèle de données : compléments

## Statut
Accepté

Complète [ADR-006](ADR-006-persistance.md), sans le remplacer.

## Contexte
L'ADR-006 fixe PostgreSQL, Prisma et les entités de la première version. La réalisation a ajouté des tables, des colonnes, des index, et confié plusieurs règles d'intégrité à la base elle-même.

## Décision
Tables ajoutées :
- `REFRESH_TOKEN` (ADR-010) : jeton haché (SHA-256), famille (une session par appareil), expiration, révocation.
- `NOTIFICATION` : destinataire, auteur, type (`like`, `comment`, `follow`, `repost`), vidéo, commentaire et **copie du texte du commentaire**, date de lecture.
- `BLOCK` : `blocker_id`, `blocked_id`, clé composite.
- `PUSH_DEVICE` : jeton APNs (clé), compte, environnement (`sandbox` | `production`).
- `WALLET_TRANSACTION` : journal des mouvements de jetons (ADR-021).

Colonnes ajoutées :
- `USER.role` (`user` | `admin`, ADR-019).
- `VIDEO.upload_id` et `VIDEO.raw_size` (envoi multipart, taille déclarée vérifiée à l'assemblage).
- `CONVERSATION.request_sender_id`, `accepted_at`, `declined_at` (demandes de message).
- `CONVERSATION_PARTICIPANT.last_read_message_id` (« Vu », badges) et `cleared_up_to_message_id` (suppression pour soi). Repères ordonnés (UUID v7), sans clé étrangère.
- `MESSAGE.shared_video_id` (vidéo partagée), sans clé étrangère : une vidéo supprimée reste signalée « indisponible ».

Identifiants et index :
- Identifiants **UUID v7**, ordonnés dans le temps : ils servent de curseur de pagination.
- Index de listes : `follows(following_id, created_at)`, `follows(follower_id, created_at)`, `favorites(user_id, created_at)`, `reposts(user_id, created_at)`, `likes(user_id, created_at)`.
- Index uniques partiels des notifications : au plus une notification par like, republication et follow.

Règles portées par la base (écrites à la main dans les migrations) :
- **Compteurs dénormalisés tenus par des triggers** (likes, favoris, republications, commentaires, abonnés, abonnements), suppressions en cascade comprises. Le code applicatif ne les écrit jamais.
- **`views_count` compte les comptes distincts** : trigger à l'insertion dans `VIEW_HISTORY` seulement, jamais décrémenté.
- **Contraintes CHECK** : pas d'auto-follow ni d'auto-blocage, solde ≥ 0, cadeau > 0, notification cohérente avec son type et jamais adressée à son auteur, message avec texte ou vidéo, mouvement de jetons non nul et cohérent.
- Trigger de nettoyage : une conversation restée à moins de deux participants (compte supprimé) est supprimée.
- Suppression d'un compte en cascade, sauf `GIFT_SENT` et `WALLET_TRANSACTION`, anonymisés (`SET NULL`).

## Alternatives
- Compteurs recalculés à la lecture (`COUNT`) : coûteux pour le feed. Rejeté.
- Compteurs écrits par le code applicatif : dérive dès qu'une suppression en cascade n'est pas suivie. Rejeté au profit des triggers.
- Compteurs dans Redis : voir ADR-025.
- `views_count` incrémenté à chaque visionnage : facile à gonfler. Comptes distincts retenus.

## Conséquences
### Positives
- Compteurs toujours justes, y compris après une suppression de compte ou de vidéo.
- Des règles que ni un bug applicatif ni un script ne peuvent contourner.

### Négatives
- Une partie des règles vit dans le SQL des migrations, invisible pour Prisma : les migrations concernées s'écrivent à la main.
- Une écriture par visionnage dans `VIEW_HISTORY` (volume élevé).

## Liens
- ADR-006 — Persistance
- ADR-021 — Portefeuille : journal et règles de crédit
- ADR-025 — Rôle de Redis
- ADR-028 — Règles produit de la première version
