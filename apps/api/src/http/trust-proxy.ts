// Réglage `trust proxy` d'Express, depuis TRUST_PROXY (facultatif) : l'adresse IP du client (`req.ip`) sert aux
// limites de débit (ADR-030). Derrière un répartiteur de charge ou un proxy, sans ce réglage, toutes les requêtes
// sembleraient venir du proxy ; avec un réglage trop large, un client pourrait choisir son IP (X-Forwarded-For).
// Valeurs : absent ou `false` (défaut, pas de proxy), un nombre de proxys devant l'API (`1`), `true` (tous, à
// éviter), ou une liste d'adresses ou de sous-réseaux de confiance, comme l'accepte Express (`loopback, 10.0.0.0/8`).
export function parseTrustProxy(value: string | undefined): boolean | number | string {
  const trimmed = value?.trim() ?? '';
  if (trimmed === '' || trimmed === 'false') return false;
  if (trimmed === 'true') return true;
  if (/^\d+$/.test(trimmed)) return Number(trimmed);
  return trimmed;
}
