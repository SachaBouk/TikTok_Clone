import 'reflect-metadata';
import { ValidationPipe } from '@nestjs/common';
import { NestFactory } from '@nestjs/core';
import type { NestExpressApplication } from '@nestjs/platform-express';
import { SwaggerModule } from '@nestjs/swagger';
import { AppModule } from './app.module';
import { parseTrustProxy } from './http/trust-proxy';
import { RealtimeService } from './modules/realtime/application/realtime.service';
import { RealtimeWsAdapter } from './modules/realtime/interfaces/realtime-ws.adapter';
import { buildOpenApiDocument } from './openapi/openapi';

async function bootstrap() {
  // `rawBody` : corps brut gardé à côté du JSON lu (`req.rawBody`), pour vérifier la signature HMAC du webhook
  // RevenueCat, calculée sur les octets reçus (ADR-031).
  const app = await NestFactory.create<NestExpressApplication>(AppModule, { rawBody: true });
  // Adresse IP du client derrière un proxy (limites de débit, ADR-030) : voir TRUST_PROXY dans .env.example.
  app.set('trust proxy', parseTrustProxy(process.env.TRUST_PROXY));
  // SIGTERM / SIGINT : ferme proprement les workers BullMQ et les connexions (onModuleDestroy).
  app.enableShutdownHooks();
  // Valide les corps et paramètres de requête (classes class-validator) ; les champs inattendus sont refusés.
  // `transform` : le handler reçoit l'instance de la classe, avec conversions (`limit` en nombre) et valeurs par défaut.
  app.useGlobalPipes(new ValidationPipe({ whitelist: true, forbidNonWhitelisted: true, transform: true }));
  // Documentation interactive sur /docs, spec brute sur /docs/openapi.json (ADR-005).
  // Montées directement sur Express : la garde JWT ne s'y applique pas.
  SwaggerModule.setup('docs', app, buildOpenApiDocument(app), { jsonDocumentUrl: 'docs/openapi.json' });
  // WebSocket natif sur le même port (ADR-011), authentifié au handshake par l'access token.
  app.useWebSocketAdapter(new RealtimeWsAdapter(app, app.get(RealtimeService)));
  await app.listen(process.env.PORT ?? 3000);
}

void bootstrap();
