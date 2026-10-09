# ADR-053 — Live : comparaison des technologies de diffusion

## Statut
Accepté

Complète [ADR-016](ADR-016-perimetre-mvp.md) (périmètre) et [ADR-015](ADR-015-hebergement.md) (hébergement), sans les remplacer : le Live, reporté par l'ADR-016 (« Formats de contenu »), entre dans le périmètre (décision du développeur, dernière des fonctionnalités levées). Cet ADR **compare** les façons de diffuser la vidéo en direct, puis consigne la décision du développeur (section « Décision »).

## Contexte
Un live, comme sur TikTok : un compte filme en direct depuis l'iPhone ; des spectateurs regardent, écrivent dans un chat, envoient des cœurs et des cadeaux ; ses abonnés sont prévenus qu'il est « en direct ».

Ce qui existe déjà et que le live réutilise, quelle que soit la technologie :
- **temps réel** (ADR-011, ADR-022) : le WebSocket de l'API porte déjà les événements vers l'app. Le chat, les cœurs, les cadeaux reçus et le nombre de spectateurs peuvent y passer, sans lien avec la vidéo ;
- **cadeaux** (ADR-050) : la dépense atomique (`PrismaWalletRepository.sendGift`) et `gifts_sent` ; l'ADR-050 prévoit `video_id` facultatif pour les cadeaux en live ;
- **notifications** (activité, push) et **signalements** (ADR-038), **blocage et suspension** (ADR-029, ADR-037) ;
- **caméra** (ADR-052) : `AVCaptureSession` dans l'app.

