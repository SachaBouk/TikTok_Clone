# ADR-066 — Lives façon TikTok : icône « LIVE », lives à faire défiler, écran redessiné

## Statut
Proposé

Complète [ADR-053](ADR-053-live-comparaison-diffusion.md) (Live) et [ADR-016](ADR-016-perimetre-mvp.md) (périmètre), sans les remplacer.

## Contexte
Avec l'ADR-053, on n'arrive sur un live que par la rangée « EN DIRECT » (comptes suivis), la photo d'un profil, l'activité, un message ou un lien. Le développeur fournit des captures de TikTok :
- une icône « LIVE » en haut à gauche de l'accueil ;
- des lives qu'on fait défiler en balayant vers le haut ;
- un écran de live redessiné :
  - en haut, une pastille de l'auteur (photo, nom, j'aime, « + Suivre ») et le nombre de spectateurs ;
  - en bas, « Commenter », Rose, Cadeau et Partager ;
  - toucher l'écran envoie des j'aime ;
  - le chat montre aussi « a rejoint », « a aimé le LIVE » et « a partagé le LIVE » ;
  - toucher l'auteur ouvre sa fiche ;
  - un live terminé affiche un sondage, puis propose le live suivant.

Il demande de les reproduire.

## Décision
Choix du développeur, parmi les options proposées.

