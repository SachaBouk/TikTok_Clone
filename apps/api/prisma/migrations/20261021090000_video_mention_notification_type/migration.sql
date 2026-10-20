-- Valeur d'enum dans sa propre migration, avant son premier usage (ADR-065).
ALTER TYPE "notification_type" ADD VALUE 'video_mention';
