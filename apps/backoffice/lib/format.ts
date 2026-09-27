// Mise en forme française des dates et des nombres (heure de Paris, quel que soit le serveur).
const dateTime = new Intl.DateTimeFormat('fr-FR', { dateStyle: 'medium', timeStyle: 'short', timeZone: 'Europe/Paris' });
const number = new Intl.NumberFormat('fr-FR');

export function formatDateTime(iso: string): string {
  return dateTime.format(new Date(iso));
}

export function formatNumber(value: number): string {
  return number.format(value);
}

// Lien vers la même liste avec d'autres paramètres ; un paramètre vide ou nul est retiré.
export function withQuery(path: string, params: Record<string, string | null | undefined>): string {
  const query = new URLSearchParams();
  for (const [name, value] of Object.entries(params)) if (value) query.set(name, value);
  const search = query.toString();
  return search ? `${path}?${search}` : path;
}
