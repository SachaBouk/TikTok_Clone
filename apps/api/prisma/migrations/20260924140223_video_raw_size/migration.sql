/*
  Warnings:

  - Added the required column `raw_size` to the `videos` table without a default value. This is not possible if the table is not empty.

*/
-- AlterTable
ALTER TABLE "videos" ADD COLUMN     "raw_size" INTEGER NOT NULL;
