import type { RealtimeMessage } from '../domain/realtime';
import { RealtimeBus } from '../domain/realtime-bus';

// Bus en mémoire pour les tests : remet chaque message, dans l'ordre, à tous les abonnés (une seule instance).
export class InMemoryRealtimeBus extends RealtimeBus {
  readonly published: RealtimeMessage[] = [];
  private readonly handlers = new Set<(message: RealtimeMessage) => void>();

  async publish(message: RealtimeMessage): Promise<void> {
    this.published.push(message);
    for (const handler of this.handlers) handler(message);
  }

  async subscribe(handler: (message: RealtimeMessage) => void): Promise<() => Promise<void>> {
    this.handlers.add(handler);
    return async () => {
      this.handlers.delete(handler);
    };
  }
}
