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
    { title: 'Comptes', count: stats.users, href: '/users' },
    { title: 'Vidéos', count: stats.videos, href: '/videos' },
    { title: 'Commentaires', count: stats.comments, href: '/comments' },
  ];

  return (
    <div className="flex flex-col gap-6">
      <h1 className="text-2xl font-semibold">Tableau de bord</h1>

      <div className="grid gap-4 sm:grid-cols-3">
        {cards.map(({ title, count, href }) => (
          <Link key={title} href={href}>
            <Card className="transition-colors hover:bg-muted/50">
              <CardHeader>
                <CardDescription>{title}</CardDescription>
                <CardTitle className="text-3xl tabular-nums">{formatNumber(count.total)}</CardTitle>
              </CardHeader>
              <CardContent className="text-sm text-muted-foreground">+{formatNumber(count.last7Days)} sur 7 jours</CardContent>
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
                  <a href={`${POSTHOG_PROJECT_URL}${path}`} target="_blank" rel="noreferrer" className="block rounded-lg border p-3 hover:bg-muted/50">
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
              Renseigne <code>POSTHOG_PROJECT_URL</code> dans le <code>.env</code> (par exemple <code>https://eu.posthog.com/project/12345</code>) pour
              afficher les liens vers le projet PostHog.
            </p>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
