-- Cadeaux en jetons (ADR-050). gifts_sent n'a jamais été écrite : ses colonnes obligatoires s'ajoutent sans valeur
-- par défaut.

-- DropIndex
DROP INDEX "gifts_sent_recipient_id_created_at_idx";

-- DropIndex
DROP INDEX "gifts_sent_sender_id_created_at_idx";

-- AlterTable
ALTER TABLE "gifts_sent" ADD COLUMN     "client_gift_id" UUID NOT NULL,
ADD COLUMN     "gift_code" TEXT NOT NULL,
ADD COLUMN     "sender_balance_after" INTEGER NOT NULL,
ADD COLUMN     "video_id" UUID;

-- AlterTable
ALTER TABLE "notifications" ADD COLUMN     "gift_amount" INTEGER,
ADD COLUMN     "gift_code" TEXT;

-- AlterTable
ALTER TABLE "wallets" ADD COLUMN     "earned" INTEGER NOT NULL DEFAULT 0;

-- CreateIndex
CREATE INDEX "gifts_sent_sender_id_gift_id_idx" ON "gifts_sent"("sender_id", "gift_id");

-- CreateIndex
CREATE INDEX "gifts_sent_recipient_id_gift_id_idx" ON "gifts_sent"("recipient_id", "gift_id");

-- CreateIndex
CREATE UNIQUE INDEX "gifts_sent_sender_id_client_gift_id_key" ON "gifts_sent"("sender_id", "client_gift_id");

-- AddForeignKey
ALTER TABLE "gifts_sent" ADD CONSTRAINT "gifts_sent_video_id_fkey" FOREIGN KEY ("video_id") REFERENCES "videos"("video_id") ON DELETE SET NULL ON UPDATE CASCADE;


-- ─── Écrit à la main (Prisma ne voit pas les CHECK) ───

-- Gains : jamais négatifs.
ALTER TABLE "wallets" ADD CONSTRAINT "wallets_earned_positive" CHECK ("earned" >= 0);

-- Cadeau : code du catalogue, solde de l'expéditeur jamais négatif, jamais à soi-même.
ALTER TABLE "gifts_sent" ADD CONSTRAINT "gifts_sent_code_not_empty" CHECK ("gift_code" <> '');
ALTER TABLE "gifts_sent" ADD CONSTRAINT "gifts_sent_balance_positive" CHECK ("sender_balance_after" >= 0);
ALTER TABLE "gifts_sent" ADD CONSTRAINT "gifts_sent_not_self" CHECK ("sender_id" <> "recipient_id");

-- Notification de cadeau : code et prix, seulement pour ce type. Auteur et vidéo sont exigés par
-- notifications_target_by_type (branche par défaut, comme un like).
ALTER TABLE "notifications" ADD CONSTRAINT "notifications_gift_columns" CHECK (
  CASE "type"
    WHEN 'gift' THEN "gift_code" IS NOT NULL AND "gift_amount" > 0
    ELSE "gift_code" IS NULL AND "gift_amount" IS NULL
  END
);
