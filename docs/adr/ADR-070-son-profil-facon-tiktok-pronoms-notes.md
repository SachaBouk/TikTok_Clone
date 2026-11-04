# ADR-070 — Son profil façon TikTok : pronoms, notes de profil, « Trouver des amis »

## Statut
Proposé

Complète [ADR-056](ADR-056-profil-facon-tiktok.md) (profil), [ADR-069](ADR-069-profil-facon-tiktok-autres-comptes.md) (profil d'un autre compte) et [ADR-016](ADR-016-perimetre-mvp.md) (périmètre : compte et profil), sans les remplacer.

## Contexte
Après le profil des autres comptes (ADR-069), le développeur refond **son propre profil** d'après des captures de TikTok :
- barre du haut : **crayon** à gauche (« Modifier le profil »), à droite des **empreintes** (visiteurs du profil), **« personne + »** (« Trouver des amis ») et **☰** (menu, ADR-057) ;
- en-tête comme celui d'un autre compte : nom en grand (cadenas d'un compte privé, ▾ pour changer de compte), @pseudo, compteurs « Suivis · Followers · J'aime », photo à droite avec un « + » ; sur la photo, une **bulle « À quoi penses-tu ? »** (les **notes** de TikTok : un court texte visible des autres pendant 24 h) ;
- une pastille « + Ajouter une bio · ♡ Je m'intéresse à… », puis les onglets des grilles ; grille vide : « Partage une vidéo souvenir » et « Importer » ;
- « Modifier le profil » : photo, « Modifier la photo ou l'avatar », Nom, Nom d'utilisateur, lien du profil, puis « Informations de base » : Bio, **Pronom**, et « Autres » : Collecte de fonds ;
- « Trouver des amis » : recherche, « Entrer en contact », « Utiliser un code QR », « Inviter des ami(e)s », Contacts, Facebook, puis les comptes suggérés (avec trois vidéos de certains comptes).

L'API ne garde ni pronoms ni note ; les pronoms étaient hors périmètre de l'ADR-056.

## Décision
Choix du développeur, parmi les options proposées.

### Pronoms
- Colonne **`users.pronouns`** (texte libre, **20 caractères au plus**, nettoyé ; vide ou `null` l'efface), CHECK à la main (migration `profile_pronouns_notes`).
- Modifiés par **`PATCH /users/me`** avec `pronouns` (comme la bio). Champ **`pronouns`** (`string | null`) du profil (`UserProfileDto`), dans toutes les routes qui renvoient un profil.
- Affichés à côté du @pseudo, sur son profil et sur celui des autres.

### Notes de profil
- Colonnes **`users.note_text`** (1 à 60 caractères) et **`users.note_posted_at`**, remplies ou vides ensemble (CHECK).
- **`PUT /users/me/note`** `{ text }` : publie ou remplace la note (texte nettoyé, retours à la ligne remplacés par des espaces, 1 à 60 caractères, sinon 400), renvoie le profil. **`DELETE /users/me/note`** : la retire (idempotent), renvoie le profil.
- **Visible 24 h** après sa publication, par tout le monde (invités compris), sur le profil (`GET /users/:username`, `GET /users/me`…) : champ **`note`** du profil = `{ text, postedAt, expiresAt }`, **absent** sans note ou une fois expirée. L'expiration est **filtrée à la lecture** : une note expirée reste en base jusqu'à la prochaine note ou son retrait (rien à programmer).
- Pas de notification, pas de réponse ni de j'aime sur une note, pas de limite de débit (comme les autres champs du profil). Un profil reste lisible dans les deux sens en cas de blocage (ADR-029), sa note aussi.

### Visiteurs du profil
**Pas d'icône des empreintes** pour l'instant : il faudrait garder les visites et un réglage de confidentialité. Pourra faire l'objet d'une étape à part.

### App (sans changement d'API)
- Barre du haut : crayon (« Modifier le profil »), « personne + » (« Trouver des amis »), ☰. Les boutons « Modifier le profil », « Partager le profil » et **jetons** disparaissent de l'en-tête : le solde reste dans le menu ☰ (« Solde », ADR-057), le partage dans « Trouver des amis » (« Inviter des ami(e)s »).
- « Je m'intéresse à… » ouvre les centres d'intérêt (ADR-055).
- **« Trouver des amis »** : recherche de comptes (ADR-049), « Utiliser un code QR » (son code, ADR-057, et un **scanner** avec la caméra qui ouvre le profil d'un lien `tiktokclone://users/<pseudo>`), « Inviter des ami(e)s » (feuille de partage du système avec le lien du profil), puis les comptes suggérés (ADR-058, ADR-068) avec les trois dernières vidéos de chaque compte (grille publique `GET /users/:username/videos`).
- **Hors périmètre** : compte privé (cadenas), changement de compte (▾), « Entrer en contact », Contacts, Facebook, collecte de fonds, tri de la grille, avatars (seulement la photo).

## Conséquences
- Pronoms et note ne sont lus que pour les routes du profil (`UsersService.profileView`, port `UserRepository.findProfileDetails`), en parallèle du compteur « J'aime » : une petite lecture de plus par profil affiché, aucune pour les autres lectures de comptes (feed, listes).
- Une note expirée reste stockée jusqu'à son remplacement (texte de 60 caractères au plus, déjà public pendant 24 h).
- Le scanner de code QR ne se vérifie que sur un iPhone (pas de caméra dans le simulateur).
- « Trouver des amis » lit une grille par compte suggéré affiché (trois vidéos), à la demande.
