import { randomUUID } from 'node:crypto';
import { ModerationActionRepository } from '../domain/moderation-action.repository';
import type { ModerationAction, NewModerationAction } from '../domain/report';

// Adaptateur en mémoire pour les tests : identifiants croissants (comme les UUID v7).
export class InMemoryModerationActionRepository extends ModerationActionRepository {
  readonly actions: ModerationAction[] = [];
  private sequence = 0;

  constructor(private readonly now: () => Date = () => new Date()) {
    super();
  }

  async add(action: NewModerationAction): Promise<void> {
    this.actions.push({ ...action, id: `${String(++this.sequence).padStart(8, '0')}-${randomUUID().slice(9)}`, createdAt: this.now() });
  }

  async list(filter: { targetUserId?: string }, beforeId: string | null, limit: number): Promise<ModerationAction[]> {
    return [...this.actions]
      .sort((a, b) => (a.id < b.id ? 1 : -1))
      .filter((a) => (!filter.targetUserId || a.targetUserId === filter.targetUserId) && (!beforeId || a.id < beforeId))
      .slice(0, limit);
  }
}
