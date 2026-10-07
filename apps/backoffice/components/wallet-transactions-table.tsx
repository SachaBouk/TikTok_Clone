import Link from 'next/link';
import type { AdminWalletTransactionDto, WalletTransactionKind } from '@repo/shared';
import { UserAvatar } from '@/components/user-avatar';
import { Badge } from '@/components/ui/badge';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { formatDateTime, formatNumber, formatSigned } from '@/lib/format';

const KIND_LABELS: Record<WalletTransactionKind, string> = {
  purchase: 'Achat',
  refund: 'Remboursement',
  adjustment: 'Ajustement',
  // Jamais dans le journal RevenueCat : les cadeaux ont leur propre journal (page « Cadeaux », ADR-050).
  giftSent: 'Cadeau envoyé',
};

// Journal des jetons (page « Jetons » et fiche d'un compte). Le montant appliqué n'est affiché à part que s'il
// diffère du montant annoncé par RevenueCat (remboursement plafonné au solde, client inconnu).
export function WalletTransactionsTable({ transactions, showAccount = true }: { transactions: AdminWalletTransactionDto[]; showAccount?: boolean }) {
  return (
    <Table>
      <TableHeader>
        <TableRow>
          <TableHead>Date</TableHead>
          {showAccount && <TableHead>Compte</TableHead>}
          <TableHead>Mouvement</TableHead>
          <TableHead className="text-right">Jetons</TableHead>
          <TableHead className="text-right">Solde après</TableHead>
          <TableHead>Store</TableHead>
          <TableHead>Événement RevenueCat</TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        {transactions.map((transaction) => (
          <TableRow key={transaction.id}>
            <TableCell className="text-muted-foreground">{formatDateTime(transaction.occurredAt)}</TableCell>
            {showAccount && (
              <TableCell>
                {transaction.user ? (
                  <Link href={`/users/${transaction.user.id}`} className="flex items-center gap-2">
                    <UserAvatar user={transaction.user} size="sm" />
                    <span>@{transaction.user.username}</span>
                  </Link>
                ) : transaction.unmatched ? (
                  <span className="flex flex-col gap-1">
                    <Badge variant="destructive">À rapprocher</Badge>
                    <code className="text-xs text-muted-foreground">{transaction.appUserId}</code>
                  </span>
                ) : (
                  <span className="text-muted-foreground">Compte supprimé</span>
                )}
              </TableCell>
            )}
            <TableCell>
              <span className="flex flex-wrap items-center gap-2">
                {KIND_LABELS[transaction.kind]}
                {transaction.environment !== 'PRODUCTION' && <Badge variant="outline">Test</Badge>}
              </span>
              {transaction.productId && <span className="text-xs text-muted-foreground">{transaction.productId}</span>}
            </TableCell>
            <TableCell className="text-right tabular-nums">
              <span className={transaction.amount < 0 ? 'text-destructive' : undefined}>{formatSigned(transaction.amount)}</span>
              {transaction.appliedAmount !== transaction.amount && (
                <span className="block text-xs text-muted-foreground">appliqué : {formatSigned(transaction.appliedAmount)}</span>
              )}
            </TableCell>
            <TableCell className="text-right tabular-nums">
              {transaction.balanceAfter === null ? '—' : formatNumber(transaction.balanceAfter)}
            </TableCell>
            <TableCell>
              <span className="block text-sm">{transaction.store ?? '—'}</span>
              {transaction.storeTransactionId && <code className="text-xs text-muted-foreground">{transaction.storeTransactionId}</code>}
            </TableCell>
            <TableCell>
              <code className="text-xs text-muted-foreground">{transaction.revenuecatEventId}</code>
            </TableCell>
          </TableRow>
        ))}
        {transactions.length === 0 && (
          <TableRow>
            <TableCell colSpan={showAccount ? 7 : 6} className="py-8 text-center text-muted-foreground">
              Aucun mouvement.
            </TableCell>
          </TableRow>
        )}
      </TableBody>
    </Table>
  );
}
