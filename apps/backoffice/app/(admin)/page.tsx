import type { Metadata } from 'next';
import Link from 'next/link';
import { ExternalLinkIcon } from 'lucide-react';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { VIDEO_STATUS_LABELS } from '@/components/video-status-badge';
import { POSTHOG_PROJECT_URL } from '@/lib/config';
import { formatNumber } from '@/lib/format';
import { getStats } from '@/models/stats.model';

export const metadata: Metadata = { title: 'Tableau de bord' };

// Liens vers PostHog (ADR-013) : les analyses d'usage et l'expérience A/B restent dans PostHog,
// l'API n'a pas de copie de ces données (choix du développeur pour la première version).
const POSTHOG_LINKS = [
  { path: '/dashboard', label: 'Tableaux de bord', description: 'Rétention, visionnage, engagement' },
  { path: '/experiments', label: 'Expériences', description: 'Résultats de « guest-signup-prompt »' },
  { path: '/feature_flags', label: 'Feature flags', description: 'Variantes et répartition' },
];

export default async function DashboardPage() {
  const stats = await getStats();
  const cards = [
    // Comptes suspendus (ADR-037) : rappelés sous le total.
    {
      title: 'Comptes',
      count: stats.users,
      href: '/users',
      note: stats.users.suspended > 0 ? `${formatNumber(stats.users.suspended)} suspendu(s)` : null,
    },
    { title: 'Vidéos', count: stats.videos, href: '/videos' },
    { title: 'Commentaires', count: stats.comments, href: '/comments' },
    // Jetons vendus en production (ADR-009) ; achats de test à part, sur la page « Jetons ».
    { title: 'Jetons vendus', count: { total: stats.tokens.production.purchased, last7Days: stats.tokens.purchasedLast7Days }, href: '/tokens' },
  ];

  return (
    <div className="flex flex-col gap-6">
      <h1 className="text-2xl font-semibold">Tableau de bord</h1>

      {stats.reports.openTargets > 0 && (
        <Link href="/reports" className="rounded-lg border border-destructive/50 p-3 text-sm text-destructive hover:bg-muted/50">
          {formatNumber(stats.reports.openTargets)} contenu(s) ou compte(s) signalé(s) à examiner.
        </Link>
      )}

      {stats.tokens.unmatched > 0 && (
        <Link href="/tokens?rapprocher=1" className="rounded-lg border border-destructive/50 p-3 text-sm text-destructive hover:bg-muted/50">
          {formatNumber(stats.tokens.unmatched)} achat(s) de jetons d’un client inconnu, à rapprocher avec RevenueCat.
        </Link>
      )}

      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        {cards.map(({ title, count, href, note }) => (
          <Link key={title} href={href}>
            <Card className="transition-colors hover:bg-muted/50">
              <CardHeader>
                <CardDescription>{title}</CardDescription>
                <CardTitle className="text-3xl tabular-nums">{formatNumber(count.total)}</CardTitle>
              </CardHeader>
              <CardContent className="text-sm text-muted-foreground">
                +{formatNumber(count.last7Days)} sur 7 jours
                {note && <span className="text-destructive"> · {note}</span>}
              </CardContent>
            </Card>
          </Link>
        ))}
      </div>

      <Card>
        <CardHeader>
          <CardTitle>Vidéos par statut</CardTitle>
          <CardDescription>Une vidéo en échec ou bloquée en traitement mérite un coup d’œil.</CardDescription>
        </CardHeader>
        <CardContent className="grid gap-4 sm:grid-cols-4">
          {(['ready', 'processing', 'uploading', 'failed'] as const).map((status) => (
            <Link key={status} href={`/videos?status=${status}`} className="rounded-lg border p-3 hover:bg-muted/50">
              <div className="text-sm text-muted-foreground">{VIDEO_STATUS_LABELS[status]}</div>
              <div className="text-xl font-semibold tabular-nums">{formatNumber(stats.videos[status])}</div>
            </Link>
          ))}
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>Mesure d’audience et tests A/B</CardTitle>
          <CardDescription>Données de l’app iOS, dans PostHog.</CardDescription>
        </CardHeader>
        <CardContent>
          {POSTHOG_PROJECT_URL ? (
            <ul className="grid gap-3 sm:grid-cols-3">
              {POSTHOG_LINKS.map(({ path, label, description }) => (
                <li key={path}>
                  <a
                    href={`${POSTHOG_PROJECT_URL}${path}`}
                    target="_blank"
                    rel="noreferrer"
                    className="block rounded-lg border p-3 hover:bg-muted/50"
                  >
                    <span className="flex items-center gap-1 font-medium">
                      {label} <ExternalLinkIcon className="size-3.5" />
                    </span>
                    <span className="text-sm text-muted-foreground">{description}</span>
                  </a>
                </li>
              ))}
            </ul>
          ) : (
            <p className="text-sm text-muted-foreground">
              Renseigne <code>POSTHOG_PROJECT_URL</code> dans le <code>.env</code> (par exemple <code>https://eu.posthog.com/project/12345</code>)
              pour afficher les liens vers le projet PostHog.
            </p>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
