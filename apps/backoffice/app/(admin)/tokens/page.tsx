import type { Metadata } from 'next';
import Link from 'next/link';
import { FilterChip } from '@/components/filter-chip';
import { Pagination } from '@/components/pagination';
import { WalletTransactionsTable } from '@/components/wallet-transactions-table';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { formatNumber, withQuery } from '@/lib/format';
import { getStats } from '@/models/stats.model';
import { getUser } from '@/models/users.model';
import { listWalletTransactions } from '@/models/wallet.model';

export const metadata: Metadata = { title: 'Jetons' };

// Jetons (ADR-009) : totaux annoncés par RevenueCat, et journal des mouvements appliqués aux soldes. Les achats
// de test (sandbox) sont comptés à part : ils ne sont jamais payés.
export default async function TokensPage({ searchParams }: { searchParams: Promise<{ userId?: string; rapprocher?: string; curseur?: string }> }) {
  const { userId, rapprocher, curseur } = await searchParams;
  const unmatched = rapprocher === '1';
  const [stats, page, account] = await Promise.all([
    getStats(),
    listWalletTransactions({ userId, unmatched, cursor: curseur }),
    userId ? getUser(userId) : null,
  ]);
  const { tokens } = stats;
  const figures = [
    { label: 'Vendus', value: tokens.production.purchased, detail: `+${formatNumber(tokens.purchasedLast7Days)} sur 7 jours` },
    { label: 'Remboursés', value: tokens.production.refunded, detail: 'Annoncés par le store' },
    { label: 'Ajustés', value: tokens.production.adjusted, detail: 'Tableau de bord RevenueCat' },
    { label: 'En circulation', value: tokens.inCirculation, detail: 'Somme des soldes' },
  ];

  return (
    <div className="flex flex-col gap-6">
      <h1 className="text-2xl font-semibold">Jetons</h1>

      <div className="grid gap-4 sm:grid-cols-4">
        {figures.map(({ label, value, detail }) => (
          <Card key={label}>
            <CardHeader>
              <CardDescription>{label}</CardDescription>
              <CardTitle className="text-3xl tabular-nums">{formatNumber(value)}</CardTitle>
            </CardHeader>
            <CardContent className="text-sm text-muted-foreground">{detail}</CardContent>
          </Card>
        ))}
      </div>
      <p className="text-sm text-muted-foreground">
        Production seulement. Achats de test (Xcode, TestFlight, Test Store) : {formatNumber(tokens.sandbox.purchased)} vendus,{' '}
        {formatNumber(tokens.sandbox.refunded)} remboursés, {formatNumber(tokens.sandbox.adjusted)} ajustés.
      </p>

      <div className="flex flex-col gap-4">
        <div className="flex flex-wrap items-center justify-between gap-2">
          <h2 className="text-lg font-semibold">Journal</h2>
          {!unmatched && !userId && tokens.unmatched > 0 && (
            <Button variant="outline" size="sm" asChild>
              <Link href="/tokens?rapprocher=1">{formatNumber(tokens.unmatched)} à rapprocher</Link>
            </Button>
          )}
        </div>
        {(unmatched || userId) && (
          <div className="flex gap-2">
            {userId && (
              <FilterChip label={account ? `Compte : @${account.username}` : 'Un compte'} clearHref={withQuery('/tokens', { rapprocher })} />
            )}
            {unmatched && <FilterChip label="À rapprocher" clearHref={withQuery('/tokens', { userId })} />}
          </div>
        )}
        {unmatched && (
          <p className="text-sm text-muted-foreground">
            Clients RevenueCat inconnus de l’API au moment de l’achat (identifiant anonyme, compte supprimé avant le webhook) : aucun solde n’a été
            crédité. Retrouver le client dans RevenueCat par son identifiant, puis créditer le compte par un ajustement.
          </p>
        )}
        <WalletTransactionsTable transactions={page.items} />
        <Pagination
          onFirstPage={!curseur}
          firstHref={withQuery('/tokens', { userId, rapprocher })}
          nextHref={page.nextCursor ? withQuery('/tokens', { userId, rapprocher, curseur: page.nextCursor }) : null}
        />
      </div>
    </div>
  );
}
