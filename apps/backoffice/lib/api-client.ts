import 'server-only';
import { cookies } from 'next/headers';
import { redirect } from 'next/navigation';
import { ApiError } from './api-error';
import { API_URL } from './config';
import { ACCESS_COOKIE } from './session-cookies';

type Query = Record<string, string | number | undefined | null>;

// Client de l'API REST pour les models (ADR-004), côté serveur uniquement : il envoie l'access token de
// la session. Le proxy l'a rafraîchi avant la requête. Session refusée (401) ou rôle retiré (403) :
// fin de session. Les autres erreurs remontent en ApiError. `body` : corps JSON (PUT).
export async function apiRequest<T>(method: 'GET' | 'DELETE' | 'PUT', path: string, query: Query = {}, body?: unknown): Promise<T> {
  const accessToken = (await cookies()).get(ACCESS_COOKIE)?.value;
  if (!accessToken) redirect('/auth/fin?raison=session');

  const url = new URL(`${API_URL}${path}`);
  for (const [name, value] of Object.entries(query)) {
    if (value !== undefined && value !== null && value !== '') url.searchParams.set(name, String(value));
  }
  const response = await fetch(url, {
    method,
    headers: { Authorization: `Bearer ${accessToken}`, ...(body === undefined ? {} : { 'Content-Type': 'application/json' }) },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
    cache: 'no-store',
  });

  if (response.status === 401) redirect('/auth/fin?raison=session');
  if (response.status === 403) redirect('/auth/fin?raison=acces');
  if (!response.ok) throw await ApiError.from(response);
  return (response.status === 204 ? undefined : await response.json()) as T;
}

// Ressource absente (404) : null, pour que la page affiche « introuvable ».
export async function orNull<T>(request: Promise<T>): Promise<T | null> {
  try {
    return await request;
  } catch (error) {
    if (error instanceof ApiError && error.status === 404) return null;
    throw error;
  }
}
