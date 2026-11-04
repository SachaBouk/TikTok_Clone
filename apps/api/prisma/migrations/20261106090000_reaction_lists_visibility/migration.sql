-- Visibilité des vidéos aimées et des favoris (ADR-071) : privées par défaut, y compris pour les comptes existants.
ALTER TABLE "users" ADD COLUMN     "favorites_visibility" "video_visibility" NOT NULL DEFAULT 'private',
ADD COLUMN     "likes_visibility" "video_visibility" NOT NULL DEFAULT 'private';