### Lives à faire défiler (app, API)
- **Icône « LIVE »** à gauche du sélecteur « Abonnements | Pour toi ». Elle ouvre, en plein écran, **tous les lives en cours** visibles du lecteur. On passe au suivant en balayant vers le haut, et on revient en balayant vers le bas. Invités compris.
- **Route** : `GET /lives` (publique) → `{ items }`, 50 lives au plus, sans pagination :
  - lives en cours, sans ceux des comptes masqués (suspendus, et blocages dans un sens ou dans l'autre pour un compte connecté) ni le sien ;
  - ceux des comptes suivis d'abord, puis les plus regardés (spectateurs distincts depuis le début), puis les plus récents.
- **Dans l'app** : une seule salle à la fois. On se connecte au live affiché et on quitte le précédent dès qu'on balaie. En attendant l'image, la photo floutée de l'auteur s'affiche avec les deux points rose et cyan.
- Sans live en cours : « Aucun live en ce moment ».

### Écran du live (app)
- **En haut** :
  - pastille de l'auteur : photo, nom, j'aime du live (total des cœurs, désormais renvoyé à tous : `heartsCount` de `LiveDto`, jusqu'ici dans les chiffres de l'auteur seulement), « + Suivre » (absent pour son propre live et une fois l'auteur suivi) ;
  - nombre de spectateurs, ×. L'auteur garde « Changer de caméra » et la confirmation de fin.
- **En bas** : champ « Commenter » (avec la flèche d'envoi pendant la saisie), 🌹 Rose (spectateur), 🎁 Cadeau (spectateur), Partager. « Signaler » passe par la fiche de l'auteur.
- **J'aime en touchant l'écran** : chaque toucher sur la vidéo envoie un j'aime (envoyés par lots, comme avant), avec un cœur qui jaillit à l'endroit touché. Le bouton cœur disparaît. Ses propres touchers sont comptés dans la pastille : « Tu as envoyé N j'aime », quelques secondes. L'auteur ne peut pas aimer son live, comme avant.
- **Rose en un toucher** : envoie une Rose (1 jeton) sans ouvrir la feuille, avec les règles de l'ADR-050 (solde, limite, identifiant d'envoi). Solde insuffisant : la feuille des cadeaux s'ouvre, avec « Recharger ».
- **Fiche de l'auteur** (toucher la pastille) : photo, nom, pseudo, abonnés, abonnements (nombres entiers : « 9050 abonnés »), bio, « Suivre », drapeau « Signaler ». Elle est lue avec les routes du profil existantes.
- **Feuille des cadeaux façon TikTok** (aussi pour les vidéos) : fond sombre, destinataire et solde en haut, catalogue sur 4 colonnes (emoji, nom, prix avec la pièce), cadeau choisi sur fond plus sombre avec « Envoyer » dans sa case (« Recharger » si le solde ne suffit pas), « Cadeaux » et « Recharger › » en bas.
- **Saisie** : barre blanche au-dessus du clavier, champ gris, flèche grise puis rouge ; sous la barre, le gris du clavier (les coins arrondis du clavier d'iOS 26 ne laissent voir aucun bord).
- **Icône « LIVE »** : cadre aux coins arrondis ouvert sur les côtés autour de « LIVE », antenne en V, comme celle de TikTok.

### Lignes d'événement du chat (API, app)
Nouveaux événements de la salle (union `LiveRoomEvent`), chacun `{ user }`, au mieux :
- `viewerJoined` : un compte connecté rejoint le live (`POST /lives/:id/join`), « Inès a rejoint ». Les invités et l'auteur ne sont pas annoncés.
- `viewerLiked` : premiers j'aime d'un compte sur ce live, « Inès a aimé le LIVE ».
- `liveShared` : nouvelle route `POST /lives/:id/share` (compte connecté, 204). L'app l'appelle après un partage envoyé, par la feuille système ou par message. Elle annonce « Inès a partagé le LIVE ». Elle ne tient pas de compteur.

Chaque événement n'est annoncé **qu'une fois par compte et par live**, pendant la durée maximale d'un live (dédoublonnage `RateLimiter.once`). Rien n'est stocké. Dans le chat, ces lignes ne se suppriment pas, ne se copient pas, et celles des comptes bloqués sont masquées comme leurs messages.

### Sondage de fin (app)
- Live terminé, pour un spectateur : « Comment s'est passé ce live ? » avec Neutre, Positif, Négatif, puis « Envoyer » (rose une fois un choix fait). La miniature est la photo de l'auteur, faute d'image du live. Ensuite « Merci pour ton avis ».
- Dans les lives à faire défiler, s'y ajoute « Balaie vers le haut pour le live suivant ». Ailleurs, c'est « Fermer ».
- La réponse n'est envoyée qu'à la mesure d'audience (`live_feedback`, ADR-013), jamais à l'API. Sans consentement, elle n'est envoyée nulle part.
- L'auteur garde son écran de fin avec ses chiffres.

### Mesure d'audience
- `live_viewed` porte la source `discover`.
- Nouveaux événements `live_liked` (nombre de j'aime d'un lot), `live_rose_sent` et `live_feedback` (`answer`).

### Hors périmètre (décision du développeur)
Multi-invités, classements (« Daily Ranking »), abonnements payants (« Subscribe »), boutique, meilleurs donateurs en haut, bannières d'événements, niveaux et équipes, compteur de partages, « Explore » et « Boutique » dans les onglets de l'accueil.

## Alternatives
- **Seulement les lives des comptes suivis** (route existante) : souvent vide sur un petit réseau. Écarté.
- **Pagination de `GET /lives`** : inutile tant que les lives en cours se comptent par dizaines. On la reportera si besoin.
- **Lignes « a rejoint » tirées du webhook de LiveKit** (`participant_joined`) : elles annonceraient aussi les invités et les reconnexions. Écarté.
- **Sondage gardé par l'API** : sans usage côté produit pour l'instant (pas de recommandation). Écarté.

## Conséquences
- Pas de migration.
- `LiveDto` gagne `heartsCount` (j'aime du live, pour tous).
- Le client Swift gagne `listLives`, `shareLive` et les événements `viewerJoined`, `viewerLiked`, `liveShared`.
- Dans les lives à faire défiler, les pages ignorent le clavier pour garder leur taille ; la saisie d'un commentaire est affichée par l'écran des lives, au-dessus du clavier.
- **Limites** :
  - spectateurs comptés depuis le début du live (pas « en ce moment ») pour le classement ;
  - 50 lives au plus ;
  - un compte annoncé une fois par live, même s'il revient ;
  - un événement perdu (salle injoignable) n'est pas rejoué ;
  - le sondage n'est pas lié au live dans l'API ;
  - le lien d'un live et la rangée « EN DIRECT » ouvrent toujours un seul live.
