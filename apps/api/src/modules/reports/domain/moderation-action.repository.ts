import type { ModerationAction, NewModerationAction } from './report';

// Port du journal de modération (table moderation_actions, ADR-038).
export abstract class ModerationActionRepository {
  abstract add(action: NewModerationAction): Promise<void>;
  // Du plus récent au plus ancien, strictement avant `beforeId` (UUID v7) ; `targetUserId` : actions sur ce compte.
  abstract list(filter: { targetUserId?: string }, beforeId: string | null, limit: number): Promise<ModerationAction[]>;
}
