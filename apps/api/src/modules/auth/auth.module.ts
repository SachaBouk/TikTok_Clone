import { Module } from '@nestjs/common';
import { APP_GUARD } from '@nestjs/core';
import { JwtModule } from '@nestjs/jwt';
import { PassportModule } from '@nestjs/passport';
import { AuthService } from './application/auth.service';
import { AuthConfig } from './auth.config';
import { AccessTokenIssuer } from './domain/access-token-issuer';
import { AppleIdentityVerifier } from './domain/apple-identity-verifier';
import { AuthAccountRepository } from './domain/auth-account.repository';
import { PasswordHasher } from './domain/password-hasher';
import { RefreshTokenRepository } from './domain/refresh-token.repository';
import { JoseAppleIdentityVerifier } from './infrastructure/jose-apple-identity-verifier';
import { JwtAccessTokenIssuer } from './infrastructure/jwt-access-token-issuer';
import { PrismaAuthAccountRepository } from './infrastructure/prisma-auth-account.repository';
import { PrismaRefreshTokenRepository } from './infrastructure/prisma-refresh-token.repository';
import { ScryptPasswordHasher } from './infrastructure/scrypt-password-hasher';
import { AuthController } from './interfaces/auth.controller';
import { JwtAuthGuard } from './interfaces/jwt-auth.guard';
import { JwtStrategy } from './interfaces/jwt.strategy';

// Authentification (ADR-010). Enregistre aussi la garde JWT globale : toute route de l'API
// exige un access token, sauf celles marquées @Public(). Exporte AuthService pour vérifier
// l'access token hors HTTP (handshake WebSocket du module realtime, ADR-011).
@Module({
  imports: [
    PassportModule,
    JwtModule.registerAsync({
      useFactory: () => {
        const config = AuthConfig.fromEnv();
        return {
          secret: config.jwtAccessSecret,
          signOptions: { expiresIn: config.accessTokenTtlSeconds, algorithm: 'HS256' },
        };
      },
    }),
  ],
  controllers: [AuthController],
  providers: [
    { provide: AuthConfig, useFactory: () => AuthConfig.fromEnv() },
    { provide: AuthAccountRepository, useClass: PrismaAuthAccountRepository },
    { provide: RefreshTokenRepository, useClass: PrismaRefreshTokenRepository },
    { provide: PasswordHasher, useClass: ScryptPasswordHasher },
    { provide: AccessTokenIssuer, useClass: JwtAccessTokenIssuer },
    {
      provide: AppleIdentityVerifier,
      useFactory: (config: AuthConfig) => new JoseAppleIdentityVerifier(config.appleBundleId),
      inject: [AuthConfig],
    },
    {
      provide: AuthService,
      useFactory: (
        accounts: AuthAccountRepository,
        refreshTokens: RefreshTokenRepository,
        passwords: PasswordHasher,
        accessTokens: AccessTokenIssuer,
        apple: AppleIdentityVerifier,
        config: AuthConfig,
      ) =>
        new AuthService(accounts, refreshTokens, passwords, accessTokens, apple, {
          accessTokenTtlSeconds: config.accessTokenTtlSeconds,
          refreshTokenTtlDays: config.refreshTokenTtlDays,
        }),
      inject: [AuthAccountRepository, RefreshTokenRepository, PasswordHasher, AccessTokenIssuer, AppleIdentityVerifier, AuthConfig],
    },
    JwtStrategy,
    { provide: APP_GUARD, useClass: JwtAuthGuard },
  ],
  exports: [AuthService],
})
export class AuthModule {}
