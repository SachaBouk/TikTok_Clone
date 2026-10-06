# ADR-049 — Recherche de comptes et hashtags

## Statut
Accepté

Complète [ADR-016](ADR-016-perimetre-mvp.md) (périmètre) et [ADR-003](ADR-003-architecture-backend.md) (modules), sans les remplacer : la recherche, les hashtags et l'historique des recherches, reportés par l'ADR-016, entrent dans le périmètre (décision du développeur).

## Contexte
L'ADR-016 a reporté la recherche, les hashtags et l'historique des recherches (« ajouté en même temps que la recherche »). Le développeur lève cette réserve.

Aujourd'hui, on ne trouve un compte qu'en passant par une vidéo, une liste d'abonnés ou un message. Les descriptions des vidéos (2 200 caractères au plus) peuvent contenir des `#mots`, mais rien ne les relie entre elles.

Ce qui existe déjà :
- la recherche du backoffice (`UsersService.searchAccounts`) : partielle et sans casse, mais sans classement ni masquage, réservée aux administrateurs ;
- le masquage des comptes bloqués (ADR-029) et suspendus (ADR-037) : `InteractionsService.getHiddenAccountIds` ;
- les relations par lot (`InteractionsService.getRelationships`, ADR-036) ;
- les grilles de vidéos et le lecteur vertical (module `feed`, élément `FeedItemDto`).

