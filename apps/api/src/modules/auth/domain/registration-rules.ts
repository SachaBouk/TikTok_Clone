// Règles de l'inscription par email (ADR-055), vérifiées par le service et la validation des requêtes. L'app iOS
// applique les mêmes (`RegistrationRules.swift`) : les garder alignées.

// Mot de passe : 8 à 128 caractères, au moins une lettre et un chiffre. Seulement à l'inscription : la connexion ne
// vérifie aucun format, et les comptes créés avant ces règles gardent leur mot de passe.
export const MIN_PASSWORD_LENGTH = 8;
export const MAX_PASSWORD_LENGTH = 128;
export const PASSWORD_PATTERN = /^(?=.*\p{L})(?=.*\p{Nd})/u;

// Âge minimum pour créer un compte, comme sur TikTok.
export const MIN_SIGNUP_AGE = 13;
// Date de naissance au format `AAAA-MM-JJ` (jour du calendrier, sans fuseau).
export const BIRTH_DATE_PATTERN = /^\d{4}-\d{2}-\d{2}$/;
const MIN_BIRTH_YEAR = 1900;

export function isValidPassword(password: string): boolean {
  return password.length >= MIN_PASSWORD_LENGTH && password.length <= MAX_PASSWORD_LENGTH && PASSWORD_PATTERN.test(password);
}

// Date de naissance lue en minuit UTC, ou null si elle n'existe pas (« 2023-02-30 ») ou sort des bornes
// (avant 1900, ou après aujourd'hui).
export function parseBirthDate(value: string, now: Date): Date | null {
  if (!BIRTH_DATE_PATTERN.test(value)) return null;
  const [year, month, day] = value.split('-').map(Number);
  const date = new Date(Date.UTC(year, month - 1, day));
  if (date.getUTCFullYear() !== year || date.getUTCMonth() !== month - 1 || date.getUTCDate() !== day) return null;
  if (year < MIN_BIRTH_YEAR || date.getTime() > now.getTime()) return null;
  return date;
}

// Âge en années révolues à la date du jour (UTC). Né un 29 février : un an de plus le 1er mars des années non
// bissextiles.
export function ageOn(birthDate: Date, now: Date): number {
  let age = now.getUTCFullYear() - birthDate.getUTCFullYear();
  const beforeBirthday =
    now.getUTCMonth() < birthDate.getUTCMonth() || (now.getUTCMonth() === birthDate.getUTCMonth() && now.getUTCDate() < birthDate.getUTCDate());
  if (beforeBirthday) age -= 1;
  return age;
}
