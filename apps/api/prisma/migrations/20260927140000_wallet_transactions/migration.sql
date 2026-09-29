-- Journal des mouvements du solde de jetons (ADR-009), alimenté par les webhooks RevenueCat.
-- CreateEnum
CREATE TYPE "wallet_transaction_kind" AS ENUM ('purchase', 'refund', 'adjustment');

-- CreateTable
CREATE TABLE "wallet_transactions" (
    "wallet_transaction_id" UUID NOT NULL,
    "user_id" UUID,
    "kind" "wallet_transaction_kind" NOT NULL,
    "amount" INTEGER NOT NULL,
    "applied_amount" INTEGER NOT NULL,
    "balance_after" INTEGER,
    "revenuecat_event_id" TEXT NOT NULL,
    "app_user_id" TEXT NOT NULL,
    "product_id" TEXT,
    "store_transaction_id" TEXT,
    "store" TEXT,
    "environment" TEXT NOT NULL,
    "occurred_at" TIMESTAMP(3) NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "wallet_transactions_pkey" PRIMARY KEY ("wallet_transaction_id")
);

-- CreateIndex
CREATE UNIQUE INDEX "wallet_transactions_revenuecat_event_id_key" ON "wallet_transactions"("revenuecat_event_id");

-- CreateIndex
CREATE INDEX "wallet_transactions_user_id_wallet_transaction_id_idx" ON "wallet_transactions"("user_id", "wallet_transaction_id");

-- AddForeignKey
ALTER TABLE "wallet_transactions" ADD CONSTRAINT "wallet_transactions_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("user_id") ON DELETE SET NULL ON UPDATE CASCADE;


-- Contraintes écrites à la main (Prisma ne sait pas les exprimer) : un mouvement n'est jamais nul, le solde
-- après un mouvement n'est jamais négatif, et le mouvement appliqué va dans le sens annoncé sans le dépasser.
ALTER TABLE "wallet_transactions" ADD CONSTRAINT "wallet_transactions_amount_not_zero" CHECK ("amount" <> 0);
ALTER TABLE "wallet_transactions" ADD CONSTRAINT "wallet_transactions_balance_non_negative" CHECK ("balance_after" >= 0);
ALTER TABLE "wallet_transactions" ADD CONSTRAINT "wallet_transactions_applied_within_amount"
  CHECK (("amount" > 0 AND "applied_amount" BETWEEN 0 AND "amount") OR ("amount" < 0 AND "applied_amount" BETWEEN "amount" AND 0));
