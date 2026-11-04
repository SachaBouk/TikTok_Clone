-- Abonnement « Plus » (ADR-073) : jetons offerts par l'abonnement, dans le journal des jetons. Valeur ajoutée dans sa
-- propre migration, avant tout usage (PostgreSQL ne permet pas d'utiliser une valeur ajoutée dans la même transaction).
ALTER TYPE "wallet_transaction_kind" ADD VALUE 'subscription_grant';
