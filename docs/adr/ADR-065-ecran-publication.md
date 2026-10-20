# ADR-065 — Écran de publication : couverture, lieu, mentions, étiquette IA, brouillons

## Statut
Proposé

Complète [ADR-062](ADR-062-creation-video-facon-tiktok.md) (création vidéo, écran de publication), [ADR-060](ADR-060-commentaires-facon-tiktok.md) (mentions) et [ADR-035](ADR-035-metadonnees-personnelles-videos.md) (position), sans les remplacer.

## Contexte
L'ADR-062 a laissé hors de l'écran de publication le choix de la couverture, le lieu, les mentions dans la description (non notifiées) et les brouillons. Le développeur fournit des captures de TikTok :
- couverture « Modifier la couverture » : image choisie sur une frise, titre dans un style ;
- « @ Mention » et suggestions ;
- « Lieu » avec des lieux proches, et une page « Ajouter un lieu » avec recherche ;
- « Brouillons » à côté de « Publier » ;
- « Plus d'options » en sections : confidentialité, réglages avancés, dont « Contenu généré par l'IA » et « Enregistrer sur l'appareil ».

Il demande de les ajouter.

## Décision
Choix du développeur, parmi les options proposées.

### Couverture (app, API, worker)
- **Dans l'app** : « Modifier la couverture » ouvre un écran « Annuler / Enregistrer ». On y choisit une image de la vidéo sur une frise, puis éventuellement un titre dans un style : Standard, Vecteur, Glitch, Teinte, Rétro, Incliné, Pilule, Pop, Bulle. L'app dessine l'image finale (JPEG 9:16) ; sans couverture choisie, rien ne change.
- **Envoi** : `POST /videos/upload-url` accepte `cover` (`{ fileSize }`, JPEG de 2 Mio au plus) et renvoie `coverUrl`, une URL signée pour un seul PUT. Elle expire comme les parties, et son type et sa taille sont signés comme pour la photo de profil. Le fichier va dans le bucket des bruts (`<userId>/<uuid>-cover.jpg`, colonne `videos.cover_key`, jamais exposée).
- **Worker** : le job de transcodage porte `coverKey`. La miniature publiée (`thumbnail.jpg`) est alors la couverture, réencodée par FFmpeg à la taille des miniatures et sans métadonnées. Si la couverture est absente ou illisible, le worker prend l'image de la vidéo, comme avant : une couverture ne fait jamais échouer une publication.
- La couverture est supprimée avec le brut (nettoyage de la vidéo).

### Lieu (app, API)
- **Page « Ajouter un lieu »** : recherche Apple Plans (MapKit), et « Lieux à proximité » si l'utilisateur autorise la localisation (demandée sur cette page seulement, « pendant l'utilisation »). Sur l'écran de publication, quelques lieux proches sont proposés, seulement si la localisation est déjà autorisée.
- **Seuls le nom et l'adresse affichée** sont envoyés (`location: { name, address? }` à l'envoi ; colonnes `videos.location_name`, `location_address`), **jamais de coordonnées** : dans l'esprit de l'ADR-035.
- Affiché sous la vidéo (« 📍 Nom »). `VideoDto` et `FeedItemDto` portent `location`, absent sans lieu. Pas de page d'un lieu (reportée).