## Décision
### Recherche de comptes
- **Route** : `GET /search/users?q=&cursor=&limit=`, **publique** (invité compris). `q` : 1 à 50 caractères, `@` initial ignoré. Pages de 20, 50 au plus, **100 résultats au plus** par recherche. Curseur opaque (position dans le classement).
- **Correspondance** : `q` contenu dans le pseudo ou dans le nom, sans casse (`ILIKE`, caractères `%` et `_` échappés).
- **Classement** : pseudo identique, puis pseudo qui commence par `q`, puis nombre d'abonnés décroissant, puis identifiant.
- **Masquage** : comptes suspendus pour tous ; pour un compte connecté, comptes bloqués dans un sens ou dans l'autre. Ils sont exclus **dans la requête** : aucune page n'est raccourcie. Le compte connecté figure dans les résultats.
- **Élément** : `user` (résumé), `followersCount` et, pour un compte connecté, `viewer` (`following`, `followedBy`, comme les listes d'abonnés) pour le bouton « Suivre ».
- **Index** : extension `pg_trgm`, index GIN trigrammes sur `users.username` et `users.display_name`.

### Hashtags
- **Règle d'extraction** (`videos/domain/hashtags.ts`, à garder alignée avec `HashtagRules.swift` de l'app et avec le SQL de la migration) :
  - description normalisée en NFC ;
  - `#` suivi de 1 à 50 lettres, chiffres décimaux ou `_`, non précédé d'une lettre, d'un chiffre ou d'un `_`, et non suivi d'un tel caractère (au-delà de 50, ce n'est pas un hashtag). Les classes suivent `[[:alnum:]]` de PostgreSQL : lettres de toutes les écritures, chiffres romains compris, mais ni « ½ » ni « ² » ;
  - au moins une lettre ou un chiffre ;
  - nom mis en minuscules, accents gardés (`#été` ≠ `#ete`) ;
  - 20 hashtags distincts au plus par vidéo, dans l'ordre d'apparition.
- **Données** (module `videos`, propriétaire des descriptions) :
  - `hashtags` (`hashtag_id`, `name` unique, `videos_count`, `created_at`) ;
  - `video_hashtags` (`video_id`, `hashtag_id`, `created_at` = date de publication), clé composite, suppression en cascade avec la vidéo ;
  - les lignes sont créées **au passage en `ready`**, dans la même transaction (`finishTranscoding`) : un hashtag ne compte que des vidéos publiées ;
  - `videos_count` est tenu par un **trigger** (comme les compteurs d'interactions) ; un hashtag sans vidéo reste en base, mais n'est plus proposé ;
  - CHECK écrits à la main : nom de 1 à 50 caractères, compteur ≥ 0 ;
  - index GIN trigrammes sur `hashtags.name` (préfixe), index `video_hashtags(hashtag_id, created_at)` et `video_hashtags(created_at)`.
- **Remplissage des descriptions existantes** : par la migration, en SQL (même règle, `regexp_matches` avec `[[:alnum:]_]`, `normalize(…, NFC)`, `lower`), pour les vidéos déjà `ready`.
- **Routes** :
  - `GET /search/hashtags?q=&limit=` (publique) : hashtags **qui commencent par** `q` (`#` initial ignoré), ayant au moins une vidéo, du plus utilisé au moins utilisé ; 10 par défaut, 20 au plus. Sert à la recherche et aux suggestions de la publication ;
  - `GET /search/trending-hashtags` (publique) : **hashtags tendance**, 10 au plus : vidéos publiées ces 7 derniers jours, puis nombre total de vidéos (un catalogue calme a donc quand même des suggestions) ;
  - `GET /hashtags/:name` (publique) : `{ name, videosCount }`. Un nom valide inconnu donne 0 vidéo, sans 404 ; un nom invalide, 400 ;
  - `GET /hashtags/:name/videos?cursor=&limit=` (publique, module `feed`) : vidéos publiées du hashtag, **les plus récentes d'abord** (choix du développeur : date de publication puis identifiant, pagination par clé, curseur des grilles), même élément que le feed. Comptes masqués retirés (page plus courte). Pages de 21, 60 au plus.
- Le nombre de vidéos d'un hashtag compte aussi celles des comptes masqués (comme `comments_count`).

### Modules (ADR-003)
- Nouveau module **`search`**, sans données ni couche `infrastructure/` (comme `admin`) : il assemble `UsersService.searchProfiles` (classement en SQL, comptes exclus donnés par l'appelant), `InteractionsService` (masquage et relations) et `VideosService` (hashtags). `users` ne dépend toujours pas d'`interactions`.
- Les hashtags appartiennent à `videos` (dépôt des vidéos, `VideoRepository`, qui écrit aussi leurs lignes au passage en `ready`). La grille d'un hashtag est dans `feed`, comme les grilles du profil.

### App iOS
- **Loupe en haut du feed** (choix du développeur), à droite du sélecteur « Abonnements | Pour toi » : elle pousse l'écran de recherche dans la pile de l'accueil.
- **Écran de recherche** : champ natif (`searchable`).
  - **Avant la saisie** : historique, puis hashtags tendance.
  - **Pendant la saisie** (300 ms sans frappe) : hashtags qui commencent par le texte (5 au plus), puis comptes (paginés, bouton « Suivre »).
  - Toucher un compte ouvre son profil, toucher un hashtag ouvre sa page.
- **Historique des recherches sur l'appareil** (choix du développeur) :
  - 20 recherches au plus, la plus récente d'abord, sans doublon (UserDefaults) ;
  - une recherche est retenue quand on valide le champ ou qu'on ouvre un résultat ;
  - suppression ligne par ligne et « Effacer » ;
  - **effacé à chaque changement de session** (connexion, déconnexion, suppression du compte) : il n'est jamais visible d'un autre compte ;
  - pas de table ni de route : rien ne quitte l'appareil.
- **Page d'un hashtag** : `#nom`, nombre de vidéos, grille ; toucher une vidéo ouvre le lecteur vertical sur la liste du hashtag.
- **Hashtags cliquables** dans la description des vidéos (feed, lecteur d'une grille, vidéo seule) : ils ouvrent la page du hashtag.
- **Suggestions en écrivant « # »** (choix du développeur) dans la description d'une publication : le hashtag en cours de saisie (à la fin du texte) propose les hashtags existants qui commencent ainsi, avec leur nombre de vidéos ; toucher en complète la saisie.

## Alternatives
- **Onglet « Découvrir »** : plus visible, mais un cinquième onglet. Écarté par le développeur au profit de la loupe.
- **Historique côté serveur** : partagé entre appareils, mais une donnée personnelle de plus à stocker et à purger. Écarté par le développeur. **Pas d'historique** : contraire à l'ADR-016. Écarté.
- **Page d'un hashtag par popularité** : la page bouge pendant le parcours, avec une pagination par décalage plus coûteuse. Écarté par le développeur.
- **Recherche de vidéos par texte** (plein texte dans les descriptions) : non demandée, plus lourde. Écartée pour l'instant.
- **Recherche dans le module `users`** : `users` devrait dépendre d'`interactions` pour le masquage, qui dépend déjà de `users`. Écarté au profit d'un module `search`.
- **Hashtags dans un module à part, avec leurs tables** : il devrait être prévenu de chaque publication et de chaque suppression de vidéo, alors que la cascade et la transaction de `finishTranscoding` suffisent dans `videos`. Écarté.
- **Lignes `video_hashtags` créées à l'envoi** (statut `uploading`) : un hashtag compterait des vidéos jamais publiées. Écarté.
- **Remplissage par un script** (règle TypeScript exacte) : une commande de plus à lancer à chaque déploiement. Écarté au profit du SQL de la migration, avec la même règle.
- **Recherche insensible aux accents** (`unaccent`) : il faudrait un index sur une expression, que Prisma ne sait pas décrire. Écartée pour l'instant.

## Conséquences
### Positives
- On trouve un compte par son pseudo ou son nom, avec les mêmes règles de masquage que le reste de l'app.
- Les vidéos se relient par leurs hashtags. Pages, suggestions et tendances viennent de la base, sans traitement à part.
- L'historique des recherches ne quitte pas l'appareil.

### Négatives
- **Règle des hashtags écrite trois fois** (TypeScript, Swift, SQL de la migration) : elles peuvent diverger. Vérifié sur des cas limites (accents, NFC, écritures non latines, chiffres arabes et romains, emoji) ; seul écart connu : la minuscule du « İ » turc (« i̇ » en TypeScript, « i » en SQL), pour les seules vidéos remplies par la migration.
- **Recherche sensible aux accents** : « ines » ne trouve pas « Inès » (les pseudos, eux, sont sans accents).
- Pas de limite de débit sur la recherche (route publique, requête indexée).
- **Tendances** : calculées à chaque appel (agrégat sur 7 jours), sans cache.
- Le nombre de vidéos d'un hashtag compte les comptes masqués. La page peut en montrer moins.
- **Suggestions de la publication** : seulement pour le hashtag tapé à la fin de la description (la position du curseur n'est pas suivie).

## Liens
- ADR-003 — Architecture backend
- ADR-006 — Persistance
- ADR-016 — Périmètre du MVP
- ADR-018 — Modules messaging, push et admin
- ADR-029 — Blocage : contenus masqués
- ADR-036 — « Suivre en retour »
- ADR-037 — Suspension de compte
- ADR-048 — Feed des abonnements
