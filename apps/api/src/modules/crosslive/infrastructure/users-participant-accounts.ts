import { Injectable } from '@nestjs/common';
import { UsersService } from '../../users/application/users.service';
import { ParticipantAccounts, type ParticipantAccount } from '../domain/participant-token';

// Comptes du Live commun, lus par le service exporté du module `users` (ADR-003).
@Injectable()
export class UsersParticipantAccounts extends ParticipantAccounts {
  constructor(private readonly users: UsersService) {
    super();
  }

  async find(userId: string): Promise<ParticipantAccount | null> {
    const [user] = await this.users.getByIds([userId]);
    return user ? { id: user.id, username: user.username, avatarUrl: user.avatarUrl } : null;
  }
}
