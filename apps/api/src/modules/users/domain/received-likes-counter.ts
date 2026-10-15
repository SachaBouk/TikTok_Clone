// Port : likes reçus par un compte sur ses vidéos publiées, compteur « J'aime » de son profil (ADR-056).
// Les vidéos appartiennent au module videos : ce module ne les lit pas lui-même (ADR-003).
export abstract class ReceivedLikesCounter {
  abstract countFor(userId: string): Promise<number>;
}
