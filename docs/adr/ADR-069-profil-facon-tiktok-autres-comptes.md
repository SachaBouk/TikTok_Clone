# ADR-069 — Profil d'un autre compte façon TikTok : comptes suggérés liés au profil, profil partagé par message

## Statut
Proposé

Complète [ADR-056](ADR-056-profil-facon-tiktok.md) (profil), [ADR-058](ADR-058-onglet-messages.md) (comptes suggérés) et [ADR-018](ADR-018-modules-messaging-push-admin.md) (messagerie), sans les remplacer.

## Contexte
Le développeur refond l'écran de profil, en commençant par celui des autres comptes, d'après des captures de TikTok :
- nom en grand à gauche, @pseudo dessous, photo à droite, compteurs « Suivis · Followers · J'aime » alignés à gauche ;
- un grand bouton « Suivre », puis deux boutons ronds : **message** (avion en papier) et **« personne + »**, qui déplie sous les boutons une rangée de **comptes suggérés liés à ce profil** (« Comptes suggérés ⓘ · Tout voir › ») ;
- en haut à droite, une **flèche de partage** : feuille « Envoyer à » (amis, puis applications, puis Code QR, Signaler, Bloquer, Envoyer message) ;
- une cloche (notifications des nouvelles vidéos du compte).

L'API ne propose que les suggestions du compte connecté (`GET /users/me/suggestions`, ADR-058), et un message ne peut partager qu'une vidéo, une story (réponse) ou un live.

## Décision
Choix du développeur, parmi les options proposées.

### Comptes suggérés liés à un profil
- **`GET /users/:username/suggestions?limit=`** (compte connecté, 20 par défaut, 50 au plus, sans pagination), même réponse que `GET /users/me/suggestions`.
- **Candidats** : comptes que **suit ce profil** et comptes **suivis par ses abonnés** ; jamais le lecteur, le profil lui-même, un compte que le lecteur suit déjà, ni un compte masqué (bloqué dans un sens ou l'autre, suspendu). Une seule requête SQL (`findProfileSuggestionCandidates`).
- **Classement** : comme les suggestions (ADR-058) — « te suit », puis le nombre de comptes suivis par le lecteur qui le suivent (`followedBy`) — puis suivi par le profil, puis le nombre de ses abonnés qui le suivent, puis l'identifiant.
- **Complément** : comptes populaires (ADR-068) s'il reste de la place, jamais le profil lui-même.
- Profil inconnu, bloqué dans un sens ou l'autre ou suspendu : **404**. Déclarée après `users/me/suggestions` (`me` est un pseudo réservé).

### Profil partagé par message
- **`POST /conversations/:id/messages`** accepte **`profileId`** (texte facultatif) : un compte **visible de l'expéditeur** (ni bloqué dans un sens ou l'autre, ni suspendu), sinon **404** (`SharedProfileNotFoundError`). Son propre profil peut être partagé.
- Colonne **`messages.shared_user_id`** (UUID, **sans clé étrangère**, comme une vidéo ou un live partagés : un compte supprimé reste signalé « indisponible ») ; contraintes CHECK revues (migration `message_shared_profile`) : le message a un texte, une vidéo, un live, un profil ou un événement ; une ligne d'événement n'a pas de profil.
- **Lecture** : `MessageDto.profile` = `{ id, available, user? }`, `available` faux (et `user` absent) pour un compte supprimé ou **masqué au lecteur** (résolu pour chaque lecteur, comme une vidéo partagée).
- Push : « a partagé un profil ». Aucun compteur.

### Cloche
**Pas de cloche** pour l'instant : les notifications push ne sont pas encore dans l'app (pas de compte Apple Developer). Elle pourra s'ajouter avec elles.

### App (sans changement d'API)
Le reste de l'écran (mise en page, feuille « Envoyer à », Code QR du compte, Signaler, Bloquer, Envoyer message, « Tout voir ») est construit dans l'app avec les routes existantes.

## Conséquences
- Le bouton « personne + » a toujours des comptes à proposer, grâce au complément.
- Une requête de plus par ouverture de la rangée (pas au chargement du profil).
- Le partage d'un profil ne crée pas de conversation tout seul : la feuille « Envoyer à » passe, comme pour une vidéo, par une conversation ouverte ou créée.
- Limites : pas de partage vers WhatsApp, Snapchat ou Instagram (pas de SDK) ; « Copier le lien », SMS et la feuille système les remplacent. Les liens de profil restent des liens d'app (`tiktokclone://users/<pseudo>`).
