import type { HealthDto } from '@repo/shared';

const API_URL = process.env.API_URL ?? 'http://localhost:3000';

async function getApiHealth(): Promise<HealthDto | null> {
  try {
    const res = await fetch(`${API_URL}/health`, { cache: 'no-store' });
    return res.ok ? ((await res.json()) as HealthDto) : null;
  } catch {
    return null;
  }
}

export default async function HomePage() {
  const health = await getApiHealth();

  return (
    <main>
      <h1>Backoffice</h1>
      <p>API : {health ? `${health.status} (${health.timestamp})` : 'injoignable'}</p>
    </main>
  );
}
