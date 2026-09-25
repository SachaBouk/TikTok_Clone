// Port : contenus d'un compte stockés hors de ce module (fichiers de ses vidéos), à nettoyer quand le
// compte est supprimé. La cascade de la base supprime les lignes, pas les fichiers du stockage objet.
// Appelé avant la suppression en base : si la programmation échoue, le compte reste intact.
export abstract class AccountContentCleanup {
  abstract scheduleCleanup(userId: string): Promise<void>;
}
