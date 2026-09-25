# ADR-016 — Périmètre de la première version (MVP)

## Statut
Accepté

## Contexte
La liste des fonctionnalités d'une application type TikTok (diapo 9 du cahier des charges) couvre la création et l'édition de vidéos, plusieurs formats de contenu, la découverte, les interactions sociales, la monétisation, le compte et la connexion.
Le projet est développé par une seule personne.
Plusieurs de ces fonctionnalités sont chacune un projet à part entière (Live, Stories, TikTok Shop).
Le cahier des charges impose un paywall dans le rendu final.

## Décision
Fonctionnalités retenues pour la première version :
- **Feed principal** de vidéos que l'on scrolle, affichées dans un ordre aléatoire, sans algorithme de recommandation.
- **Publication de vidéos** : upload simple depuis la galerie de l'app, sans édition. C'est la seule source de vidéos du feed en production.
- **Script de seed**, uniquement en local et pour la démo : il crée des comptes de démonstration, envoie des fichiers vidéo dans le stockage objet, crée les lignes `VIDEO` en statut `uploading` et place les jobs de transcodage dans la queue. Les vidéos suivent le même pipeline qu'un upload depuis l'app.
- **Interactions sociales** : like, favoris, commentaire, partage, republication, follow, messagerie directe, activité (notifications).
- **Compte** (création et gestion) : nom, pseudo, photo de profil, bio, followers, suivis, centre d'activités (historique de visionnage, commentaires).
- **Connexion / déconnexion**, avec un accès réduit aux fonctionnalités en mode déconnecté.
- **Paywall** : achat de jetons, crédités sur le portefeuille (`WALLET`).

Fonctionnalités reportées après la première version :
- **Création et édition** : enregistrement vidéo, trim / cut / merge, filtres et effets. Elles viendront enrichir l'upload simple.
- **Formats de contenu** : Live, Stories, réponses vidéo à un commentaire.
- **Découverte** : For You Page (algorithme de recommandation), feed des comptes suivis, recherche, hashtags et sons tendances.
- **Historique des recherches**, ajouté en même temps que la recherche.
- **Dépense des jetons** : cadeaux en live. Ainsi que TikTok Shop.

## Alternatives
- Périmètre complet (toutes les fonctionnalités de la diapo 9) : couvre l'expérience TikTok entière, mais plusieurs fonctionnalités sont des projets à part entière. Non retenu.
- Reporter toute publication de vidéos (y compris l'upload) : laisse le feed sans source de contenu. Non retenu.
- Publication de vidéos depuis le backoffice : envisagée, écartée par le lead développeur.
- Insertion directe de vidéos en base : contourne le pipeline de l'ADR-008 (pas de HLS ni de CDN) et crée deux types de sources vidéo. Rejetée au profit du script de seed.
- Feed en ordre chronologique : envisagé, ordre aléatoire retenu.
- Reporter toute la monétisation : ne couvre pas l'exigence de paywall du cahier des charges. Non retenu.

## Conséquences
### Positives
- Le développement se concentre sur le feed, les interactions sociales et le compte.
- Les fonctionnalités les plus lourdes (Live, Stories, TikTok Shop, algorithme de recommandation, édition vidéo) sont hors du périmètre initial.
- En production, l'upload direct et le pipeline vidéo (ADR-007, ADR-008) n'ont qu'un seul point d'entrée : l'app.
- L'exigence de paywall est couverte par l'achat de jetons (ADR-009).
- En local et pour la démo, le feed est alimenté en une commande, avec des vidéos identiques à celles publiées depuis l'app.

### Négatives
- La messagerie directe, retenue, s'appuie sur le temps réel (ADR-011) et ajoute plusieurs entités (ADR-006).
- Dans la première version, les jetons achetés n'ont pas encore d'usage : la dépense (`GIFT_SENT`) arrive avec les cadeaux.
- Un ordre aléatoire complique la pagination du feed (risque de doublons ou de vidéos manquées entre deux pages).
- En production, le feed ne contient que les vidéos publiées par les utilisateurs : au lancement, il dépend des premiers uploads.
- Le script de seed doit rester aligné avec le pipeline vidéo lorsque celui-ci évolue.

## Liens
- ADR-006 — Persistance
- ADR-007 — Upload vidéo direct
- ADR-008 — Pipeline vidéo
- ADR-009 — Paiement et jetons
- ADR-010 — Authentification
- ADR-011 — Temps réel
- ADR-012 — Traitement asynchrone
