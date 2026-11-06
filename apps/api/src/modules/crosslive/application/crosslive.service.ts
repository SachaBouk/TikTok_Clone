import {
  CrossLiveUnavailableError,
  ParticipantAccounts,
  ParticipantNotFoundError,
  ParticipantTokenSigner,
  participantClaims,
} from '../domain/participant-token';

// Live commun d'echimine (ADR-079) : l'API ne fait que signer le Jeton de Participant du compte connecté ; salles,
// chat, réactions et modération sont au serveur commun.
export class CrossLiveService {
  constructor(
    private readonly accounts: ParticipantAccounts,
    private readonly signer: ParticipantTokenSigner,
  ) {}

  async participantToken(userId: string): Promise<string> {
    if (!this.signer.available) throw new CrossLiveUnavailableError();
    const account = await this.accounts.find(userId);
    if (!account) throw new ParticipantNotFoundError();
    return this.signer.sign(participantClaims(account));
  }
}
