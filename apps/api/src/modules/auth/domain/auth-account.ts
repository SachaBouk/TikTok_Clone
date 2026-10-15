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
  // Date de naissance (ADR-055), privée : jamais exposée. Nulle pour un compte Sign in with Apple.
  birthDate: Date | null;
}

export interface AuthTokens {
  accessToken: string;
  // Durée de validité de l'access token, en secondes.
  accessTokenExpiresIn: number;
  refreshToken: string;
}

// Suspension d'un compte par un administrateur (ADR-037) : connexion refusée, sessions révoquées, contenus masqués.
// Elle dure jusqu'à sa levée par un administrateur.
export interface AccountSuspension {
  userId: string;
  suspendedAt: Date;
  // Motif interne, visible des seuls administrateurs (la personne suspendue voit un message générique).
  reason: string;
  // Administrateur auteur de la suspension ; nul s'il a supprimé son compte depuis.
  suspendedBy: string | null;
}

export const MAX_SUSPENSION_REASON_LENGTH = 500;
