# ADR-057 — Menu du profil, page « Solde », centre des activités et paramètres façon TikTok

## Statut
Accepté

Complète [ADR-016](ADR-016-perimetre-mvp.md) (périmètre : compte et profil, centre d'activités), [ADR-006](ADR-006-persistance.md) (historique de visionnage) et [ADR-009](ADR-009-paiement-jetons.md) (portefeuille de jetons), sans les remplacer.

## Contexte
Le développeur veut que les écrans ouverts depuis le menu ☰ de son profil ressemblent à ceux de TikTok (captures fournies) :
- un **panneau latéral** qui glisse depuis la droite : « Ressources » (Solde), « Outils personnels » (Centre des activités, Vidéos hors ligne, Ton code QR, TikTok Minis), « Outils de création et professionnels » (TikTok Studio, Promouvoir), « Paramètres et confidentialité » ;
- la page **« Solde »** : en grand le « Solde estimé » (gains du créateur), une pastille « Pièces N | Obtenir des Pièces », une carte « Transactions — Tout voir », des services (récompenses LIVE, monétisation, abonnements) ;
- le **« Centre des activités »** : historiques de visionnage, des commentaires, des recherches (et d'autres) ; l'historique de visionnage est **rangé par jour** (« Aujourd'hui », « Hier »…) avec « Sélectionner » et « Filtrer par date » ; celui des recherches aussi, avec l'heure ;
- **« Paramètres et confidentialité »** : sections Activité, Compte, Visibilité, Interactions, Connexion.

Ce qui existe déjà : un écran « Paramètres » unique (portefeuille, historiques, comptes bloqués, mesure d'audience, déconnexion, suppression du compte) ; le paywall (ADR-009) et les gains non dépensables (ADR-050) ; l'historique de visionnage (`view_history.viewed_at`, ADR-006) **sans sa date dans l'API** ; l'historique des recherches gardé sur l'appareil sans date (ADR-049).

## Décision
- **Date de visionnage dans l'API** : `viewedAt` facultatif sur l'élément du feed (`FeedItemDto`), **présent seulement** dans `GET /users/me/history` (date de la dernière vue, déjà lue pour la pagination : aucune requête de plus, aucune migration). L'app range la grille par jour. **Pas de filtre par date** (choix du développeur : il faudrait un paramètre de plus).
- **Menu ☰** (app) : panneau par-dessus les onglets avec Solde, Centre des activités, Ton code QR, Paramètres et confidentialité.
- **« Ton code QR »** (choix du développeur) : le lien du profil (`tiktokclone://users/<pseudo>`, ADR-056) en code QR, dessiné sur l'iPhone, avec « Partager le profil ». Pas de lecteur de code QR dans l'app (l'appareil photo de l'iPhone ouvre le lien).
- **Page « Solde »** (choix du développeur) : en grand les **gains en jetons** (ADR-050), qu'un œil masque, sans conversion en argent ; pastille « Jetons N | Obtenir des jetons » qui ouvre les packs (ADR-009) dans une feuille ; « Transactions » et « Cadeaux reçus » sur leurs pages. Ouverte par le bouton jetons du profil ou « Recharger » d'un cadeau, elle ouvre d'emblée les packs. Source `menu` de `paywall_viewed` (à la place de `settings`).
- **Centre des activités** : historiques de visionnage (par jour, « Sélectionner » pour en retirer plusieurs, « Tout effacer »), des commentaires (sa photo, « Nom ▸ auteur de la vidéo », date, miniature) et des recherches (par jour avec l'heure ; toucher relance la recherche ; « Sélectionner »). Les recherches gardent leur **date sur l'appareil** (une recherche gardée avant n'en a pas : « Plus ancien »).
- **Paramètres et confidentialité** : Activité (centres d'intérêt), Compte (page « Compte » : pseudo, suppression du compte ; « Partager le profil »), Visibilité (comptes bloqués ; vidéos aimées et favoris « Toi uniquement », sans réglage), Confidentialité (mesure d'audience), Connexion (« Se déconnecter »).
- **Hors périmètre** (choix du développeur) : vidéos hors ligne, TikTok Minis, TikTok Studio, Promouvoir, services de la page Solde (récompenses LIVE, monétisation, abonnements), montant en argent, autres historiques (publicité, mentions, compte, réutilisation du contenu), compte privé, notifications, temps d'écran, Connexion Famille, mentions, messages directs, réutilisation du contenu, téléchargements, **changement de compte**.

## Alternatives
- **Grille sans dates** : aucun changement d'API, mais pas de rangement par jour ; écarté par le développeur.
- **Route dédiée à l'historique** (élément propre avec `viewedAt` obligatoire) : un type de plus côté API et app pour un seul champ ; écarté, l'élément du feed sert déjà les grilles et le lecteur.
- **Filtre par date** (paramètres `from`/`to`) : reporté par le développeur.
- **Solde en grand** : plus proche de ce qu'on dépense, mais la page de TikTok met en avant les gains ; écarté par le développeur.
- **Plusieurs comptes sur l'appareil** (« Changer de compte ») : plusieurs sessions dans le trousseau ; reporté par le développeur.

## Conséquences
### Positives
- Des écrans reconnaissables, sans nouvelle table ni migration ; un seul champ facultatif de plus dans l'API.
- Le code QR du profil, sans dépendance ni serveur.

### Négatives
- `viewedAt` n'a de sens que dans l'historique : absent des autres listes, ce que le schéma ne dit que par sa description.
- Retirer plusieurs vidéos de l'historique envoie une requête par vidéo.
- Les recherches gardées avant cette version n'ont pas de date.

## Liens
- ADR-006 — Modèle de données
- ADR-009 — Jetons et paywall
- ADR-016 — Périmètre du MVP
- ADR-049 — Recherche de comptes et hashtags
- ADR-050 — Cadeaux en jetons
- ADR-056 — Profil façon TikTok
