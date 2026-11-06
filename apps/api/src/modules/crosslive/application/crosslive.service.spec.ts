import { describe, expect, it } from 'vitest';
import {
  CrossLiveUnavailableError,
  ParticipantAccounts,
  ParticipantNotFoundError,
  participantName,
  type ParticipantAccount,
} from '../domain/participant-token';
import { InMemoryParticipantTokenSigner } from '../infrastructure/in-memory-participant-token-signer';
import { CrossLiveService } from './crosslive.service';

class FakeAccounts extends ParticipantAccounts {
  constructor(private readonly accounts: ParticipantAccount[]) {
    super();
  }
  async find(userId: string): Promise<ParticipantAccount | null> {
    return this.accounts.find((account) => account.id === userId) ?? null;
  }
}

const lea: ParticipantAccount = { id: 'u-1', username: 'lea.martin', avatarUrl: 'https://cdn.example.com/a.jpg' };
const hugo: ParticipantAccount = { id: 'u-2', username: 'hugo', avatarUrl: 'http://localhost:9000/avatars/u-2/x' };

describe('CrossLiveService', () => {
  it('signe les claims du compte connecté, photo https comprise', async () => {
    const signer = new InMemoryParticipantTokenSigner();
    const service = new CrossLiveService(new FakeAccounts([lea]), signer);

    await expect(service.participantToken('u-1')).resolves.toBe('token-1');
    expect(signer.signed).toEqual([{ sub: 'u-1', name: 'lea.martin', picture: 'https://cdn.example.com/a.jpg' }]);
  });

  it('omet une photo qui n’est pas en https', async () => {
    const signer = new InMemoryParticipantTokenSigner();
    await new CrossLiveService(new FakeAccounts([hugo]), signer).participantToken('u-2');

    expect(signer.signed[0]).toEqual({ sub: 'u-2', name: 'hugo' });
  });

  it('refuse sans secret configuré', async () => {
    const service = new CrossLiveService(new FakeAccounts([lea]), new InMemoryParticipantTokenSigner(false));

    await expect(service.participantToken('u-1')).rejects.toBeInstanceOf(CrossLiveUnavailableError);
  });

  it('refuse un compte introuvable', async () => {
    const service = new CrossLiveService(new FakeAccounts([]), new InMemoryParticipantTokenSigner());

    await expect(service.participantToken('u-9')).rejects.toBeInstanceOf(ParticipantNotFoundError);
  });

  it('tronque le pseudo à 30 caractères visibles sans couper un emoji', () => {
    expect(participantName('a'.repeat(40))).toHaveLength(30);
    expect(participantName(`${'b'.repeat(29)}👩‍👩‍👧‍👦c`)).toBe(`${'b'.repeat(29)}👩‍👩‍👧‍👦`);
  });
});