### Mentions dans la description (app, API)
- « @ Mention » ajoute « @ », avec les mêmes suggestions que les commentaires (ADR-060). Une mention de la description s'ouvre sur le profil, dans le feed.
- **Prévenus à la publication** (passage en `ready`) : les comptes mentionnés dans la description, avec les règles des commentaires :
  - 5 au plus ;
  - ni soi-même, ni un compte inconnu ou suspendu, ni un compte qui a un blocage avec l'auteur (dans un sens ou dans l'autre) ;
  - **une vidéo privée ne prévient personne**, même si elle devient publique ensuite.

  Nouvelle notification `videoMention` (« t'a mentionné(e) dans une vidéo », avec push) : une par vidéo et par compte, jamais regroupée, emportée avec la vidéo. `videos` prévient `interactions` par un écouteur (`onVideoPublished`) : `videos` ne dépend toujours de personne.

### Étiquette « Contenu généré par l'IA » (app, API)
Interrupteur des réglages avancés : `aiGenerated` à l'envoi (colonne `videos.ai_generated`, faux par défaut), affiché « Créé avec l'IA » sous la description. Il est choisi à la publication seulement.

### Enregistrer sur l'appareil (app)
Interrupteur des réglages avancés, retenu sur l'iPhone et coupé par défaut. L'autorisation « ajout dans Photos seulement » est demandée en l'activant ; refusée, il reste coupé, avec un message. À la publication, une copie de la vidéo montée est enregistrée dans Photos.

### Brouillons (app)
- « Brouillons » enregistre la création **sur l'iPhone** : fichiers d'origine, montage, description, réglages, lieu, couverture. Le choix « Enregistrer le brouillon » est aussi proposé en abandonnant une vidéo depuis l'aperçu.
- Ils apparaissent en tête de la grille « Vidéos » de son profil (« Brouillons : N »), avec une page de brouillons : ouvrir, supprimer.
- Ouvrir un brouillon le **retire** des brouillons et rouvre l'éditeur ; on peut l'enregistrer de nouveau. Rien n'est envoyé à l'API. Les brouillons sont oubliés à la déconnexion (fichiers supprimés).

### « Plus d'options » en sections
- « Confidentialité » : commentaires, son (ADR-064).
- « Réglages avancés » : contenu généré par l'IA, enregistrer sur l'appareil.

L'audience garde sa propre ligne et sa feuille.

### Mesure d'audience
- `video_upload_started` porte en plus `cover_changed`, `cover_title`, `location_added`, `mention_count`, `ai_generated` et `saved_to_device`.
- Nouveaux événements `draft_saved` et `draft_opened`.

### Hors périmètre (décision du développeur)
- « Ajouter un lien » et les modèles, « Partager sur » (Messages, Facebook), Duo, Collage, autocollants créés depuis la vidéo, « Ajouter à sa story » par les autres ;
- importations en haute qualité, langue de la vidéo et sous-titres, contrôle de l'audience (18 ans et plus), divulgation de contenu commercial, produits similaires ;
- suggestions de texte (« Add yours ») ;
- page d'un lieu ;
- couverture et lieu modifiables après la publication ;
- brouillons synchronisés entre appareils.

## Alternatives
- **Couverture choisie par un instant (`coverTime`) et extraite par le worker** : pas de fichier à envoyer, mais pas de titre. Écarté.
- **Couverture traitée par l'API** (comme une photo de profil) : l'API ne touche aucun octet vidéo, et le worker sait déjà produire la miniature. Écarté.
- **Coordonnées du lieu gardées** (carte, lieux proches côté serveur) : donnée de position personnelle. Écarté.
- **Brouillons sur le compte** : synchronisés, mais il faudrait stocker des fichiers non publiés. Écarté.

## Conséquences
- Migrations :
  - `video_mention_notification_type` (valeur d'enum, séparée de son premier usage) ;
  - `publication_details` : colonnes `cover_key`, `location_name`, `location_address`, `ai_generated` ; index unique des notifications `video_mention` ; CHECK de cohérence (adresse seulement avec un nom ; longueurs ; notification `video_mention` avec auteur et vidéo).
- Le contrat de la file de transcodage gagne `coverKey`.
- Le client Swift gagne `cover`, `coverUrl`, `location`, `aiGenerated` et le type de notification `videoMention`.
- **Limites** :
  - une couverture envoyée mais jamais confirmée reste dans le bucket des bruts jusqu'au nettoyage de l'envoi abandonné (24 h) ;
  - une couverture illisible est ignorée sans prévenir l'auteur ;
  - les brouillons occupent l'iPhone (fichiers d'origine) et disparaissent avec l'app ;
  - une mention dans une vidéo privée qui devient publique n'est jamais notifiée.
