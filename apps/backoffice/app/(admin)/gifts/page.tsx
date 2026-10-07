import type { Metadata } from 'next';
import { FilterChip } from '@/components/filter-chip';
import { GiftsTable } from '@/components/gifts-table';
import { Pagination } from '@/components/pagination';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { formatNumber, withQuery } from '@/lib/format';
import { listGifts } from '@/models/gifts.model';
import { getStats } from '@/models/stats.model';
import { getUser } from '@/models/users.model';

export const metadata: Metadata = { title: 'Cadeaux' };

// Cadeaux en jetons (ADR-050) : jetons dépensés par les expéditeurs, gains des créateurs (non dépensables, sans
// retrait), et journal de chaque cadeau. Lecture seule, comme le portefeuille (ADR-032).
export default async function GiftsPage({ searchParams }: { searchParams: Promise<{ userId?: string; curseur?: string }> }) {
  const { userId, curseur } = await searchParams;
  const [stats, page, account] = await Promise.all([getStats(), listGifts({ userId, cursor: curseur }), userId ? getUser(userId) : null]);
  const { tokens } = stats;
  const figures = [
    { label: 'Jetons dépensés', value: tokens.giftsSpent, detail: `+${formatNumber(tokens.giftsSpentLast7Days)} sur 7 jours` },
    { label: 'Gains des créateurs', value: tokens.earned, detail: 'Comptes existants, non dépensables' },
    { label: 'En circulation', value: tokens.inCirculation, detail: 'Somme des soldes dépensables' },
  ];

  return (
    <div className="flex flex-col gap-6">
      <h1 className="text-2xl font-semibold">Cadeaux</h1>

      <div className="grid gap-4 sm:grid-cols-3">
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

      <div className="flex flex-col gap-4">
        <h2 className="text-lg font-semibold">Journal</h2>
        {userId && (
          <div className="flex gap-2">
            <FilterChip label={account ? `Compte : @${account.username}` : 'Un compte'} clearHref="/gifts" />
          </div>
        )}
        <GiftsTable gifts={page.items} />
        <Pagination
          onFirstPage={!curseur}
          firstHref={withQuery('/gifts', { userId })}
          nextHref={page.nextCursor ? withQuery('/gifts', { userId, curseur: page.nextCursor }) : null}
        />
      </div>
    </div>
  );
}
