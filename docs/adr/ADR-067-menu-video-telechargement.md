# ADR-067 — Menu d'une vidéo : vitesse, défilement automatique, affichage allégé, téléchargement

## Statut
Proposé

Complète [ADR-016](ADR-016-perimetre-mvp.md) (périmètre), [ADR-062](ADR-062-creation-video-facon-tiktok.md) (réglages de publication) et [ADR-035](ADR-035-metadonnees-personnelles-videos.md) (métadonnées personnelles), sans les remplacer.

## Contexte
Le lecteur vidéo accélère déjà en ×2 à l'appui long sur un côté de la vidéo, avec un verrou (choix du développeur, sans ADR : rien ne change côté API). Le milieu de la vidéo était réservé. Le développeur fournit des captures de TikTok : un appui long au milieu ouvre un menu (feuille blanche) qui propose :
- Télécharger, Pas intéressé(e), Signaler ;
- Vitesse (0.5× · 1.0× · 1.5× · 2.0×), Alléger l'affichage, Défilement automatique ;
- Légendes et traductions, Diffuser, Gérer les fils d'actualité, Lien avec publication, Promouvoir.

« Alléger l'affichage » ne laisse que la vidéo, avec en bas une barre de progression, un × et une pastille pause / vitesse. Le défilement automatique passe à la vidéo suivante à la fin de la vidéo en cours ; en l'activant, TikTok affiche « La prochaine publication s'affichera automatiquement », et « Fais défiler jusqu'à la publication suivante » en le coupant.

## Décision
Choix du développeur, parmi les options proposées.

### Menu (app)
- **Appui long au milieu** de la vidéo (le tiers central, les côtés gardant la vitesse ×2) : feuille du menu, la vidéo continue derrière. Dans tous les lecteurs vidéo (feeds, lecteur d'une grille, vidéo seule) ; ni stories ni lives.
- Entrées : Télécharger, Pas intéressé(e), Signaler (vidéo d'un autre) ; Vitesse, Alléger l'affichage, Défilement automatique ; Diffuser.

### Vitesse (app)
- Quatre vitesses : 0.5×, 1.0×, 1.5×, 2.0×. **Un seul réglage avec le verrou ×2** : verrouiller le ×2 revient à choisir 2.0× ; avec 2.0× choisi, l'appui long sur un côté lit à vitesse normale, et glisser vers le bas revient à 1.0×.
- Pour toutes les vidéos, **jusqu'à la relance de l'app** ; oubliée à la déconnexion.

### Défilement automatique (app)
- Activé : à la fin de la vidéo en cours, le lecteur passe à la suivante (au lieu de boucler). Message « La prochaine publication s'affichera automatiquement » avec un bouton pour le couper, puis « Fais défiler jusqu'à la publication suivante » une fois coupé.
- Jusqu'à la relance de l'app, oublié à la déconnexion.

### Alléger l'affichage (app)
- Seule la vidéo reste (ni auteur, description, colonne de droite, barre du haut ni barre d'onglets). En bas : barre de progression qu'on peut faire glisser, × pour sortir, pastille pause / lecture et vitesse (un toucher passe à la vitesse suivante).
- **Gardé d'une vidéo à l'autre jusqu'au ×** ; quitté en quittant le lecteur, à la relance et à la déconnexion.

### Pas intéressé(e) (app)
Sur l'iPhone seulement (pas d'algorithme de recommandation, ADR-016) : la vidéo est retirée du lecteur et l'on passe à la suivante. Oublié à la relance et à la déconnexion.

### Diffuser (app)
AirPlay : le sélecteur d'appareils du système. Rien côté API.

### Télécharger (app, API)
- **Fichier d'origine** : `POST /videos/:id/download` (compte connecté) renvoie `{ url, expiresAt, contentType, fileName, size }` : une **URL signée de lecture (GET) du brut**, valable **15 min**, servie en pièce jointe (`<videoId>.mp4` ou `.mov`). L'app télécharge le fichier et l'enregistre dans Photos (autorisation « ajout seulement »).
- Le brut arrive déjà sans position GPS ni modèle d'appareil (ADR-035) : rien à retirer. Pas de filigrane.
- **Contrôles**, dans l'ordre : vidéo publiée et visible du compte (privée : son auteur seulement), auteur ni suspendu ni bloqué dans un sens ou dans l'autre (404, comme la vidéo seule), téléchargement autorisé par l'auteur (**403** sinon, sauf pour l'auteur lui-même), puis la limite. Un brut disparu donne 404.
- **Limite** (comme l'ADR-039) : 30 téléchargements par heure et 200 par jour et par compte (chaque URL demandée compte, ses propres vidéos comprises) ; au-delà, 429 avec `Retry-After`.
- **Réglage de l'auteur** « Autoriser le téléchargement » (colonne `videos.downloads_enabled`, vrai par défaut) : choisi à l'envoi (`POST /videos/upload-url` avec `downloadsEnabled`), changé par l'auteur quel que soit le statut (`PATCH /videos/:id/download-settings` `{ downloadsEnabled }` → la vidéo, 404 pour un autre), comme les commentaires (ADR-062) et le son (ADR-064). Dans l'app : réglages de publication et feuille de partage de ses vidéos ; refusé, l'entrée « Télécharger » est grisée pour les autres. `VideoDto` et `FeedItemDto` portent `downloadsEnabled`.
- Module `interactions` (il connaît déjà les comptes masqués et le limiteur) ; l'URL est signée par `VideosService.presignDownload` (port de stockage `presignGet`), qui ne vérifie aucun droit.

### Hors périmètre (décision du développeur)
Légendes et traductions (pas de sous-titres), Gérer les fils d'actualité, Lien avec publication (« Pourquoi cette vidéo »), Promouvoir.

### Mesure d'audience
`video_menu_opened`, `playback_speed_changed` (`speed`), `auto_scroll_changed` (`enabled`), `clear_mode_changed` (`enabled`), `video_not_interested`, `video_downloaded` (`video_id`).

## Alternatives
- **MP4 produit par le worker** (720p, public) : plus léger, mais stocké en double et absent des vidéos déjà publiées. Écarté.
- **Assembler le HLS dans l'app** : AVFoundation n'exporte pas un flux HLS en fichier ; il faudrait réassembler les segments à la main. Écarté.
- **Téléchargement toujours permis** : plus simple, mais l'auteur ne peut pas protéger ses vidéos. Écarté.
- **« Pas intéressé(e) » envoyé à l'API** : sans algorithme, rien ne s'en servirait. Écarté.

## Conséquences
- Migration `video_downloads_enabled` (colonne `videos.downloads_enabled`, vrai par défaut).
- Le client Swift gagne `downloadVideo`, `setVideoDownloadSettings` et `downloadsEnabled`.
- **Limites** :
  - une URL signée peut être partagée pendant ses 15 minutes ;
  - le fichier d'origine peut être lourd (1 Gio au plus) et dans une qualité supérieure à la lecture ;
  - pas de filigrane ni de mention de l'auteur dans le fichier ;
  - interdire le téléchargement ne retire pas les copies déjà faites.
