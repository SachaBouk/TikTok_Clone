import { randomBytes, scrypt, timingSafeEqual, type ScryptOptions } from 'node:crypto';
import { PasswordHasher } from '../domain/password-hasher';

// scrypt intégré à Node : aucune dépendance native. Paramètres au-dessus du minimum OWASP
// (N = 2^16, r = 8, p = 1 : 64 Mio par calcul). Ils sont stockés dans le hash, donc modifiables sans migration.
// Format : scrypt$N$r$p$<sel base64>$<hash base64>
const PARAMS = { N: 2 ** 16, r: 8, p: 1 };
const KEY_LENGTH = 64;
const SALT_LENGTH = 16;

export class ScryptPasswordHasher extends PasswordHasher {
  // Hash factice, calculé une fois, pour les vérifications sans compte (voir PasswordHasher.verify).
  private readonly dummyHash = this.hash('mot-de-passe-factice');

  async hash(password: string): Promise<string> {
    const salt = randomBytes(SALT_LENGTH);
    const key = await derive(password, salt, KEY_LENGTH, PARAMS);
    return ['scrypt', PARAMS.N, PARAMS.r, PARAMS.p, salt.toString('base64'), key.toString('base64')].join('$');
  }

  async verify(password: string, hash: string | null): Promise<boolean> {
    const stored = hash ?? (await this.dummyHash);
    const [algorithm, N, r, p, salt, key] = stored.split('$');
    if (algorithm !== 'scrypt' || !salt || !key) return false;

    const expected = Buffer.from(key, 'base64');
    const actual = await derive(password, Buffer.from(salt, 'base64'), expected.length, {
      N: Number(N),
      r: Number(r),
      p: Number(p),
    });
    return timingSafeEqual(actual, expected) && hash !== null;
  }
}

function derive(password: string, salt: Buffer, keyLength: number, params: { N: number; r: number; p: number }): Promise<Buffer> {
  // `maxmem` doit dépasser 128 * N * r octets, sinon Node refuse le calcul.
  const options: ScryptOptions = { ...params, maxmem: 256 * params.N * params.r };
  return new Promise((resolve, reject) => {
    scrypt(password.normalize('NFKC'), salt, keyLength, options, (error, key) => (error ? reject(error) : resolve(key)));
  });
}
