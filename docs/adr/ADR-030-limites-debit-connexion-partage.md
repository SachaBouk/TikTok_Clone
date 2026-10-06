# ADR-030 — Limites de débit : connexion et partages

## Statut
Accepté

Complète [ADR-028](ADR-028-regles-produit-premiere-version.md) et [ADR-025](ADR-025-role-redis.md), sans les remplacer.

## Contexte
Seule la messagerie avait des limites de débit (ADR-028 : messages et demandes). Deux routes publiques restaient ouvertes :
- `POST /auth/login` : on pouvait essayer des mots de passe sans limite, sur un compte ou sur beaucoup de comptes ;
- `POST /videos/:id/share` (ouverte aux invités, sans table) : rappeler la route gonflait le compteur de partages d'une vidéo.

## Décision
**Connexion par email et mot de passe** (choix du lead développeur) :
- Seuls les **échecs** comptent. Il y a deux limites : **5 échecs par email en 15 min** contre le forçage d'un compte, et **20 échecs par adresse IP en 15 min** contre l'essai d'un mot de passe courant sur beaucoup de comptes.
- Au-delà, toute tentative est refusée en **429 avec `Retry-After`**, même avec le bon mot de passe, jusqu'à la fin de la fenêtre. Le mot de passe n'est alors pas vérifié. Le message ne dit pas laquelle des deux limites est atteinte.
- Une connexion réussie remet à zéro le compteur de l'email, pas celui de l'IP.
- L'email n'apparaît dans les clés Redis que sous forme d'empreinte SHA-256.
- Sign in with Apple n'est pas limité : le jeton est vérifié par Apple, il n'y a rien à deviner.

**Partage public** (choix du lead développeur) :
- **Un seul partage compté par vidéo et par personne** sur 24 h glissantes. La personne est le compte connecté, sinon l'adresse IP de l'invité.
- Les partages suivants répondent 200 avec le compteur inchangé : rien ne change pour l'app.
- Le partage par message reste compté à chaque envoi : il est déjà limité par la messagerie.

**Adresse IP du client** : c'est `req.ip` d'Express. Le réglage facultatif `TRUST_PROXY` (`trust proxy` d'Express) désigne les proxys de confiance devant l'API ; par défaut, il n'y en a aucun. Le backoffice transmet l'adresse du navigateur dans `X-Forwarded-For` ; l'API ne s'en sert que si `TRUST_PROXY` désigne le backoffice.

**Mise en œuvre** : un limiteur partagé `src/rate-limit/` (port `RateLimiter`, adaptateurs Redis et en mémoire, module global), sur le modèle de `src/storage/`. Il sert la messagerie, `auth` et `interactions`. Il utilise des fenêtres fixes (clés `ratelimit:<clé>:<durée>:<index>`), plus un dédoublonnage `SET NX EX` pour les partages. Le port n'importe ni NestJS ni Redis : les services des modules le reçoivent par leur factory (ADR-003). Si Redis est indisponible, l'action est permise, et c'est journalisé.

## Alternatives
- **Toutes les tentatives de connexion par IP** (10 par minute) : ne bloque jamais un compte, mais freine peu une attaque répartie, et toutes les connexions au backoffice partagent l'IP du serveur Next. Rejeté.
- **Échecs par email seulement** : n'empêche pas d'essayer un mot de passe courant sur tous les comptes. Rejeté.
- **Blocage progressif** (délai doublé à chaque échec) ou CAPTCHA : plus fin, mais plus complexe ; un CAPTCHA demande un service externe. Reporté.
- **Partages limités en 429** (30 par heure) : chaque partage réel compte, mais un script ajoute encore 30 partages par heure. Rejeté.
- **Table des partages** : dédoublonnage exact et durable, mais une écriture en base par partage pour un simple compteur (ADR-006 : pas de table). Rejeté.
- **Un limiteur par module** : trois copies du même code. Rejeté au profit d'un limiteur partagé, comme le stockage objet.

## Conséquences
### Positives
- On ne peut plus deviner un mot de passe en masse, ni gonfler un compteur de partages en rappelant la route.
- Le même mécanisme, déjà éprouvé par la messagerie, sert toute l'API. L'app et le backoffice affichent le délai d'attente.

### Négatives
- Quelqu'un qui connaît l'email d'un compte peut en bloquer la connexion par mot de passe pendant 15 min (5 échecs).
- Les invités qui partagent une adresse IP (réseau d'entreprise ou d'école, NAT d'opérateur) partagent la limite de 20 échecs et le dédoublonnage des partages. Une adresse IPv6 se renouvelle facilement.
- Mal réglé, `TRUST_PROXY` fausse l'adresse du client : trop large, un client choisit son IP ; absent derrière un proxy, tous les clients ont l'IP du proxy.
- Ce sont des fenêtres fixes : jusqu'au double de la limite est possible à cheval sur deux fenêtres.

## Liens
- ADR-003 — Architecture backend : hexagonale allégée
- ADR-010 — Authentification
- ADR-014 — Cache et sessions avec Redis
- ADR-025 — Rôle de Redis
- ADR-028 — Règles produit de la première version
- Prolongé par [ADR-039](ADR-039-limites-debit-actions.md) — Limites de débit : inscription, réactions, commentaires, follows, vues et envois
