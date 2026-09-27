// Configuration lue côté serveur (pages, Server Actions, proxy) : le navigateur ne contacte jamais l'API
// (ADR-004). Hors NEXT_PUBLIC_, ces variables ne sont de toute façon pas envoyées au navigateur.
export const API_URL = (process.env.API_URL ?? 'http://localhost:3000').replace(/\/+$/, '');

// Projet PostHog (ADR-013), pour les liens du tableau de bord. Facultatif.
export const POSTHOG_PROJECT_URL = process.env.POSTHOG_PROJECT_URL?.replace(/\/+$/, '') || null;
