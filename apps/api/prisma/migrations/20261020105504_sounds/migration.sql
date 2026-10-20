-- AlterTable
ALTER TABLE "videos" ADD COLUMN     "sound_id" UUID,
ADD COLUMN     "sound_shared" BOOLEAN NOT NULL DEFAULT true;

-- CreateTable
CREATE TABLE "sounds" (
    "sound_id" UUID NOT NULL,
    "video_id" UUID NOT NULL,
    "user_id" UUID NOT NULL,
    "audio_url" TEXT NOT NULL,
    "duration_ms" INTEGER NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "sounds_pkey" PRIMARY KEY ("sound_id")
);

-- CreateTable
CREATE TABLE "sound_favorites" (
    "user_id" UUID NOT NULL,
    "sound_id" UUID NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "sound_favorites_pkey" PRIMARY KEY ("user_id","sound_id")
);

-- CreateIndex
CREATE UNIQUE INDEX "sounds_video_id_key" ON "sounds"("video_id");

-- CreateIndex
CREATE INDEX "sound_favorites_user_id_created_at_idx" ON "sound_favorites"("user_id", "created_at");

-- CreateIndex
CREATE INDEX "videos_sound_id_idx" ON "videos"("sound_id");

-- AddForeignKey
ALTER TABLE "videos" ADD CONSTRAINT "videos_sound_id_fkey" FOREIGN KEY ("sound_id") REFERENCES "sounds"("sound_id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "sounds" ADD CONSTRAINT "sounds_video_id_fkey" FOREIGN KEY ("video_id") REFERENCES "videos"("video_id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "sounds" ADD CONSTRAINT "sounds_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("user_id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "sound_favorites" ADD CONSTRAINT "sound_favorites_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("user_id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "sound_favorites" ADD CONSTRAINT "sound_favorites_sound_id_fkey" FOREIGN KEY ("sound_id") REFERENCES "sounds"("sound_id") ON DELETE CASCADE ON UPDATE CASCADE;


-- Écrit à la main (ADR-064) : durée du son positive.
ALTER TABLE "sounds" ADD CONSTRAINT "sounds_duration_positive" CHECK ("duration_ms" > 0);
