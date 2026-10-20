# ADR-063 — Éditeur vidéo : filtres en catégories, autocollants, effets

## Statut
Accepté

Complète [ADR-062](ADR-062-creation-video-facon-tiktok.md) (création vidéo façon TikTok) et [ADR-052](ADR-052-enregistrement-edition-video.md) (édition vidéo dans l'app), sans les remplacer.

## Contexte
L'ADR-062 a laissé hors périmètre les autocollants et les effets, et gardé une rangée de 8 filtres sans réglage. Le développeur fournit des captures de TikTok : panneau de filtres par catégories (Portrait, Paysage, Nourriture, Ambiance) avec vignettes rondes et curseur d'intensité ; panneau « Stickers | Emoji » ; éditeur d'effets plein écran (« Cancel / Save », frise colorée, onglets « Trending », « Visual », « Transition »…). Il demande de les ajouter, dans une version adaptée.

## Décision
Choix du développeur, parmi les options proposées. Tout se fait dans l'app, à l'export sur l'iPhone : **ni l'API, ni le worker, ni le contrat ne changent** (l'app envoie toujours un seul fichier, ADR-052).

### Filtres
- Une vingtaine de filtres Core Image **rangés par catégorie** : Portrait, Paysage, Nourriture, Ambiance (les 7 filtres existants gardent leur identifiant, dans « Ambiance »).
- Panneau en bas de l'aperçu (et de l'éditeur par clips) : ⊘ pour aucun filtre, onglets des catégories, vignettes rondes (l'image de la vidéo filtrée), nom du filtre choisi en rose ; au changement, son nom et sa catégorie s'affichent en grand au milieu de la vidéo.
- **Intensité** de 0 à 100 (curseur au-dessus du panneau, valeur affichée), 100 par défaut ; mélange de l'image d'origine et de l'image filtrée.

### Autocollants
- Panneau « Autocollants | Emoji » :
  - « Autocollants » : la date du jour (deux styles) et l'heure, figées au moment de l'ajout ;
  - « Emoji » : une grille d'emojis par catégorie, avec une barre de catégories en bas.
- Posés et manipulés comme les textes : glisser (repère central, corbeille « Supprimer »), pincer pour la taille ; 10 au plus ; visibles pendant toute la vidéo, incrustés à l'export.

### Effets (version réduite)
- Éditeur plein écran (« Annuler », « Enregistrer ») : aperçu de la vidéo, annuler / rétablir et supprimer à droite, frise de toute la vidéo avec la tête de lecture et les plages d'effets en couleur, onglets de catégories (Visuel, Couleur, Déformation), grille d'une douzaine d'effets Core Image (surexposition, bruit noir, négatif, flou, pixels, bande dessinée, affiche, lueur, miroir…) avec leur vignette.
- Toucher un effet le pose **à partir de la tête de lecture, pour 2 secondes** (ou jusqu'à la fin) ; une plage choisie se raccourcit ou s'allonge par ses bords, se supprime ; 20 effets au plus. « Annuler » oublie les changements de la séance, « Enregistrer » les garde (un seul pas d'annulation dans l'éditeur).
- Appliqués à l'export sur leur plage de la vidéo finale, après le filtre et avant les textes et autocollants.

### Mesure d'audience
`video_upload_started` porte en plus `filter_intensity` (0 à 100), `sticker_count` et `effect_count`.

### Hors périmètre (décision du développeur)
Autocollants « Mention », « Hashtag », « Sondage », « Don », « Lieu », « Musique », « Add yours », photo ajoutée en autocollant et GIF (ils demanderaient l'API ou un service tiers) ; transitions, effets de visage et de mouvement, effets « Tendances » et « Nouveau » ; voix off ; filtre posé en glissant sur la vidéo.

## Alternatives
- **Autocollants « Mention » et « Hashtag » dessinés** : non cliquables à la lecture, ils tromperaient le spectateur ; un vrai autocollant cliquable demande l'API. Écarté.
- **Effets maintenus au doigt pendant la lecture** (comme TikTok) : difficile à doser sur une vidéo courte et à vérifier ; la pose par toucher puis l'ajustement des bords donnent le même résultat. Écarté.
- **Garder les filtres actuels** : écarté au profit du panneau des captures.

## Conséquences
### Positives
- Éditeur plus proche de TikTok, sans coût côté serveur.
- Filtres, effets et autocollants passent par le même compositeur Core Image que le reste (ADR-062).

### Négatives
- Tout filtre, effet ou autocollant impose un réencodage sur l'iPhone.
- Dans le simulateur, l'aperçu reste simplifié (ni filtre ni effet, piège connu de l'ADR-062) : seules les vignettes et l'export les montrent.
- Les emojis sont dessinés par la police du système : leur apparence dépend de la version d'iOS de l'auteur.

## Liens
- [ADR-062](ADR-062-creation-video-facon-tiktok.md), [ADR-052](ADR-052-enregistrement-edition-video.md), [ADR-013](ADR-013-analytics-ab-testing.md)
