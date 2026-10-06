# ADR-044 — Renvoi d'un message en échec : identifiant d'envoi

## Statut
Accepté

Complète [ADR-028](ADR-028-regles-produit-premiere-version.md) (messagerie : demandes, limites d'envoi) et [ADR-022](ADR-022-temps-reel-protocole.md) (événement `messageCreated`), sans les remplacer.

## Contexte
Dans l'app, un message dont l'envoi échouait disparaissait du fil et son texte revenait dans le champ de saisie. Pour qu'un message en échec reste affiché et puisse être renvoyé, il faut régler deux questions.

- **Le doublon.** Une coupure peut survenir après que l'API a enregistré le message, avant que la réponse arrive. L'app croit alors à un échec. Un renvoi créait un second message identique, compté une seconde fois dans les limites d'envoi, avec une seconde notification push. L'API n'avait aucun moyen de reconnaître le même envoi.
- **La reconnaissance de l'écho.** L'écho temps réel de son propre message (`messageCreated`) retirait la bulle « Envoi… » en comparant le texte. Deux messages identiques envoyés à la suite pouvaient être confondus.

## Décision
- **Identifiant d'envoi** (`clientMessageId`, UUID choisi par l'app) : facultatif dans `POST /conversations/:id/messages`.
  - Colonne `messages.client_message_id`, index unique `(sender_id, client_message_id)` (migration `message_client_id`). Les valeurs nulles ne se gênent pas : un envoi sans identifiant (partage d'une vidéo par message) se comporte comme avant.
  - **Renvoi avec le même identifiant** : l'API rend le message déjà créé (201, même réponse). Rien n'est recréé, recompté dans les limites, annoncé ni poussé, et le partage d'une vidéo n'est pas recompté. C'est vrai même si la conversation ne permet plus d'écrire depuis (blocage, demande épuisée) : le message était parti avant.
  - **Envois simultanés** avec le même identifiant : l'index unique n'en laisse passer qu'un. Les autres requêtes relisent le message gagnant et le rendent, sans rien annoncer.
  - **Même identifiant dans une autre conversation** du même expéditeur : **409**. C'est une erreur de l'app.
  - **Message retiré depuis** par son expéditeur : la ligne n'existe plus, et un renvoi crée un nouveau message.
  - **Exposition** : `clientMessageId` n'apparaît que dans la réponse à l'envoi et dans l'écho `messageCreated` adressé à l'expéditeur. Il n'est jamais montré au destinataire, ni dans les listes de messages ou de conversations (`MessageItem.clientMessageId`, posé par le service).
- **Dans l'app** :
  - chaque message écrit reçoit un identifiant d'envoi, le même à chaque essai ;
  - **« Non envoyé »** : en cas d'échec, la bulle reste à sa place, avec un « ! » rouge et « Non envoyé · Toucher pour réessayer ». Un toucher ouvre un menu natif « Réessayer », « Copier », « Supprimer ». « Réessayer » est absent quand la conversation ne permet plus d'écrire. Le texte ne revient plus dans le champ ;
  - **renvoi à la main** (comme Messages), jamais automatique. Une coupure ne déclenche pas d'alerte : la bulle suffit. Une limite d'envoi (429) bloque aussi le renvoi pendant son délai, et un renvoi trop tôt rappelle ce délai. Un refus (403) affiche le message de l'API et relit la conversation ;
  - **durée de vie** : les messages sortants sont gardés par `MessagingModel` pendant la session de l'app. Ils restent après la fermeture de la conversation, mais sont oubliés à la relance, à la déconnexion et à la suppression de la conversation. Leur texte n'est jamais écrit sur le disque ;
  - l'écho temps réel qui porte l'identifiant retire la bulle en attente, ou en échec si la réponse s'était perdue. La comparaison du texte disparaît.

## Alternatives
- **App seule, sans changement d'API** : avant un renvoi, relire les derniers messages et y chercher le même texte. C'est une heuristique : deux messages identiques envoyés exprès seraient confondus, et une requête supplémentaire part à chaque renvoi. Écarté.
- **En-tête `Idempotency-Key` générique** (gardé dans Redis pour toutes les routes) : plus général, mais il faut stocker les réponses avec une durée de vie, et il diverge de la base en cas de perte de Redis. La messagerie suffit pour l'instant. Écarté.
- **Garder les messages en échec sur le disque** (retrouvés après une relance) : le texte des messages serait alors stocké sur l'appareil, ce qui n'est le cas nulle part ailleurs. Écarté.
- **Renvoi automatique au retour de la connexion** (comme WhatsApp) : il devient sûr grâce à l'identifiant, mais un message peut ne plus être d'actualité. Écarté pour l'instant.

## Conséquences
### Positives
- Un renvoi ne crée jamais de doublon, même quand la réponse s'est perdue ou que deux essais partent ensemble.
- L'utilisateur garde ce qu'il a écrit, peut le renvoyer depuis la conversation même après l'avoir quittée, ou le supprimer.
- L'écho de son propre message est reconnu sans ambiguïté.

### Négatives
- Une colonne et un index de plus sur `messages` (identifiant nul pour les anciens messages et les partages de vidéo).
- Une lecture de plus avant chaque envoi qui porte un identifiant.
- Un message non envoyé est perdu si l'app est fermée (choix assumé : rien n'est écrit sur le disque).
- La boîte de réception ne signale pas une conversation qui contient un message non envoyé.

## Liens
- ADR-028 — Règles produit de la première version (messagerie)
- ADR-022 — Temps réel : protocole
- ADR-003 — Architecture backend
- ADR-006 — Persistance
