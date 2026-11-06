import { ParticipantTokenSigner, type ParticipantClaims } from '../domain/participant-token';

// Signataire des tests du service : garde les claims reçues.
export class InMemoryParticipantTokenSigner extends ParticipantTokenSigner {
  readonly signed: ParticipantClaims[] = [];

  constructor(readonly available = true) {
    super();
  }

  async sign(claims: ParticipantClaims): Promise<string> {
    this.signed.push(claims);
    return `token-${this.signed.length}`;
  }
}
