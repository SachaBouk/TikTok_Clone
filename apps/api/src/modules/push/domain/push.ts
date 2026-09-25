// Notifications push (APNs) : l'app enregistre le token de l'appareil, les modules envoient un message
// à un compte via PushService, et chaque appareil du compte le reçoit. Au mieux : un échec est journalisé
// et relancé, jamais propagé à la requête qui l'a déclenché.

// Build de développement (sandbox) ou App Store / TestFlight (production) : serveurs APNs différents.
export type PushEnvironment = 'sandbox' | 'production';

export interface PushDevice {
  token: string;
  userId: string;
  environment: PushEnvironment;
}

export interface PushMessage {
  title: string;
  body: string;
  // Regroupement dans le centre de notifications d'iOS (une conversation, l'activité…).
  threadId: string;
  // Clés personnalisées du payload, pour ouvrir le bon écran (`type`, `conversationId`…).
  data: Record<string, string>;
}

// Résultat pour un appareil : `invalidToken` si APNs ne le connaît plus (app désinstallée…).
export type PushResult = 'sent' | 'invalidToken';

// Token APNs : hexadécimal (64 caractères aujourd'hui, Apple se réserve de l'allonger).
export const PUSH_TOKEN_PATTERN = /^[0-9a-fA-F]{64,200}$/;
export const PUSH_BODY_MAX_LENGTH = 200;
