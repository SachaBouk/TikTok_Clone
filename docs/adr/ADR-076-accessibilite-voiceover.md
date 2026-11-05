# ADR-076 — Accessibilité VoiceOver : une personne aveugle peut parcourir l'app

## Statut
Proposé

Complète [ADR-002](ADR-002-architecture-mobile.md) (app iOS), [ADR-016](ADR-016-perimetre-mvp.md) (périmètre), [ADR-052](ADR-052-enregistrement-edition-video.md) et [ADR-062](ADR-062-creation-video-facon-tiktok.md) (création et éditeur), [ADR-065](ADR-065-ecran-publication.md) (écran de publication) et [ADR-006](ADR-006-persistance.md) (modèle de données), sans les remplacer.

## Contexte
Le développeur veut qu'une **personne aveugle puisse se balader dans l'app avec VoiceOver** : nommer tous les boutons, icônes et images ; regrouper chaque carte de liste en un seul élément ; rendre le parcours principal faisable les yeux fermés ; annoncer à voix haute les changements à l'écran ; proposer une alternative à chaque geste (balayage, double toucher).

Un audit des 292 fichiers Swift de l'app a montré une base correcte (barre d'onglets, colonne d'actions du feed, onboarding de l'ADR-075, lignes de recherche et de conversation) mais des manques bloquants :
- **la surface de la vidéo n'est pas un élément** : pause, menu de la vidéo (seul accès à Télécharger, Pas intéressé(e), Signaler, Vitesse, AirPlay), vitesse ×2 et balayage vers le profil sont introuvables ; rien ne dit qu'on a changé de vidéo ;
- **visionneuse de stories** : un seul geste maison (toucher gauche ou droite, appui long, glisser vers le bas), sans moyen de revenir en arrière ni de mettre en pause ;
- **bulles de messages** : rien ne dit qui a écrit ni quand ;
- **aucune annonce** dans tout le projet (messages éphémères, « Copié », « Envoyé », nouveaux messages, erreurs en ligne) ;
- barres de progression glissables sans valeur, « tirer pour actualiser » maison (ADR-058) inaccessible, commentaires éclatés en une dizaine d'arrêts, miniatures lues comme des images vides, état « non lu » porté par la seule couleur ;
- **l'éditeur vidéo** (ADR-062, ADR-063) repose sur des glissements (frise, poignées, recadrage, textes et autocollants déplaçables, plages d'effets).

## Décision
Choix du développeur, parmi les options proposées.

### Portée
- **VoiceOver seulement**, pour les personnes aveugles. Taille du texte (Dynamic Type), contraste renforcé et inversion intelligente sont **reportés** (choix du développeur : « concentré sur les personnes totalement aveugles pour le moment »).
- **Toute l'app**, création et **éditeur complet** compris (choix du développeur, plutôt qu'un parcours simple).
- Textes lus en français, comme l'interface.

