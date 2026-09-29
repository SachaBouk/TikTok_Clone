import type { INestApplication } from '@nestjs/common';
import { DocumentBuilder, SwaggerModule, type OpenAPIObject } from '@nestjs/swagger';
import { OPENAPI_PUBLIC_EXTENSION } from '../modules/auth/interfaces/public.decorator';
import {
  ConversationAcceptedEvent,
  ConversationDeletedEvent,
  ConversationReadEvent,
  MessageCreatedEvent,
  MessageDeletedEvent,
  TypingClientMessage,
  TypingEvent,
} from '../modules/messaging/interfaces/messaging.events';
import { NotificationCreatedEvent, UnreadNotificationsChangedEvent } from '../modules/notifications/interfaces/notifications.events';
import { VideoProcessedEvent } from '../modules/videos/interfaces/videos.events';
import { WalletUpdatedEvent } from '../modules/wallet/interfaces/wallet.events';

const BEARER = 'bearer';

// Événements du WebSocket `/realtime` (ADR-011), par valeur de leur champ `event`. OpenAPI ne décrit pas
// un WebSocket : ils sont publiés comme schémas (union `RealtimeEvent`), pour que le client Swift ait
// des types Codable à décoder.
const REALTIME_EVENTS = {
  videoProcessed: VideoProcessedEvent,
  notificationCreated: NotificationCreatedEvent,
  unreadNotificationsChanged: UnreadNotificationsChangedEvent,
  messageCreated: MessageCreatedEvent,
  messageDeleted: MessageDeletedEvent,
  conversationRead: ConversationReadEvent,
  conversationAccepted: ConversationAcceptedEvent,
  conversationDeleted: ConversationDeletedEvent,
  typing: TypingEvent,
  walletUpdated: WalletUpdatedEvent,
};
// Messages de l'app vers le serveur (union `RealtimeClientMessage`), à encoder avec les types générés.
const REALTIME_CLIENT_MESSAGES = {
  typing: TypingClientMessage,
};

// Contrat d'API (ADR-005) : source unique pour le client iOS (swift-openapi-generator) et la doc.
// Partagé par main.ts (Swagger UI) et export.ts (fichier openapi.json versionné).
export function buildOpenApiDocument(app: INestApplication): OpenAPIObject {
  const config = new DocumentBuilder()
    .setTitle('API TikTok clone')
    .setDescription(
      'API REST du backend. Les routes exigent un access token (`Authorization: Bearer …`), ' +
        'sauf celles sans cadenas, accessibles en mode invité.\n\n' +
        '**Temps réel** : WebSocket `ws://<hôte>/realtime`, avec le même en-tête `Authorization: Bearer …` ' +
        '(sans token valide : HTTP 401 au handshake). Le serveur envoie des messages JSON décrits par le schéma ' +
        '`RealtimeEvent` ; l’app peut envoyer ceux du schéma `RealtimeClientMessage` (`typing`), les autres sont ignorés. Fermeture 4001 : access token expiré, rafraîchir puis se ' +
        'reconnecter. Rien n’est rejoué après une coupure : à la reconnexion, relire l’état par l’API REST.',
    )
    .setVersion('0.1.0')
    .addServer('http://localhost:3000', 'Local')
    .addBearerAuth({ type: 'http', scheme: 'bearer', bearerFormat: 'JWT' }, BEARER)
    // Sécurisé par défaut, comme la garde globale JwtAuthGuard.
    .addSecurityRequirements(BEARER)
    .build();

  const document = SwaggerModule.createDocument(app, config, {
    // Le nom de la méthode du controller devient l'operationId, donc le nom de la méthode Swift
    // générée (`client.login(…)` plutôt que `client.AuthController_login(…)`).
    operationIdFactory: (_controllerKey, methodKey) => methodKey,
    extraModels: [...Object.values(REALTIME_EVENTS), ...Object.values(REALTIME_CLIENT_MESSAGES)],
  });

  markPublicOperations(document);
  unwrapSingleRefAllOf(document);
  addUnion(document, 'RealtimeEvent', 'Message envoyé par le serveur sur le WebSocket `/realtime` (ADR-011).', REALTIME_EVENTS);
  addUnion(document, 'RealtimeClientMessage', 'Message envoyé par l’app sur le WebSocket `/realtime` (les autres sont ignorés).', REALTIME_CLIENT_MESSAGES);
  assertUniqueOperationIds(document);
  return document;
}

// Union d'événements distingués par `event`. swift-openapi-generator en fait un enum (`.videoProcessed(…)`,
// `.notificationCreated(…)`…) décodable (ou encodable) directement depuis (vers) un message du WebSocket.
function addUnion(document: OpenAPIObject, name: string, description: string, members: Record<string, { name: string }>) {
  const refs = Object.fromEntries(Object.entries(members).map(([event, schema]) => [event, `#/components/schemas/${schema.name}`]));
  document.components!.schemas![name] = {
    description,
    oneOf: Object.values(refs).map(($ref) => ({ $ref })),
    discriminator: { propertyName: 'event', mapping: refs },
  };
}

// @nestjs/swagger écrit une référence à un enum nommé sous la forme `{ allOf: [{ $ref }] }`.
// swift-openapi-generator en fait une struct enveloppe (`status.value1`) au lieu d'utiliser l'enum
// directement : on remplace cette forme par un simple `$ref`.
function unwrapSingleRefAllOf(document: OpenAPIObject) {
  for (const schema of Object.values(document.components?.schemas ?? {})) {
    const properties = (schema as { properties?: Record<string, Record<string, unknown>> }).properties ?? {};
    for (const [name, property] of Object.entries(properties)) {
      const allOf = property.allOf as { $ref?: string }[] | undefined;
      if (Object.keys(property).length === 1 && allOf?.length === 1 && allOf[0]?.$ref) {
        properties[name] = { $ref: allOf[0].$ref };
      }
    }
  }
}

// Les routes @Public() n'exigent pas de token : `security: []` annule l'exigence globale.
function markPublicOperations(document: OpenAPIObject) {
  for (const operation of operations(document)) {
    if (operation[OPENAPI_PUBLIC_EXTENSION]) {
      operation.security = [];
      delete operation[OPENAPI_PUBLIC_EXTENSION];
    }
  }
}

// Deux méthodes de controller homonymes produiraient deux operationId identiques :
// spec invalide et génération Swift en échec. On échoue tout de suite, avec le nom en cause.
function assertUniqueOperationIds(document: OpenAPIObject) {
  const seen = new Set<string>();
  for (const { operationId } of operations(document)) {
    if (!operationId) continue;
    if (seen.has(operationId)) {
      throw new Error(`operationId en double : « ${operationId} ». Renommez l'une des méthodes de controller.`);
    }
    seen.add(operationId);
  }
}

function* operations(document: OpenAPIObject) {
  for (const path of Object.values(document.paths)) {
    for (const method of ['get', 'put', 'post', 'delete', 'patch'] as const) {
      const operation = path[method];
      if (operation) yield operation as typeof operation & Record<string, unknown>;
    }
  }
}
