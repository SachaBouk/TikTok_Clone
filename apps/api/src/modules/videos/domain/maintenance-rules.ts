// Maintenance planifiée du module videos (ADR-007, ADR-012).

// Un upload non confirmé après 24 h est abandonné : l'upload multipart est annulé et la vidéo supprimée.
// Largement au-delà de la validité des URLs signées (2 h) : l'app ne peut plus le terminer.
export const ABANDONED_UPLOAD_AFTER_MS = 24 * 60 * 60 * 1000;

// Une vidéo en `processing` sans changement depuis 1 h est remise dans la file de transcodage,
// au cas où son job aurait été perdu. Sans effet si le job existe encore (jobId = videoId).
export const STUCK_TRANSCODE_AFTER_MS = 60 * 60 * 1000;

// Nombre maximal de vidéos traitées par passage, pour borner la durée de chaque exécution.
export const MAINTENANCE_BATCH_SIZE = 100;

// Vidéo Mux (ADR-074) en `processing` depuis 15 min : son état est relu chez Mux (webhook perdu, tunnel coupé).
export const STUCK_HOSTED_VIDEO_AFTER_MS = 15 * 60 * 1000;

// Confirmation d'un envoi direct chez Mux : attentes successives (ms) avant que Mux ait créé l'asset.
export const HOSTED_ASSET_WAIT_MS = [300, 700, 1500];
