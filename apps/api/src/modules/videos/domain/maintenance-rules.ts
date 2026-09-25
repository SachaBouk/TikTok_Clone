// Maintenance planifiée du module videos (ADR-007, ADR-012).

// Un upload non confirmé après 24 h est abandonné : l'upload multipart est annulé et la vidéo supprimée.
// Largement au-delà de la validité des URLs signées (2 h) : l'app ne peut plus le terminer.
export const ABANDONED_UPLOAD_AFTER_MS = 24 * 60 * 60 * 1000;

// Une vidéo en `processing` sans changement depuis 1 h est remise dans la file de transcodage,
// au cas où son job aurait été perdu. Sans effet si le job existe encore (jobId = videoId).
export const STUCK_TRANSCODE_AFTER_MS = 60 * 60 * 1000;

// Nombre maximal de vidéos traitées par passage, pour borner la durée de chaque exécution.
export const MAINTENANCE_BATCH_SIZE = 100;
