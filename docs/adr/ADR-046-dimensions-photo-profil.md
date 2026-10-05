# ADR-046 — Dimensions de la photo de profil vérifiées par l'API

## Statut
Proposé

Complète [ADR-016](ADR-016-perimetre-mvp.md) (profil : photo) et la décision du développeur « pas de traitement d'image côté serveur », sans les remplacer.

## Contexte
L'app recadre la photo de profil en carré de 512 px et l'encode en JPEG avant de l'envoyer en un seul PUT signé. À la confirmation, l'API revérifiait déjà le type, la taille (5 Mio au plus) et la signature des premiers octets. Elle ne vérifiait pas les dimensions, faute de bibliothèque d'image côté serveur (limite documentée).

Un client autre que l'app (ou une app modifiée) pouvait donc installer une image très allongée, minuscule, ou géante : une image de 20 000 × 20 000 px tient dans 5 Mio en PNG, et chaque appareil qui l'affiche devrait la décompresser (plus d'un gigaoctet en mémoire).

## Décision
- **Règle** (choix du développeur) : la photo doit être un **carré de 64 à 2048 px** (`AVATAR_MIN_DIMENSION`, `AVATAR_MAX_DIMENSION`, `users/domain/profile-rules.ts`). Cette règle :
  - accepte l'envoi actuel de l'app (512 px) ;
  - laisse une marge si l'app change de taille plus tard ;
  - refuse les images allongées, minuscules ou géantes.
- **Lecture à la main**, sans bibliothèque ni décodage (`users/domain/image-dimensions.ts`, fonctions pures) :
  - **PNG** : le bloc IHDR, toujours le premier (largeur et hauteur aux octets 16 à 23) ;
  - **JPEG** : parcours des segments depuis le début jusqu'au premier marqueur SOF (SOF0 à SOF15, sauf DHT, JPG et DAC), qui porte hauteur et largeur. Les segments d'application (JFIF, EXIF…) le précèdent : il doit se trouver dans les **64 premiers Kio** (`AVATAR_HEADER_LENGTH`), sinon l'image est refusée. Les dimensions sont celles stockées, avant rotation EXIF, ce qui est sans effet pour un carré.
- **À la confirmation** (`PUT /users/me/avatar`) : une seule lecture des 64 premiers Kio (`GET` avec `Range`), qui sert à vérifier la signature puis les dimensions. Une image refusée est supprimée du stockage, et l'API répond **400** : « La photo de profil doit être une image JPEG ou PNG carrée, de 64 à 2048 px et 5 Mio au plus ».
- L'app n'a rien à changer : elle envoie déjà un carré de 512 px.

## Alternatives
- **Bibliothèque `image-size`** (pure JavaScript, nombreux formats) : une dépendance de plus pour deux formats. Écarté.
- **Décoder et réencoder l'image côté serveur** (`sharp`…) : garantirait le contenu et retirerait les métadonnées, mais demande une dépendance native (libvips) dans l'image Docker de l'API, et du temps de calcul à chaque envoi. Écarté pour l'instant.
- **Exactement 512 × 512** : le plus strict, mais toute évolution de l'app demanderait de changer l'API en même temps. Écarté.
- **Seulement une taille maximale** (toute proportion) : protège des images géantes, mais laisse passer des photos de profil non carrées. Écarté.

## Conséquences
### Positives
- Plus d'image géante ni déformée en photo de profil, quel que soit le client.
- Aucune dépendance nouvelle ; lecture testée sur de vraies images (FFmpeg, `sips` de macOS) et des en-têtes construits.

### Négatives
- Une lecture de 64 Kio au lieu de 8 octets à chaque confirmation.
- Le contenu de l'image n'est toujours pas décodé : un fichier à l'en-tête correct mais aux données corrompues passe. Les métadonnées (EXIF) ne sont pas retirées par le serveur.
- Un JPEG dont les segments d'application dépassent 64 Kio avant le SOF est refusé (jamais le cas des JPEG produits par l'app).

## Liens
- ADR-016 — Périmètre du MVP
- ADR-003 — Architecture backend (règles dans le domaine)
