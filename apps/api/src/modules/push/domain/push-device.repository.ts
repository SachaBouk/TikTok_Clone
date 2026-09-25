import type { PushDevice } from './push';

// Port de la table push_devices.
export abstract class PushDeviceRepository {
  // Un token passe au dernier compte connecté sur l'appareil.
  abstract register(device: PushDevice): Promise<void>;
  // Seulement si le token appartient à ce compte (déconnexion).
  abstract unregister(userId: string, token: string): Promise<void>;
  abstract findByUser(userId: string): Promise<PushDevice[]>;
  abstract remove(token: string): Promise<void>;
}
