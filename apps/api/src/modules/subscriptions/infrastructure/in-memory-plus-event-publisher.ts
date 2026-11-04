import { PlusEventPublisher } from '../domain/plus-events';
import type { PlusStatus } from '../domain/plus-subscription';

export class InMemoryPlusEventPublisher extends PlusEventPublisher {
  readonly published: { userId: string; status: PlusStatus }[] = [];

  async plusChanged(userId: string, status: PlusStatus): Promise<void> {
    this.published.push({ userId, status });
  }
}
