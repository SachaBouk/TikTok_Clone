# ADR-068 — Comptes suggérés complétés par des comptes populaires

## Statut
Proposé

Complète [ADR-058](ADR-058-onglet-messages.md) (comptes suggérés), sans le remplacer.

## Contexte
L'app affiche maintenant, dans le feed « Pour toi », un carrousel de comptes suggérés (choix du développeur, d'après des captures de TikTok : après la 8e vidéo, puis toutes les 30). Il lit `GET /users/me/suggestions` (ADR-058), qui ne propose que des **amis d'amis** et des **abonnés que l'on ne suit pas**.

Un compte qui ne suit personne et n'a aucun abonné (nouveau compte, ou le compte du développeur) n'a donc **aucune suggestion** : ni carrousel dans le feed, ni section « Comptes suggérés » dans l'onglet Messages. TikTok, lui, propose aussi des comptes sans lien (« Personnes que tu pourrais connaître »).

## Décision
Choix du développeur, parmi les options proposées (comptes populaires, comptes actifs récents, ne rien changer).

- **Complément** : quand les amis d'amis et les abonnés ne remplissent pas la liste demandée (`limit`), elle est complétée par des **comptes populaires**, placés après eux.
- **Comptes populaires** : comptes qui ont **au moins une vidéo publiée et publique**, classés du **plus d'abonnés** au moins, puis du **plus de vidéos publiées et publiques**, puis par identifiant. Classés parmi les 100 comptes qui publient le plus (`POPULAR_SUGGESTION_POOL`).
- **Jamais** soi-même, un compte déjà suivi, un compte masqué (bloqué dans un sens ou l'autre, suspendu) ni un compte déjà suggéré.
- **Réponse inchangée** : un compte populaire a `followsYou` faux, `followedBy` vide et `followedByCount` 0. L'app l'affiche « Personnes que tu pourrais connaître » dans le carrousel, « Suggéré pour toi » dans l'onglet Messages. Pas de changement du contrat OpenAPI.
- **Frontières (ADR-003)** : `InteractionsService.listSuggestions` lit les comptes qui publient par `VideosService.listPublishingAuthors` (nouveau, groupement sur `videos`) et leurs abonnés par `UsersService.getByIds`. Aucun accès direct aux tables d'un autre module.

## Conséquences
- Tout compte connecté voit des suggestions dès qu'il existe d'autres comptes qui publient : le carrousel du feed et la section de l'onglet Messages apparaissent aussi pour un nouveau compte.
- Deux lectures de plus quand la liste n'est pas pleine (groupement des vidéos publiées par auteur, comptes). Le groupement parcourt les vidéos publiées : à revoir (vue matérialisée, cache) si le catalogue grandit beaucoup.
- Pas de personnalisation (centres d'intérêt, contacts) : l'algorithme For You reste reporté (ADR-016).
