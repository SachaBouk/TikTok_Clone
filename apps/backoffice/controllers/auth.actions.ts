'use server';

import { headers } from 'next/headers';
import { redirect } from 'next/navigation';
import { ApiError } from '@/lib/api-error';
import { clientAddress, formatDelay } from '@/lib/format';
import { clearSession, saveSession } from '@/lib/session';
import { safeReturnPath } from '@/lib/session-cookies';
import * as auth from '@/models/auth.model';

// Controllers de la connexion (ADR-004 : les Server Actions sont les controllers du MVC).

export interface LoginState {
  error: string | null;
  email: string;
}

// Connexion par email et mot de passe (`/auth/login` de l'API), réservée aux administrateurs : le rôle est
// vérifié avant d'ouvrir la session du backoffice. Un compte sans rôle voit sa session API révoquée aussitôt.
export async function login(_previous: LoginState, form: FormData): Promise<LoginState> {
  const email = textField(form, 'email').trim();
  const password = textField(form, 'password');
  if (!email || !password) return { error: 'Saisis ton email et ton mot de passe.', email };

  try {
    const tokens = await auth.login(email, password, clientAddress((await headers()).get('x-forwarded-for')));
    try {
      await auth.getAdminSession(tokens.accessToken);
    } catch (error) {
      await auth.logout(tokens.refreshToken);
      throw error;
    }
    await saveSession(tokens);
  } catch (error) {
    if (error instanceof ApiError && error.status === 401) return { error: 'Email ou mot de passe incorrect.', email };
    if (error instanceof ApiError && error.status === 403) return { error: 'Ce compte n’a pas accès au backoffice.', email };
    if (error instanceof ApiError && error.status === 429) {
      return { error: `Trop de tentatives de connexion. Réessaie dans ${formatDelay(error.retryAfterSeconds ?? 60)}.`, email };
    }
    return { error: 'L’API est injoignable. Réessaie dans un instant.', email };
  }
  redirect(safeReturnPath(textField(form, 'suite')));
}

export async function logout(): Promise<void> {
  const refreshToken = await clearSession();
  if (refreshToken) await auth.logout(refreshToken);
  redirect('/login');
}

// Champ texte d'un formulaire ; vide s'il manque ou si c'est un fichier.
function textField(form: FormData, name: string): string {
  const value = form.get(name);
  return typeof value === 'string' ? value : '';
}
