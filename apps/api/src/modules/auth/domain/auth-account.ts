// Données d'authentification d'un compte. Le module `auth` possède les colonnes d'identification
// de la table `users` (email, hash du mot de passe, identifiant Apple) et la création des comptes ;
// le module `users` possède le profil public.
export interface AuthAccount {
  id: string;
  // Nul pour un compte créé uniquement via Sign in with Apple.
  passwordHash: string | null;
}

export interface NewAccount {
  email: string | null;
  passwordHash: string | null;
  appleSub: string | null;
  username: string;
  displayName: string;
}

export interface AuthTokens {
  accessToken: string;
  // Durée de validité de l'access token, en secondes.
  accessTokenExpiresIn: number;
  refreshToken: string;
}
