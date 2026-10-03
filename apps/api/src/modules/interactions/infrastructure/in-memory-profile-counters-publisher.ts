import { type ProfileCounters, ProfileCountersPublisher } from '../domain/profile-counters-publisher';

// Adaptateur en mémoire pour les tests : garde les compteurs publiés.
export class InMemoryProfileCountersPublisher extends ProfileCountersPublisher {
  readonly published: ProfileCounters[] = [];

  async countersChanged(counters: ProfileCounters): Promise<void> {
    this.published.push(counters);
  }
}