### Règles générales
- **Tout ce qui se touche a un nom** ; les icônes et images décoratives sont masquées (miniatures de fond, icônes doublées par un texte, animations, points « · »).
- **Une carte de liste = un élément** (ligne de conversation, d'activité, commentaire, compte, vidéo d'une grille), lu en une phrase ; ses boutons secondaires deviennent des **actions personnalisées** (rotor « Actions » : balayer vers le haut ou le bas, toucher deux fois).
- **Chaque geste a son équivalent** : action personnalisée, action ajustable (balayer vers le haut ou le bas sur l'élément) ou défilement à trois doigts (`accessibilityScrollAction`).
- **Les changements à l'écran sont annoncés** (`AccessibilityNotification.Announcement`) : messages éphémères (`Toast` et ses semblables), changement de vidéo ou de story, envoi réussi ou en échec, nouveaux messages dans la conversation ouverte, « en train d'écrire », erreurs en ligne, fin d'un rechargement. Une seule fonction (`Accessibility.announce`), sans effet quand VoiceOver est coupé.
- Titres d'écran et de section en **titres** (`.isHeader`, rotor « Titres »), segments et onglets avec l'état **sélectionné**, nombres compacts lus en entier (« 1,2 k » → « 1 200 »).

### Feed et lecteurs (feed, abonnements, amis, grilles, vidéo seule)
- La vidéo devient **un élément** « Vidéo de @pseudo », dont la valeur dit l'état (en lecture, en pause, vitesse) puis le contenu : description, **texte alternatif** (voir plus bas), lieu, « Créé avec l'IA ».
  - **toucher deux fois** : pause ou reprise ;
  - **défilement à trois doigts** vers le haut ou le bas : vidéo suivante ou précédente ; aussi en actions « Vidéo suivante » / « Vidéo précédente » ;
  - actions : « J'aime » (le double toucher de l'image), « Menu de la vidéo » (appui long au milieu), « Vitesse ×2 » / « Vitesse normale » (verrou de l'appui long sur un côté), « Profil de @pseudo » (balayage vers la gauche), « Commentaires », « Partager ».
- **Lecture automatique gardée** (choix du développeur) : VoiceOver baisse lui-même le son quand il parle. **Magic Tap** (toucher deux fois avec deux doigts) met en pause ou reprend la vidéo affichée, d'où que soit le curseur.
- À l'arrivée sur une vidéo (défilement, défilement automatique), le curseur VoiceOver se place sur elle et l'app annonce « @pseudo : description ».
- **Barre de progression** : élément ajustable « Progression », valeur « 0:05 sur 0:24 », balayer vers le haut ou le bas avance ou recule de 5 s.
- Indication « Balaie vers le haut » (ADR-055) : action « Vidéo suivante », animation masquée.

### Texte alternatif des vidéos (API)
- Champ facultatif **« Description pour l'accessibilité »** (texte alternatif) sur l'écran de publication (`PostView`, sous « Plus d'options »), **300 caractères** au plus, nettoyé comme la description.
- API (module `videos`) : colonne `videos.alt_text` (texte nul par défaut, CHECK 1 à 300 caractères, migration `video_alt_text`), reçue à l'envoi (`POST /videos/upload-url` avec `altText`) et changée par l'auteur quel que soit le statut (`PATCH /videos/:id/alt-text` `{ altText }`, vide ou nul = retiré, 404 pour un autre ; `VideosService.setAltText`). `VideoDto` et `FeedItemDto` portent `altText` (**absent** sans texte, comme `location`). L'app le change depuis la feuille de partage de ses vidéos (« Texte alternatif »). Pas pour les stories (photos et vidéos de 24 h).
- **Description automatique sur l'iPhone** (choix du développeur, en plus) : quand l'auteur n'a rien écrit, l'app analyse la **miniature** sur l'appareil avec Vision (rien n'est envoyé) : visages comptés (`VNDetectFaceRectanglesRequest`), scène (`VNClassifyImageRequest`, étiquettes traduites en français par une table de l'app ; les étiquettes sans traduction sont ignorées) et texte incrusté (`VNRecognizeTextRequest`, français et anglais). Lu après le reste, toujours précédé de « Description automatique : peut contenir… », pour qu'on ne la prenne pas pour celle de l'auteur. Calculée une fois par vidéo (cache en mémoire), seulement quand VoiceOver est actif.

### Stories
- Le média devient un élément ajustable : balayer vers le haut ou le bas = story suivante ou précédente ; actions « Story suivante », « Story précédente », « Pause » / « Reprendre », « Compte suivant » ; valeur « Story 2 sur 5, il y a 3 h » ; geste d'échappement (Z à deux doigts) = fermer.
- **Avec VoiceOver, une story photo n'avance pas seule** (5 s ne suffisent pas pour entendre l'écran) : on passe à la suivante quand on veut. Une story vidéo va au bout de sa vidéo, comme avant.
- Changement de story ou de compte annoncé (« @pseudo, story 1 sur 3 »).

### Messagerie, commentaires, activité, profil
- **Bulle de message** : une phrase « Toi : texte, 14 h 32 » / « Inès : texte, hier » (heure toujours dite, même quand l'écran ne l'affiche pas), état (« envoi », « non envoyé », « vu »), carte partagée décrite ; les nouveaux messages de la conversation ouverte sont annoncés (« Inès : salut ») ainsi que « Inès écrit… ».
- **Commentaire** : une phrase « Nom, Créateur, texte, il y a 2 h, 12 j'aime, aimé par l'auteur » ; actions « Répondre », « J'aime », « Je n'aime pas », « Profil de … », « Afficher les réponses », plus les actions déjà présentes (supprimer, signaler).
- **Activité** : « non lu » dit dans chaque ligne ; **grilles** : « description, 1 200 vues » ; **en-tête de profil** : nom en titre, compteurs lus en entier (« 1 200 abonnés »).
- **Tirer pour actualiser à deux points** (onglet Messages, profils) : action « Actualiser » sur la liste, et le `refreshable` natif quand VoiceOver est actif (défilement à trois doigts vers le bas tout en haut).

### Création et éditeur complet
- **Caméra** : déclencheur, minuteur, lampe, changement de caméra, durées et modes nommés, avec leur état ; durée filmée annoncée à l'arrêt d'un segment.
- **Galerie** : cellule « Vidéo, 0:12, 3 mai » avec son numéro de sélection (« sélectionnée, 2 ») ; albums et onglets nommés.
- **Éditeur par clips** : chaque clip de la frise est un élément « Clip 2 sur 3, 4,5 s, vitesse 1,5× » (actions : choisir, diviser à la tête de lecture, supprimer) ; poignées de début et de fin ajustables (± 0,1 s) ; tête de lecture ajustable (± 0,5 s, valeur « 0:03 sur 0:19 ») ; curseurs de vitesse et de volume ajustables (déjà en partie).
- **Recadrage** : cadre ajustable par actions (« Déplacer vers le haut / bas / la gauche / la droite », « Agrandir », « Réduire »), proportions nommées, valeur « cadre 1:1, centré ».
- **Textes et autocollants posés** : élément « Texte : Bonjour » / « Autocollant : 🔥 » avec actions « Modifier », « Déplacer vers le haut / bas / la gauche / la droite », « Centrer », « Agrandir », « Réduire », « Supprimer » (équivalents du glisser, du pincer et de la corbeille).
- **Effets et voix off** : plages de la frise des effets en éléments (« Négatif, de 0:02 à 0:04 ») ajustables et supprimables ; vignettes de filtres et d'effets nommées avec l'état sélectionné ; intensité ajustable ; enregistreur de voix off annoncé (début, fin, durée).
- **Couverture** : image choisie ajustable (image précédente ou suivante, « image 3 sur 10 »).
- **Écran de publication** : champ du texte alternatif, réglages nommés.

### Code (app iOS ; module `videos` de l'API pour le texte alternatif)
- `presentation/common/Accessibility.swift` : `Accessibility.announce(_:)`, nombres lus en entier, modificateurs communs (décor masqué, titre) ; `Toast` et les messages éphémères passent par l'annonce.
- Règles pures et testées (`domain/entities/AccessibilityText.swift`) : phrases lues (vidéo, message, commentaire, story, clip, cadre), durées parlées (« 1 min 05 s »), nombres en entier ; table des étiquettes de Vision (`SceneLabels`).
- Port `ImageDescriber` (domaine), adaptateur `VisionImageDescriber` (`data/media`), faux pour les tests ; `AutoDescriptionModel` (cache, VoiceOver seulement).
- Pas de nouvelle mesure d'audience (aucune donnée sur l'usage de VoiceOver n'est envoyée).

### Hors de cette étape
- Dynamic Type, contraste renforcé, inversion intelligente, « Différencier sans couleur » (malvoyants) ; Contrôle de sélection et Commande vocale (les noms donnés leur serviront déjà en partie).
- Sous-titres des vidéos (transcription), audiodescription, texte alternatif des stories et des photos de profil.
- Description automatique par un modèle génératif (Vision seulement, sur l'appareil).

## Alternatives
- **Vidéos en pause par défaut avec VoiceOver** : l'utilisateur entend la description sans le son ; écarté (Magic Tap suffit, et le feed garde son principe).
- **Texte alternatif seul**, ou **description automatique seule** : écartés (les deux ensemble : la description de l'auteur fait foi, l'automatique comble les vidéos sans texte).
- **Parcours de création simple** (éditeur avancé seulement nommé) : écarté par le développeur.
- **Mode « VoiceOver » distinct** (écrans simplifiés à part) : double code à entretenir, et une personne aveugle veut la même app que les autres.

## Conséquences
### Positives
- Le parcours principal (feed, profils, recherche, commentaires, messages, stories, lives, publication) se fait les yeux fermés.
- Les auteurs peuvent décrire leurs vidéos ; les autres sont décrites a minima par l'iPhone.
- Les actions personnalisées et les noms servent aussi au Contrôle de sélection et à la Commande vocale.

### Négatives
- Beaucoup de vues touchées : chaque nouvel écran devra suivre ces règles (noms, regroupement, alternative aux gestes, annonces).
- VoiceOver ne se vérifie bien que sur un iPhone ; dans le simulateur, on vérifie l'arbre d'accessibilité (Accessibility Inspector, tests d'interface) et les règles pures.
- Description automatique approximative (étiquettes de scène limitées, traduites par l'app) et un peu de calcul sur l'iPhone.
- Une colonne, une route et un champ de plus côté API.

## Liens
- ADR-002 — App iOS
- ADR-016 — Périmètre MVP
- ADR-052, ADR-062, ADR-063 — Création et éditeur vidéo
- ADR-065 — Écran de publication
