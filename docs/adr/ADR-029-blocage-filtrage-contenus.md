# ADR-029 — Blocage : contenus masqués dans le feed, les profils et les commentaires

## Statut
Accepté

Complète [ADR-028](ADR-028-regles-produit-premiere-version.md), sans le remplacer.

## Contexte
L'ADR-028 fixe les effets du blocage : dans les deux sens, ni abonnement, ni like, commentaire ou republication sur les vidéos de l'autre, ni message. Il laissait de côté le feed, les profils et les commentaires existants : un compte bloqué restait visible partout. Pour une plateforme sociale, c'est la première attente d'un utilisateur qui bloque quelqu'un.

## Décision
Pour un compte connecté, les contenus des comptes bloqués **dans un sens ou dans l'autre** sont masqués à la lecture. Rien n'est supprimé : débloquer fait tout revenir. Rien n'est filtré en mode invité.

- **Feed** : les vidéos de ces comptes sont sautées. La page est complétée avec les vidéos suivantes de l'ordre de la session, en 3 lectures au plus ; au-delà, elle reste plus courte et la pagination continue.
- **Vidéo seule** (`GET /feed/items/:id`) : introuvable (404), comme une vidéo supprimée.
- **Profil** (choix du lead développeur) : l'en-tête reste lisible dans les deux sens (nom, photo, compteurs d'abonnés). Celui qui bloque en a besoin pour débloquer, et celui qui est bloqué ne l'apprend pas. En revanche, les grilles de ce compte (vidéos, republications) et ses listes d'abonnés et d'abonnements sont **vides**.
- **Listes des autres comptes** : les vidéos de ces comptes sont retirées des republications d'un tiers, et de ses propres favoris, likes et historique de visionnage. Ces comptes sont aussi retirés des listes d'abonnés et d'abonnements.
- **Commentaires** : ceux de ces comptes sont retirés de toutes les vidéos. Les commentaires d'une vidéo de ces comptes sont introuvables (404), comme la vidéo. Le compteur `comments_count` reste celui de la base. L'historique des commentaires ne montre plus ceux écrits sur leurs vidéos.
- **Messagerie** : une vidéo partagée dont l'auteur a un blocage avec le lecteur est « indisponible » pour ce lecteur seulement (même forme qu'une vidéo supprimée). La partager est refusé (404).
- **Mise en œuvre** : filtrage à la lecture, par le service qui assemble chaque liste (`FeedService`, `InteractionsService`, `MessagingService`), à partir de l'ensemble des comptes bloqués dans les deux sens (`InteractionsService.getBlockedAccountIds`, une lecture indexée par requête). Pages de taille fixe côté base, plus courtes après filtrage, curseurs inchangés.
- **App iOS** : un compte bloqué depuis un écran disparaît aussitôt des écrans déjà chargés (feed, grilles, historiques, listes d'abonnés, commentaires ; la vidéo seule et la feuille de commentaires de ses vidéos se ferment), sans attendre un rechargement.

## Alternatives
- **Compte introuvable (404) pour celui qui est bloqué** : isolement plus fort, mais le blocage devient évident, et `users` devrait lire les blocages d'`interactions` (dépendance circulaire, ADR-003). Rejeté par le lead développeur.
- **Exclure les vidéos bloquées dès la photo du catalogue** : la photo est partagée par toutes les sessions (ADR-014) ; une photo par compte multiplierait le cache. Rejeté.
- **Filtrer en SQL dans chaque requête de liste** : pages toujours pleines, mais chaque module lirait la table `blocks`, propriété d'`interactions` (ADR-003). Rejeté.
- **Recalculer `comments_count` par lecteur** : coûteux, pour un écart mineur. Rejeté.

## Conséquences
### Positives
- Un compte bloqué ne voit plus les contenus de l'autre, et inversement, sur tous les écrans.
- Le blocage reste discret : aucune réponse ne dit « ce compte t'a bloqué ».
- Aucune nouvelle table ni migration ; débloquer est immédiat.

### Négatives
- Pages plus courtes que demandé (grilles, listes, commentaires), voire vides avec un curseur suivant ; l'app charge alors la suite.
- Le nombre de commentaires affiché compte aussi les commentaires masqués.
- Déconnecté, le compte bloqué voit tout ce qui est public, comme sur les autres plateformes.
- Une lecture de la table `blocks` de plus par requête pour un compte connecté.

## Liens
- ADR-003 — Architecture backend : hexagonale allégée
- ADR-014 — Cache et sessions avec Redis
- ADR-016 — Périmètre de la première version
- ADR-028 — Règles produit de la première version