Ce qui manque, et que cet ADR compare : **l'acheminement de la vidéo en direct** de l'iPhone qui filme vers les spectateurs. Le pipeline actuel (envoi d'un fichier, transcodage par le worker, HLS sur le CDN) ne convient pas : il traite des fichiers terminés.

Contraintes :
- **un seul développeur** : peu d'infrastructure à opérer, un environnement local complet en Docker (ADR-015) ;
- **hébergeur non choisi** (ADR-015 : Railway, Fly.io, AWS) : la solution ne doit pas l'imposer, ni l'empêcher. Point sensible : le WebRTC utilise des ports **UDP**, que certains hébergeurs ne proposent pas (Railway) ;
- **latence** : chat, cœurs et cadeaux réagissent à ce que l'on voit. Au-delà de quelques secondes, l'échange devient décalé ;
- **simulateur sans caméra** : la diffusion ne se vérifie que sur un iPhone ; la lecture, le chat et les cadeaux doivent pouvoir se tester dans le simulateur, avec une diffusion de test envoyée depuis le Mac.

## Options comparées

### 1. LiveKit auto-hébergé (serveur WebRTC, logiciel libre)
- **Principe** : serveur SFU WebRTC (Apache 2.0). L'iPhone publie sa caméra et son micro dans une « salle », les spectateurs s'y abonnent. L'API crée des jetons d'accès signés (JWT) : diffuser pour l'auteur, regarder pour les autres.
- **Latence** : sous la seconde.
- **App** : SDK Swift officiel (SPM, Apache 2.0) : publication et lecture. Un lecteur à part du lecteur HLS existant.
- **Local** : une image Docker (`livekit/livekit-server`, mode dev), à ajouter au `docker-compose.yml`. Diffusion de test depuis le Mac (outil `lk`, ou un navigateur) : tout le reste se teste dans le simulateur.
- **Production** : ports UDP (une plage, ou un seul port), TCP de secours, TURN intégré pour les réseaux restrictifs, IP publique connue. Mise à l'échelle par plusieurs nœuds avec Redis (déjà présent).
- **Sortie de secours** : **LiveKit Cloud**, même protocole et mêmes SDK : passer de l'auto-hébergement au service managé ne change que l'URL et les clés. Utile si l'hébergeur choisi n'a pas d'UDP.
- **Replay** : possible plus tard (service `egress` à part, lourd : il enregistre par un navigateur sans interface).
- **Coût** : l'infrastructure seule (serveur et bande passante). LiveKit Cloud : forfait (50 $ par mois, 150 000 minutes de participant), puis à la minute et au Go transféré.

### 2. MediaMTX auto-hébergé (serveur multi-protocoles, logiciel libre)
- **Principe** : un seul binaire (MIT, image Docker). Il reçoit le flux en RTMP, SRT ou WHIP, et le redistribue en HLS (dont LL-HLS) ou en WebRTC (WHEP). Accès contrôlés par un appel HTTP à l'API, ou par JWT.
- **Latence** : 2 à 5 s en LL-HLS ; sous la seconde en WebRTC (WHEP), mais l'app devrait alors embarquer une pile WebRTC sans SDK clé en main.
- **App** :
  - diffusion en RTMP ou SRT par HaishinKit (BSD-3, SPM) ;
  - lecture HLS par `AVPlayer`, comme le feed.
- **Local** : une image Docker ; diffusion de test par FFmpeg depuis le Mac.
- **Production** : HLS en TCP seulement, mis en cache par un CDN : beaucoup de spectateurs à bas coût, chez n'importe quel hébergeur.
- **Replay** : enregistrement en fichiers (fMP4) que le worker pourrait transcoder en vidéo.
- **Coût** : l'infrastructure seule, et le CDN.

### 3. Cloudflare Stream Live (service managé)
- **Principe** : entrée en RTMP, SRT ou WHIP ; sortie en HLS ou en WebRTC (WHEP).
- **Latence** : sous la seconde en WebRTC ; plusieurs secondes en HLS.
- **App** : HaishinKit (RTMP) ou une pile WebRTC (WHIP), lecture HLS par `AVPlayer` ou WebRTC.
- **Local** : aucun équivalent local ; le développement passe par le service en ligne (compte, clés, Internet), hors de l'environnement Docker de l'ADR-015.
- **Production** : rien à opérer.
- **Coût** : à la minute regardée, 1 $ les 1 000 minutes (WebRTC facturé à partir du 15 octobre 2026). Cohérent avec un stockage R2 si l'hébergeur retenu est Cloudflare.

### 4. Mux Live (service managé)
- **Principe** : entrée en RTMP ou SRT ; sortie en HLS faible latence ; enregistrement automatique du live, publié ensuite comme une vidéo.
- **Latence** : quelques secondes (LL-HLS).
- **App** : HaishinKit (RTMP), lecture HLS par `AVPlayer`.
- **Local** : aucun équivalent local.
- **Coût** : environ 0,05 $ par minute diffusée, et 0,0008 à 0,0012 $ par minute regardée (720p), les 100 000 premières minutes regardées offertes.

### 5. Amazon IVS (service managé)
- **Principe** : « Real-Time Streaming » (WebRTC, moins de 300 ms) ou « Low-Latency Streaming » (HLS, 3 à 5 s).
- **App** : SDK Swift d'Amazon.
- **Local** : aucun équivalent local ; impose AWS, l'un des trois hébergeurs envisagés.
- **Coût** : en temps réel, environ 0,072 $ par heure de participant, diffuseur et spectateurs compris.

## Ordre de grandeur des coûts
Hypothèse : 100 heures de live par mois, 50 spectateurs en moyenne, soit 5 000 heures regardées (300 000 minutes). En 720p, environ 1,5 Mbit/s, soit environ 3,4 To transférés.

| Option | Coût mensuel estimé |
|---|---|
| LiveKit auto-hébergé | serveur et bande passante : de quelques dizaines d'euros chez un hébergeur à bande passante incluse à environ 300 $ de transfert chez AWS (0,09 $ le Go) |
| LiveKit Cloud | environ 500 $ (participants environ 130 $, transfert environ 370 $) |
| MediaMTX auto-hébergé | serveur et CDN : le moins cher à grande audience (segments HLS mis en cache) |
| Cloudflare Stream (WebRTC) | environ 300 $ |
| Mux | environ 460 $ (diffusion environ 300 $, lecture environ 160 $) |
| Amazon IVS (temps réel) | environ 370 $ |

Tarifs publics relevés en octobre 2026, souvent par des sites tiers qui se contredisent : à revérifier sur les pages officielles avant tout engagement. Pour une démo, toutes les options restent dans leur offre gratuite ou presque.

## Comparaison

| Critère | LiveKit auto-hébergé | MediaMTX | Cloudflare Stream | Mux | Amazon IVS |
|---|---|---|---|---|---|
| Latence | < 1 s | 2–5 s (LL-HLS) | < 1 s (WebRTC) | quelques s | < 0,3 s |
| Environnement local Docker | oui | oui | non | non | non |
| Indépendance de l'hébergeur (ADR-015) | oui, UDP requis (sinon LiveKit Cloud) | oui (TCP seul) | lié à Cloudflare | oui | lié à AWS |
| SDK iOS diffusion + lecture | officiel, complet | HaishinKit + `AVPlayer` | HaishinKit ou WebRTC à intégrer | HaishinKit + `AVPlayer` | officiel |
| Infrastructure à opérer | un service (UDP, TURN) | un service | aucune | aucune | aucune |
| Grande audience | plusieurs nœuds ou Cloud | CDN, simple | gérée | gérée | gérée |
| Replay | possible, lourd | fichiers vers le worker | non (WebRTC) | automatique | possible |

## Recommandation
**LiveKit, auto-hébergé en Docker**, avec **LiveKit Cloud** comme sortie de secours sans changer le code :
- latence sous la seconde : chat, cœurs et cadeaux suivent ce que l'on voit, comme sur TikTok ;
- environnement local complet (ADR-015), et tests de bout en bout avec une diffusion envoyée depuis le Mac ;
- SDK iOS officiel pour diffuser et regarder, au lieu d'assembler une bibliothèque RTMP et le lecteur HLS ;
- pas de dépendance à un hébergeur. Si celui qui est retenu n'ouvre pas l'UDP, LiveKit Cloud prend le relais (même protocole).

**Alternative sérieuse : MediaMTX** (RTMP vers LL-HLS), si l'on préfère réutiliser le lecteur HLS, n'exposer que du TCP et viser de grandes audiences au plus bas coût, au prix de 2 à 5 s de décalage dans le chat et les cadeaux.

Les services managés (Cloudflare Stream, Mux, IVS) n'ont pas d'équivalent local et lient le projet à un fournisseur avant le choix de l'hébergeur. Ils restent des options de production si l'auto-hébergement s'avère trop lourd.

## Décision
Choix du développeur, parmi les options proposées :
- **LiveKit auto-hébergé** (recommandation suivie) ;
- **tout compte connecté** peut lancer un live ;
- **pas de replay** : le live disparaît à sa fin ;
- **interactions** : chat, cadeaux, cœurs, abonnés prévenus, **partage du live** à d'autres comptes et **signalement du live**.

### Diffusion (LiveKit)
- **Serveur** : image `livekit/livekit-server` (version figée) dans `docker-compose.yml`, en mode développement en local. En production : LiveKit auto-hébergé (ports UDP) ou LiveKit Cloud, au choix de l'hébergement (ADR-015), sans changer le code : `LIVEKIT_URL`, `LIVEKIT_API_KEY`, `LIVEKIT_API_SECRET`.
- **Une salle par live** (nom = identifiant du live). L'API délivre les **jetons d'accès** (JWT signé par la clé LiveKit, SDK `livekit-server-sdk`) :
  - l'auteur peut publier sa caméra et son micro ;
  - un spectateur ne peut que s'abonner, sans publier, invité compris (identité anonyme).
- **App** : SDK Swift officiel de LiveKit (`client-sdk-swift`, version figée), pour diffuser et regarder.
- **Événements du serveur vidéo** : webhook `POST /webhooks/livekit`, signé par LiveKit et vérifié avec la clé. Il sert à l'arrivée des spectateurs (pic et total) et au départ de l'auteur.

### Règles d'un live
- **Un live à la fois** par compte (relancer pendant un live le reprend, par exemple après une relance de l'app), **2 heures au plus**, titre facultatif de 80 caractères au plus, **10 lancements par jour** (limite de débit, ADR-039).
- **Qui regarde** : tout le monde, invités compris, en lecture seule pour les invités. Exclus :
  - les comptes bloqués, dans un sens ou dans l'autre (ADR-029) ;
  - un live dont l'auteur est suspendu (ADR-037).
- **Fin du live**, dans l'un de ces cas :
  - par l'auteur ;
  - à 2 heures (job différé) ;
  - auteur déconnecté du serveur vidéo depuis plus de 60 s (job différé, sans effet s'il est revenu ; 2 min au lancement pour se connecter) ;
  - par un administrateur ;
  - à la suspension ou à la suppression du compte.

  Une maintenance périodique (5 min) rattrape un job perdu : elle termine les lives qui dépassent 2 heures ou dont la salle n'existe plus, et reprogramme la vérification d'un auteur absent de sa salle.
- **À la fin** :
  - le chat est supprimé ;
  - restent pour l'auteur la durée, le pic et le total de spectateurs, les cœurs et les cadeaux reçus.

### Chat, cœurs, cadeaux
- **Passent par l'API**, avec ses contrôles (compte connecté, blocages, suspensions, limites de débit). Ils sont **diffusés dans la salle par les messages de données de LiveKit**, envoyés par l'API : tous les spectateurs les reçoivent, invités compris, sans changer le WebSocket de l'ADR-011.
- **Chat** :
  - 150 caractères au plus, nettoyés ;
  - les 50 derniers messages sont donnés à l'arrivée ;
  - l'auteur du live peut retirer un message ;
  - limite de débit propre au chat.
- **Cœurs** : les touchers sont envoyés par lots, et comptés pour le live.
- **Cadeaux** : même dépense que sur les vidéos (ADR-050), vers l'auteur du live. `gifts_sent.live_id` remplace la vidéo. Le cadeau est annoncé dans la salle (animation chez tous) ; pas de notification d'activité, puisque l'auteur le voit en direct.

### Abonnés prévenus, partage, signalement
- **Au début du live** :
  - notification d'activité « … est en direct » et push aux abonnés ;
  - le live apparaît en tête de la rangée de la boîte de réception (« EN DIRECT ») et sur la photo du profil.
- **Partage** :
  - lien d'app `tiktokclone://lives/<id>` par la feuille de partage ;
  - « Envoyer par message » : une carte du live dans la conversation, « Live terminé » ensuite (`messages.live_id`).
- **Signalement** :
  - nouvelle cible `live`, titre copié (ADR-038) ;
  - au backoffice, « Arrêter le live » (motif obligatoire, annoncé à l'auteur, journalisé) ;
  - la suspension du compte arrête son live.

### Ce que cela ne fait pas
- **Pas de co-animation** (invités à l'écran), ni de Shop, ni de bataille de lives.
- **Pas d'enregistrement** du live.

### Limites
- **Chat entre spectateurs** : il est diffusé à toute la salle. Un spectateur ne voit pas les messages d'un compte qu'il a bloqué seulement si l'app connaît ce blocage.
- **Diffusion** : elle ne se vérifie que sur un iPhone, puisque le simulateur n'a pas de caméra. La lecture, le chat et les cadeaux se testent dans le simulateur, avec une diffusion de test envoyée depuis le Mac.

## Liens
- ADR-003 — Architecture backend
- ADR-011 — Temps réel
- ADR-015 — Hébergement
- ADR-016 — Périmètre
- ADR-038 — Signalements
- ADR-050 — Cadeaux en jetons
- ADR-051 — Stories
- ADR-052 — Enregistrement et édition vidéo
- ADR-029 — Blocage
- ADR-037 — Suspension
- ADR-039 — Limites de débit
