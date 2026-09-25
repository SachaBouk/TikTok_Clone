export interface AppleIdentity {
  // Identifiant Apple stable de l'utilisateur pour cette app.
  sub: string;
  // Absent si l'utilisateur ne l'a pas partagé ; peut être une adresse relais privée Apple.
  email: string | null;
}

// Vérifie l'identity token renvoyé par Sign in with Apple (ADR-010).
// Lève InvalidAppleTokenError si le token est invalide, expiré ou destiné à une autre app.
export abstract class AppleIdentityVerifier {
  abstract verify(identityToken: string): Promise<AppleIdentity>;
}
