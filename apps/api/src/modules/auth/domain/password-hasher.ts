export abstract class PasswordHasher {
  abstract hash(password: string): Promise<string>;
  // Avec `hash` nul (compte inconnu ou sans mot de passe), l'adaptateur doit quand même faire le calcul
  // et renvoyer false : la durée de réponse ne révèle pas si l'email existe.
  abstract verify(password: string, hash: string | null): Promise<boolean>;
}
