import { describe, expect, it } from 'vitest';
import { ScryptPasswordHasher } from './scrypt-password-hasher';

describe('ScryptPasswordHasher', () => {
  const hasher = new ScryptPasswordHasher();

  it('vérifie le bon mot de passe et refuse un mauvais', async () => {
    const hash = await hasher.hash('motdepasse');
    expect(hash).toMatch(/^scrypt\$65536\$8\$1\$/);
    await expect(hasher.verify('motdepasse', hash)).resolves.toBe(true);
    await expect(hasher.verify('Motdepasse', hash)).resolves.toBe(false);
  });

  it('sale chaque hash : deux hash du même mot de passe diffèrent', async () => {
    expect(await hasher.hash('motdepasse')).not.toBe(await hasher.hash('motdepasse'));
  });

  it('renvoie false sans hash (compte inconnu), même pour le mot de passe factice interne', async () => {
    await expect(hasher.verify('mot-de-passe-factice', null)).resolves.toBe(false);
  });

  it('renvoie false pour un hash mal formé', async () => {
    await expect(hasher.verify('motdepasse', 'pas-un-hash')).resolves.toBe(false);
  });
});
