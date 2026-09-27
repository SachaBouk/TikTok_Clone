import type { Metadata } from 'next';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { LoginForm } from './login-form';

export const metadata: Metadata = { title: 'Connexion' };

const REASONS: Record<string, string> = {
  session: 'Ta session a expiré : reconnecte-toi.',
  acces: 'Ce compte n’a plus accès au backoffice.',
};

export default async function LoginPage({ searchParams }: { searchParams: Promise<{ suite?: string; raison?: string }> }) {
  const { suite, raison } = await searchParams;
  return (
    <main className="flex min-h-screen items-center justify-center px-4">
      <Card className="w-full max-w-sm">
        <CardHeader>
          <CardTitle>Backoffice</CardTitle>
          <CardDescription>Réservé aux administrateurs.</CardDescription>
        </CardHeader>
        <CardContent>
          <LoginForm returnTo={suite ?? ''} notice={(raison && REASONS[raison]) ?? null} />
        </CardContent>
      </Card>
    </main>
  );
}
