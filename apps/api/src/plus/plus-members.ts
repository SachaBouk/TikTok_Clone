// Registre des abonnés « Plus » (ADR-073), lu par les modules qui donnent les avantages (users : badge ; videos et live :
// durées ; wallet : cadeaux exclusifs). Port sans dépendance à NestJS ni à Redis, comme le registre des comptes
// suspendus (ADR-037) : les couches domain/ et application/ des modules peuvent l'importer (ADR-003), sans dépendre du
// module `subscriptions` (users → videos : videos ne pourrait pas dépendre d'un module qui dépend de users).
// La base reste la source de vérité (table `plus_subscriptions`, propriété du module subscriptions) ; le registre garde
// l'échéance de chaque abonné, écrite à chaque changement et reconstruite au démarrage de l'API.
// Lecture impossible (Redis indisponible) : personne n'est vu comme abonné, et c'est journalisé.
export abstract class PlusMembers {
  // Échéance de l'abonnement, ou null (jamais abonné, ou échéance inconnue du registre).
  abstract expiryOf(userId: string): Promise<Date | null>;
  // Échéance de chaque compte demandé qui en a une (passée ou non).
  abstract expiriesOf(userIds: string[]): Promise<Map<string, Date>>;
  // Écritures : une erreur est propagée. `null` retire le compte.
  abstract set(userId: string, expiresAt: Date | null): Promise<void>;
  abstract replaceAll(entries: { userId: string; expiresAt: Date }[]): Promise<void>;

  // Abonné = échéance dans le futur.
  async isActive(userId: string, now: Date = new Date()): Promise<boolean> {
    const expiresAt = await this.expiryOf(userId);
    return expiresAt !== null && expiresAt > now;
  }

  async activeAmong(userIds: string[], now: Date = new Date()): Promise<Set<string>> {
    if (userIds.length === 0) return new Set();
    const expiries = await this.expiriesOf([...new Set(userIds)]);
    return new Set([...expiries].filter(([, expiresAt]) => expiresAt > now).map(([userId]) => userId));
  }
}
