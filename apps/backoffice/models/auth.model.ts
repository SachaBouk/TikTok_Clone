import type { AdminUserDto, AuthTokensDto } from '@repo/shared';
import { ApiError } from '@/lib/api-error';
import { API_URL } from '@/lib/config';
import type { RefreshOutcome } from '@/lib/token-refresh';

// Model de l'authentification (ADR-004 : les models appellent l'API REST, ADR-010 pour les jetons).
// Sans `server-only` : le proxy s'en sert aussi pour rafraîchir la session.

async function post(path: string, body: unknown, extraHeaders: Record<string, string> = {}): Promise<Response> {
  return fetch(`${API_URL}${path}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', ...extraHeaders },
    body: JSON.stringify(body),
    cache: 'no-store',
  });
}

// Email et mot de passe : ApiError 401 s'ils sont incorrects, 429 après trop d'échecs (ADR-030).
// `clientIp` : adresse du navigateur, transmise dans X-Forwarded-For. L'API ne s'en sert pour sa limite par IP
// que si TRUST_PROXY désigne le backoffice comme proxy de confiance ; sinon, elle compte l'adresse du serveur Next.
export async function login(email: string, password: string, clientIp: string | null = null): Promise<AuthTokensDto> {
  const response = await post('/auth/login', { email, password }, clientIp ? { 'X-Forwarded-For': clientIp } : {});
  if (!response.ok) throw await ApiError.from(response);
  return (await response.json()) as AuthTokensDto;
}

// Compte connecté, s'il est administrateur : ApiError 403 sinon.
export async function getAdminSession(accessToken: string): Promise<AdminUserDto> {
  const response = await fetch(`${API_URL}/admin/me`, { headers: { Authorization: `Bearer ${accessToken}` }, cache: 'no-store' });
  if (!response.ok) throw await ApiError.from(response);
  return (await response.json()) as AdminUserDto;
}

// Rotation du refresh token (ADR-010). À appeler via le rafraîchisseur dédupliqué (lib/token-refresh).
export async function refreshSession(refreshToken: string): Promise<RefreshOutcome> {
  const response = await post('/auth/refresh', { refreshToken });
  if (response.ok) return { kind: 'refreshed', tokens: (await response.json()) as AuthTokensDto };
  if (response.status === 400 || response.status === 401) return { kind: 'rejected' };
  throw await ApiError.from(response);
}

// Révoque la session côté API. Au mieux : une API injoignable n'empêche pas de se déconnecter du backoffice.
export async function logout(refreshToken: string): Promise<void> {
  await post('/auth/logout', { refreshToken }).catch(() => undefined);
}
