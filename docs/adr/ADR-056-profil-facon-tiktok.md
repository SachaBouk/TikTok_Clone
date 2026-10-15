# ADR-056 — Profil façon TikTok : compteur « J'aime », photo recadrée et story, modification par champ

## Statut
Accepté

Complète [ADR-016](ADR-016-perimetre-mvp.md) (périmètre : compte et profil) et [ADR-046](ADR-046-dimensions-photo-profil.md) (photo de profil), sans les remplacer.

## Contexte
Le développeur veut que le profil de l'app ressemble à celui de TikTok (captures fournies), y compris les étapes de sa personnalisation :
- en-tête : grande photo avec un « + » pour la changer, @pseudo, trois compteurs (abonnements, abonnés, **J'aime**), boutons « Modifier le profil » et « Partager le profil », « + Ajouter une bio », onglets des grilles en icônes soulignées ;
- photo : « Prendre une photo » ou « Choisir une photo », recadrage **rond** au doigt, case « Publier cette photo en story » (cochée), aperçu de la story, « Enregistrer et publier », message « Enregistré » ;
- « Modifier le profil » : une page avec la photo et une ligne par champ (nom, pseudo, lien du profil, bio…), chaque champ sur sa propre page (« Annuler », « Enregistrer », compteur).

Ce qui existe déjà : le profil (ADR-016) sans compteur de likes reçus ; la photo de profil carrée de 64 à 2048 px envoyée par URL signée (ADR-046), recadrée au centre par l'app ; les stories photo (ADR-051) ; une feuille « Modifier le profil » en formulaire unique.

## Décision
- **Compteur « J'aime »** = likes reçus sur ses **vidéos publiées** (`ready`), comme TikTok :
  - nouveau champ `likesCount` du profil (`UserProfileDto`) dans les routes qui renvoient un profil (`GET /users/me`, `GET /users/:username`, `PATCH /users/me`, `PUT` et `DELETE /users/me/avatar`) ;
  - **calculé à la lecture** (somme de `videos.likes_count`, déjà tenu par les triggers), pas de colonne ni de migration ;
  - frontières (ADR-003) : port `ReceivedLikesCounter` du module `users`, adaptateur `VideoReceivedLikesCounter` → `VideosService.countLikesReceived` (`VideoRepository.sumLikesByAuthor`) ; `UsersService.profileView` assemble le compte et le compteur, seulement pour les routes du profil (les autres lectures de comptes n'en ont pas besoin) ;
  - pas d'événement temps réel : le compteur se relit avec le profil.
- **Photo de profil** (app seulement, API inchangée) :
  - « Prendre une photo » (caméra du système, si l'appareil en a une), « Choisir une photo » (galerie), « Supprimer la photo » ;
  - **recadrage rond** : l'image remplit le cercle, se déplace et s'agrandit au doigt (zoom 1 à 5), sans jamais laisser de vide (`AvatarCrop`, règles pures testées) ; le carré visible devient la photo de 512 px en JPEG, toujours envoyée comme avant (ADR-046) ;
  - **story « nouvelle photo de profil »**, case **cochée par défaut** (choix du développeur) : l'app dessine une image 1080×1920 (« ✨ J'ai une nouvelle photo de profil », la photo ronde, @pseudo, la date) et la publie comme une **story photo** (ADR-051), par la même préparation (sans métadonnées) et la même file d'envoi ; seulement si la photo a été enregistrée ; aperçu avant l'envoi. Pas de musique ni d'autocollants (ADR-052).
- **« Modifier le profil »** poussé dans la pile du profil : photo, puis « À propos de toi » : nom, pseudo, **lien du profil à copier**, bio ; chaque champ sur sa page, enregistré seul (seul le champ changé est envoyé), message « Enregistré ».
- **« Partager le profil »** : lien d'app `tiktokclone://users/<pseudo>`, ouvert dans une feuille par l'app (liens universels avec l'hébergement, comme pour les vidéos).
- **Troisième bouton** de son profil : les **jetons** (paywall, ADR-009) restent là, à la place de « Ajouter des amis » de TikTok (la recherche de comptes est déjà dans le feed, ADR-049).
- **Hors périmètre** (choix du développeur) : pronoms, association (« Nonprofit »), réseaux sociaux (Instagram, YouTube…), commandes (Shop, reporté par l'ADR-016), numéro de téléphone, visiteurs du profil, changement de compte, brouillons.

## Alternatives
- **Colonne `users.likes_received_count` tenue par trigger** : lecture plus rapide, mais une migration, un trigger de plus sur `likes` (et sur le changement de statut d'une vidéo), et une donnée des vidéos stockée dans la table des comptes. Écarté tant que la somme indexée (`videos(user_id, …)`) suffit.
- **Compter les likes de toutes les vidéos**, publiées ou non : une vidéo non publiée ne peut pas être likée ; écarté pour rester exact si une vidéo repasse en échec.
- **Story générée par l'API** : un traitement d'image côté serveur, que l'ADR-046 a écarté pour la photo de profil. Écarté.
- **Case décochée par défaut** : moins de stories involontaires ; écarté par le développeur, qui veut le comportement de TikTok.
- **Ajouter les pronoms** : nouveau champ, migration et liste de pronoms ; reporté par le développeur.

## Conséquences
### Positives
- Un profil reconnaissable, avec le nombre de likes reçus, sans migration.
- La photo cadrée par la personne elle-même, et une story pour l'annoncer, sans traitement côté serveur.

### Négatives
- **Une lecture de plus** à chaque affichage d'un profil (somme sur les vidéos du compte).
- Le compteur compte aussi les likes des comptes bloqués ou suspendus, comme `likes_count`.
- Une story publiée sans y penser (case cochée par défaut) : elle se supprime depuis la visionneuse.
- La caméra et le recadrage au doigt ne se vérifient vraiment que sur un iPhone.

## Liens
- ADR-003 — Architecture backend
- ADR-009 — Jetons et paywall
- ADR-016 — Périmètre du MVP
- ADR-046 — Dimensions de la photo de profil
- ADR-049 — Recherche de comptes et hashtags
- ADR-051 — Stories
