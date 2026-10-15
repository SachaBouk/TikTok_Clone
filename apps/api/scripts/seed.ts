// Seed de démo (ADR-016), uniquement en local : comptes de démonstration, vidéos du feed,
// interactions entre les comptes (likes, favoris, republications, follows, commentaires)
// et conversations privées entre abonnés mutuels.
//
// Le script est un client de l'API, comme l'app iOS : il crée les comptes via /auth/register et publie
// chaque vidéo par le même parcours qu'un upload depuis l'app (URLs signées, envoi direct au stockage,
// confirmation → vidéo `uploading` puis job de transcodage). Il reste ainsi aligné sur le pipeline
// vidéo sans rien en dupliquer (ADR-016, conséquence négative). Les interactions passent elles aussi
// par l'API : les compteurs sont donc tenus par les triggers de la base, et le centre d'activité
// (notifications) est alimenté par le module interactions, comme en usage réel.
//
// Prérequis : `pnpm infra:up`, l'API et le worker lancés (`pnpm dev`).
// Usage : pnpm seed [--videos=12] [--no-wait] [--no-interactions]   (--no-interactions : ni interactions ni conversations)
//   --videos=0 : aucune nouvelle vidéo, seulement les comptes et les interactions sur les vidéos existantes.
//   Vidéos : celles de seed/videos/ (.mp4, .mov) si le dossier en contient, sinon générées avec FFmpeg.
//   Celles de seed/videos/ sont d'abord recopiées sans métadonnées (position GPS…), comme l'app le fait avant l'envoi.
//   Relançable : les comptes sont réutilisés, les interactions et conversations ne sont pas dupliquées ;
//   seules les vidéos s'ajoutent à chaque lancement.
import { execFile } from 'node:child_process';
import { createHash } from 'node:crypto';
import { existsSync, mkdtempSync, readdirSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { basename, extname, join, resolve } from 'node:path';
import { promisify } from 'node:util';
import type {
  AuthTokensDto,
  CommentPageDto,
  ConversationDto,
  FeedItemDto,
  FeedPageDto,
  UnreadConversationsDto,
  UnreadNotificationsDto,
  VideoDto,
  VideoUploadDto,
} from '@repo/shared';

const execFileAsync = promisify(execFile);
const ROOT = resolve(__dirname, '../../..');
const API_URL = (process.env.SEED_API_URL ?? `http://localhost:${process.env.PORT ?? 3000}`).replace(/\/+$/, '');
const VIDEOS_DIR = resolve(ROOT, process.env.SEED_VIDEOS_DIR ?? 'seed/videos');
const FFMPEG = process.env.FFMPEG_PATH || 'ffmpeg';
// Mot de passe commun des comptes de démo : local uniquement. Une lettre et un chiffre (ADR-055) ; les comptes de démo
// créés avant gardent l'ancien (`demo-password`), essayé à la connexion s'il le faut.
const PASSWORD = 'demo-password1';
const LEGACY_PASSWORD = 'demo-password';
// Date de naissance des comptes de démo (ADR-055 : 13 ans au moins).
const BIRTH_DATE = '2000-01-01';
// Mot de passe qui fonctionne, par email (nouveau ou ancien).
const passwords = new Map<string, string>();
const WAIT_TIMEOUT_MS = 10 * 60_000;

const ACCOUNTS = [
  { username: 'lea.martin', displayName: 'Léa Martin' },
  { username: 'hugo.bernard', displayName: 'Hugo Bernard' },
  { username: 'chloe.dubois', displayName: 'Chloé Dubois' },
  { username: 'nathan.petit', displayName: 'Nathan Petit' },
  { username: 'ines.moreau', displayName: 'Inès Moreau' },
];

const CAPTIONS = [
  'Premier essai, soyez indulgents #premièrevidéo',
  'Le coucher de soleil de ce soir #sunset #été',
  'Recette express en 30 secondes #recette #cuisine',
  'Quand le lundi matin arrive #lundi #humour',
  'Petit tour en ville #balade',
  'Mon setup de travail #setup #tech',
  'Tentative de trend, avis ? #trend #humour',
  'Ambiance du week-end #weekend #été',
  'Tuto rapide pour débutants #tuto #tech',
  'Les coulisses du tournage #coulisses',
  'Défi du jour relevé #défi #trend',
  'Moment détente #détente',
];

// Motifs générés par FFmpeg pour les vidéos de démo, en vertical comme sur TikTok.
const PATTERNS = [
  'gradients=size=540x960:rate=30:speed=0.03',
  'mandelbrot=size=540x960:rate=30',
  'testsrc2=size=540x960:rate=30',
  'cellauto=size=540x960:rate=30:rule=110',
  'life=size=540x960:rate=30:mold=10:ratio=0.1:life_color=#FFD23F:death_color=#EE4266',
  'smptehdbars=size=540x960:rate=30',
];

const CONTENT_TYPES: Record<string, string> = { '.mp4': 'video/mp4', '.mov': 'video/quicktime' };

const COMMENTS = [
  'Trop bien 😍',
  'Ça me donne envie d’essayer !',
  'Le montage est super propre',
  'Je l’ai regardée trois fois',
  'Tu peux faire la suite ?',
  'Haha, trop vrai',
  'Pépite du jour',
  'La musique 👌',
  'Je partage à mes potes',
  'Incroyable, bravo',
];

// Échanges des conversations de démo : chaque conversation en reprend 2 à 4, en alternant les participants.
const DIRECT_MESSAGES = [
  'Hello ! Tu as vu ma dernière vidéo ?',
  'Oui, trop drôle 😂',
  'On en tourne une ensemble ce week-end ?',
  'Carrément, samedi ça te va ?',
  'Parfait, je ramène la lumière',
  'Ta dernière trend est incroyable',
  'Merci ! Deux heures pour la caler 😅',
  'Ça se voit, bravo',
];

// Probabilité (en %) de chaque interaction, pour chaque paire compte / vidéo (ou compte / compte).
// Le tirage est déterministe (hachage) : une relance refait exactement les mêmes choix.
const INTERACTION_RATES = { view: 85, like: 60, favorite: 20, repost: 10, comment: 30, follow: 75, conversation: 70, request: 60 };

// Premier message d'une demande de message (comptes qui ne se suivent pas mutuellement).
const REQUEST_MESSAGES = ['Salut ! J’adore tes vidéos 🙌', 'Hello, on pourrait faire une collab ?', 'Ta dernière vidéo m’a fait rire 😂'];

interface Account {
  username: string;
  displayName: string;
  email: string;
  token: string;
}

async function main() {
  const args = process.argv.slice(2);
  const videoCount = Number(args.find((a) => a.startsWith('--videos='))?.split('=')[1] ?? 12);
  const wait = !args.includes('--no-wait');
  const withInteractions = !args.includes('--no-interactions');

  assertLocal(API_URL);
  await assertApiUp();

  console.log('Comptes de démonstration');
  const accounts: Account[] = [];
  for (const account of ACCOUNTS) accounts.push(await ensureAccount(account));

  const provided = listProvidedVideos();
  const workDir = mkdtempSync(join(tmpdir(), 'seed-videos-'));
  try {
    const files = provided.length > 0 ? await withoutMetadata(provided, workDir) : videoCount > 0 ? await generateVideos(videoCount, workDir) : [];
    if (files.length > 0) {
      console.log(`\nPublication de ${files.length} vidéo(s) ${provided.length > 0 ? `depuis ${VIDEOS_DIR}` : 'générées'}`);
    } else {
      console.log('\n--videos=0 : aucune vidéo publiée');
    }

    const published: { id: string; account: Account }[] = [];
    for (const [index, file] of files.entries()) {
      const account = accounts[index % accounts.length];
      const id = await publish(account, file, CAPTIONS[index % CAPTIONS.length]);
      published.push({ id, account });
      console.log(`  ${index + 1}/${files.length}  @${account.username}  ${id}`);
    }

    if (published.length > 0 && wait) await waitForTranscoding(published);
    else if (published.length > 0) {
      console.log('\n--no-wait : les vidéos seront prêtes quand le worker les aura transcodées (interactions sur les vidéos déjà publiées).');
    }
  } finally {
    rmSync(workDir, { recursive: true, force: true });
  }

  if (withInteractions) {
    // Nouveaux access tokens : ceux du début (15 min) ont pu expirer pendant l'attente du transcodage.
    for (const account of accounts) account.token = await login(account.email, account.username);
    await seedInteractions(accounts);
    await seedConversations(accounts);
  }

  console.log('\nComptes :');
  for (const account of accounts)
    console.log(`  ${account.email}  @${account.username}  (mot de passe : ${passwords.get(account.email) ?? PASSWORD})`);
}

// ADR-016 : seed réservé au local et à la démo.
function assertLocal(url: string) {
  const { hostname } = new URL(url);
  if (!['localhost', '127.0.0.1', '::1'].includes(hostname)) {
    throw new Error(`Seed réservé au local (ADR-016) : ${url} n'est pas une adresse locale.`);
  }
}

async function assertApiUp() {
  const ok = await fetch(`${API_URL}/health`)
    .then((r) => r.ok)
    .catch(() => false);
  if (!ok) throw new Error(`API injoignable sur ${API_URL}. Lancez d'abord : pnpm infra:up puis pnpm dev`);
}

// Inscription, ou connexion si le compte existe déjà : le script peut être relancé.
async function ensureAccount({ username, displayName }: (typeof ACCOUNTS)[number]): Promise<Account> {
  const email = `${username}@demo.local`;
  const registered = await request('POST', '/auth/register', { body: { email, password: PASSWORD, username, displayName, birthDate: BIRTH_DATE } });
  if (registered.status === 201) {
    passwords.set(email, PASSWORD);
    console.log(`  créé      @${username}`);
    return { username, displayName, email, token: (registered.body as AuthTokensDto).accessToken };
  }
  if (registered.status !== 409) throw apiError('inscription', registered);

  const token = await login(email, username);
  console.log(`  existant  @${username}`);
  return { username, displayName, email, token };
}

async function login(email: string, username: string): Promise<string> {
  const candidates = passwords.has(email) ? [passwords.get(email)!] : [PASSWORD, LEGACY_PASSWORD];
  let response: Awaited<ReturnType<typeof request>> | null = null;
  for (const password of candidates) {
    response = await request('POST', '/auth/login', { body: { identifier: email, password } });
    if (response.status === 200) {
      passwords.set(email, password);
      return (response.body as AuthTokensDto).accessToken;
    }
    if (response.status !== 401) break;
  }
  throw apiError(`connexion de @${username} (compte existant avec un autre mot de passe ?)`, response!);
}

function listProvidedVideos(): string[] {
  if (!existsSync(VIDEOS_DIR)) return [];
  return readdirSync(VIDEOS_DIR)
    .filter((name) => CONTENT_TYPES[extname(name).toLowerCase()])
    .sort()
    .map((name) => join(VIDEOS_DIR, name));
}

// Copie des vidéos fournies sans leurs métadonnées (position GPS, appareil…), sans réencodage : la position
// ne doit pas partir vers le stockage, comme depuis l'app. La rotation, portée par la piste vidéo, est gardée.
// Pistes gardées : la vidéo (hors pochette) et le son ; les pistes de métadonnées d'iPhone sont écartées.
async function withoutMetadata(files: string[], directory: string): Promise<string[]> {
  console.log(`\nRetrait des métadonnées de ${files.length} vidéo(s) de ${VIDEOS_DIR}`);
  const cleaned: string[] = [];
  for (const file of files) {
    const output = join(directory, basename(file));
    await execFileAsync(FFMPEG, [
      '-nostdin',
      '-y',
      '-loglevel',
      'error',
      '-i',
      file,
      '-map',
      '0:V',
      '-map',
      '0:a?',
      '-c',
      'copy',
      '-map_metadata',
      '-1',
      '-map_chapters',
      '-1',
      output,
    ]);
    cleaned.push(output);
  }
  return cleaned;
}

// Asynchrone, pas execFileSync : bloquer la boucle d'événements plusieurs secondes empêche Node de voir
// que l'API a fermé une connexion keep-alive inactive, et le fetch suivant échoue (ECONNRESET).
async function generateVideos(count: number, directory: string): Promise<string[]> {
  console.log(`\nGénération de ${count} vidéo(s) de démo avec FFmpeg`);
  const files: string[] = [];
  for (let index = 0; index < count; index++) {
    const file = join(directory, `demo-${String(index + 1).padStart(2, '0')}.mp4`);
    const source = PATTERNS[index % PATTERNS.length];
    const title = `drawtext=font=Arial:text='Démo ${index + 1}':fontsize=120:fontcolor=white:borderw=6:bordercolor=black:x=(w-tw)/2:y=h*0.42`;
    const encode = (filters: string) =>
      execFileAsync(FFMPEG, [
        '-nostdin',
        '-y',
        '-loglevel',
        'error',
        '-f',
        'lavfi',
        '-i',
        source,
        '-f',
        'lavfi',
        '-i',
        `sine=frequency=${220 + index * 55}`,
        '-t',
        String(6 + (index % 5)),
        '-vf',
        filters,
        '-c:v',
        'libx264',
        '-preset',
        'ultrafast',
        '-crf',
        '26',
        '-pix_fmt',
        'yuv420p',
        '-c:a',
        'aac',
        '-shortest',
        file,
      ]);
    try {
      await encode(`scale=1080:1920:flags=neighbor,${title}`);
    } catch {
      // FFmpeg sans drawtext ou sans police : vidéo sans titre.
      await encode('scale=1080:1920:flags=neighbor');
    }
    files.push(file);
  }
  return files;
}

// Même parcours qu'un upload depuis l'app (ADR-007).
async function publish(account: Account, file: string, description: string): Promise<string> {
  const bytes = readFileSync(file);
  const created = await request('POST', '/videos/upload-url', {
    token: account.token,
    body: { contentType: CONTENT_TYPES[extname(file).toLowerCase()], fileSize: bytes.length, description },
  });
  if (created.status !== 201) throw apiError(`demande d'upload pour ${file}`, created);
  const upload = created.body as VideoUploadDto;

  const parts = [];
  for (const part of upload.parts) {
    const chunk = bytes.subarray((part.partNumber - 1) * upload.partSize, part.partNumber * upload.partSize);
    const response = await fetch(part.url, { method: 'PUT', body: chunk });
    const etag = response.headers.get('etag');
    if (!response.ok || !etag) throw new Error(`Envoi de la partie ${part.partNumber} de ${file} refusé par le stockage (${response.status})`);
    parts.push({ partNumber: part.partNumber, etag });
  }

  const confirmed = await request('PATCH', `/videos/${upload.video.id}/uploaded`, { token: account.token, body: { parts } });
  if (confirmed.status !== 200) throw apiError(`confirmation de ${file}`, confirmed);
  return upload.video.id;
}

async function waitForTranscoding(videos: { id: string; account: Account }[]) {
  console.log('\nTranscodage par le worker…');
  const pending = new Map(videos.map((v) => [v.id, v.account]));
  const counts = { ready: 0, failed: 0 };
  const started = Date.now();
  let hinted = false;

  while (pending.size > 0 && Date.now() - started < WAIT_TIMEOUT_MS) {
    for (const [id, account] of pending) {
      const { body } = await request('GET', `/videos/${id}`, { token: account.token });
      const status = (body as VideoDto).status;
      if (status === 'ready' || status === 'failed') {
        counts[status]++;
        pending.delete(id);
      }
    }
    process.stdout.write(`\r  ${counts.ready} prête(s), ${counts.failed} en échec, ${pending.size} en cours   `);
    if (!hinted && pending.size === videos.length && Date.now() - started > 30_000) {
      process.stdout.write('\n  Aucune vidéo traitée depuis 30 s : le worker tourne-t-il ? (pnpm dev ou pnpm --filter worker dev)\n');
      hinted = true;
    }
    if (pending.size > 0) await new Promise((r) => setTimeout(r, 2000));
  }
  console.log(pending.size > 0 ? `\n  Délai dépassé : ${pending.size} vidéo(s) encore en cours.` : '');
  if (counts.failed > 0) process.exitCode = 1;
}

// Interactions entre les comptes de démo, sur toutes les vidéos publiées (y compris celles des lancements
// précédents). Personne n'interagit avec ses propres vidéos. Likes, favoris, republications et follows sont
// idempotents côté API ; un commentaire n'est ajouté que si le compte n'a pas déjà commenté la vidéo.
// Pas de partages : sans table, ils ne sont pas dédoublonnables et gonfleraient à chaque relance.
async function seedInteractions(accounts: Account[]) {
  const videos = await listPublishedVideos();
  console.log(`\nInteractions entre les comptes sur ${videos.length} vidéo(s) publiée(s)`);
  if (videos.length === 0) return;

  const done = { view: 0, like: 0, favorite: 0, repost: 0, comment: 0, follow: 0 };
  for (const account of accounts) {
    for (const other of accounts) {
      if (other === account || !picked('follow', account.username, other.username)) continue;
      await expectOk(request('PUT', `/users/${other.username}/follow`, { token: account.token }), `follow de @${other.username}`);
      done.follow++;
    }

    for (const video of videos) {
      if (video.author.username === account.username) continue;
      // Une vue par compte et par vidéo (views_count, historique de visionnage). Réagir implique d'avoir vu.
      const reacts = (['like', 'favorite', 'repost', 'comment'] as const).some((kind) => picked(kind, account.username, video.id));
      if (reacts || picked('view', account.username, video.id)) {
        await expectOk(request('POST', `/videos/${video.id}/view`, { token: account.token }), `vue de ${video.id}`);
        done.view++;
      }
      for (const kind of ['like', 'favorite', 'repost'] as const) {
        if (!picked(kind, account.username, video.id)) continue;
        await expectOk(request('PUT', `/videos/${video.id}/${kind}`, { token: account.token }), `${kind} de ${video.id}`);
        done[kind]++;
      }
      if (picked('comment', account.username, video.id) && (await ensureComment(account, video.id))) done.comment++;
    }
  }
  // Vues, likes, favoris, republications et follows sont idempotents : ces nombres décrivent l'état obtenu,
  // identique d'un lancement à l'autre. Seuls les commentaires sont comptés quand ils sont nouveaux.
  console.log(
    `  état : ${done.view} vue(s), ${done.like} like(s), ${done.favorite} favori(s), ${done.repost} republication(s), ${done.follow} follow(s)\n` +
      `  ${done.comment} commentaire(s) ajouté(s)`,
  );

  // Produites par l'API à chaque interaction (sans doublon : un like rejoué ne notifie pas deux fois).
  console.log('\nCentre d’activité (notifications non lues)');
  for (const account of accounts) {
    const response = await request('GET', '/notifications/unread-count', { token: account.token });
    if (response.status !== 200) throw apiError(`notifications de @${account.username}`, response);
    console.log(`  @${account.username.padEnd(13)} ${(response.body as UnreadNotificationsDto).unreadCount}`);
  }
}

// Conversations privées, via l'API comme dans l'app : échanges entre abonnés mutuels, et demandes de message
// (un premier message) entre comptes qui ne se suivent pas mutuellement.
// Relançable : une conversation qui a déjà des messages n'est pas complétée. Les messages restent non lus
// par leur destinataire, pour montrer les badges de la boîte de réception et des demandes.
async function seedConversations(accounts: Account[]) {
  console.log('\nConversations privées et demandes de message');
  let created = 0;
  let sent = 0;
  let requests = 0;
  for (const [i, first] of accounts.entries()) {
    for (const second of accounts.slice(i + 1)) {
      // Abonnés mutuels d'après les tirages des follows : pas de conversation vide ouverte pour rien.
      const mutual = picked('follow', first.username, second.username) && picked('follow', second.username, first.username);
      if (!mutual) {
        if (picked('request', first.username, second.username) && (await sendRequest(first, second))) requests++;
        continue;
      }
      if (!picked('conversation', first.username, second.username)) continue;
      const response = await request('POST', '/conversations', { token: first.token, body: { username: second.username } });
      if (response.status !== 200) throw apiError(`conversation avec @${second.username}`, response);
      const conversation = response.body as ConversationDto;
      if (!conversation.canSend || conversation.lastMessage) continue;

      const count = 2 + (hash('messages', first.username, second.username) % 3);
      const start = hash('start', first.username, second.username) % DIRECT_MESSAGES.length;
      for (let n = 0; n < count; n++) {
        const sender = n % 2 === 0 ? first : second;
        const content = DIRECT_MESSAGES[(start + n) % DIRECT_MESSAGES.length];
        await expectOk(
          request('POST', `/conversations/${conversation.id}/messages`, { token: sender.token, body: { content } }),
          `message de @${sender.username}`,
        );
        sent++;
      }
      created++;
    }
  }
  console.log(`  ${created} conversation(s) créée(s), ${sent} message(s), ${requests} demande(s) de message`);

  console.log('\nBoîte de réception (conversations non lues / demandes reçues)');
  for (const account of accounts) {
    const response = await request('GET', '/conversations/unread-count', { token: account.token });
    if (response.status !== 200) throw apiError(`boîte de réception de @${account.username}`, response);
    const badges = response.body as UnreadConversationsDto;
    console.log(`  @${account.username.padEnd(13)} ${badges.unreadCount} / ${badges.requestCount}`);
  }
}

// Demande de message : un premier message de `from` à `to`, s'il ne lui a pas déjà écrit.
async function sendRequest(from: Account, to: Account): Promise<boolean> {
  const response = await request('POST', '/conversations', { token: from.token, body: { username: to.username } });
  if (response.status !== 200) throw apiError(`demande à @${to.username}`, response);
  const conversation = response.body as ConversationDto;
  if (conversation.lastMessage || !conversation.canSend) return false;
  const content = REQUEST_MESSAGES[hash('request-text', from.username, to.username) % REQUEST_MESSAGES.length];
  await expectOk(
    request('POST', `/conversations/${conversation.id}/messages`, { token: from.token, body: { content } }),
    `demande à @${to.username}`,
  );
  return true;
}

// Toutes les vidéos publiées, lues comme un invité via le feed (tant qu'il y a une page suivante).
async function listPublishedVideos(): Promise<FeedItemDto[]> {
  const videos: FeedItemDto[] = [];
  let cursor: string | null = null;
  do {
    const response = await request('GET', `/feed?limit=20${cursor ? `&cursor=${encodeURIComponent(cursor)}` : ''}`);
    if (response.status !== 200) throw apiError('lecture du feed', response);
    const page = response.body as FeedPageDto;
    videos.push(...page.items);
    cursor = page.nextCursor;
  } while (cursor);
  return videos;
}

// Renvoie true si un commentaire a été ajouté (false si le compte avait déjà commenté la vidéo).
async function ensureComment(account: Account, videoId: string): Promise<boolean> {
  let cursor: string | null = null;
  do {
    const response = await request('GET', `/videos/${videoId}/comments?limit=50${cursor ? `&cursor=${cursor}` : ''}`);
    if (response.status !== 200) throw apiError(`lecture des commentaires de ${videoId}`, response);
    const page = response.body as CommentPageDto;
    if (page.items.some((comment) => comment.author.username === account.username)) return false;
    cursor = page.nextCursor;
  } while (cursor);

  const content = COMMENTS[hash('text', account.username, videoId) % COMMENTS.length];
  await expectOk(request('POST', `/videos/${videoId}/comments`, { token: account.token, body: { content } }), `commentaire sur ${videoId}`);
  return true;
}

// Tirage déterministe : le même compte et la même cible donnent toujours le même résultat.
function picked(kind: keyof typeof INTERACTION_RATES, ...parts: string[]): boolean {
  return hash(kind, ...parts) % 100 < INTERACTION_RATES[kind];
}

function hash(...parts: string[]): number {
  return createHash('sha256').update(parts.join(':')).digest().readUInt32BE(0);
}

async function expectOk(pending: Promise<ApiResponse>, action: string): Promise<void> {
  const response = await pending;
  if (response.status < 200 || response.status >= 300) throw apiError(action, response);
}

interface ApiResponse {
  status: number;
  body: unknown;
}

// Limites de débit de l'API (ADR-030, ADR-039) : une limite par minute est attendue (`Retry-After`), puis la requête
// est rejouée ; une limite plus longue (par heure, par jour) arrête le seed avec un message.
const MAX_RATE_LIMIT_WAIT_SECONDS = 120;

async function request(method: string, path: string, { token, body }: { token?: string; body?: unknown } = {}): Promise<ApiResponse> {
  for (;;) {
    const response = await fetch(`${API_URL}${path}`, {
      method,
      headers: { ...(body ? { 'Content-Type': 'application/json' } : {}), ...(token ? { Authorization: `Bearer ${token}` } : {}) },
      body: body ? JSON.stringify(body) : undefined,
    });
    const text = await response.text();
    if (response.status === 429) {
      const wait = Number(response.headers.get('retry-after') ?? 60);
      if (wait > MAX_RATE_LIMIT_WAIT_SECONDS) {
        throw new Error(
          `Limite de débit de l'API atteinte (${method} ${path}, ${wait} s d'attente). ` +
            'Publier moins de vidéos, ou supprimer les clés Redis ratelimit:* (base locale seulement).',
        );
      }
      console.log(`  limite de débit (${method} ${path}) : attente de ${wait} s`);
      // Attente non bloquante : la boucle d'événements doit voir les connexions keep-alive fermées (piège du seed).
      await new Promise((resolve) => setTimeout(resolve, wait * 1000));
      continue;
    }
    return { status: response.status, body: text ? JSON.parse(text) : null };
  }
}

function apiError(action: string, response: ApiResponse): Error {
  const message = (response.body as { message?: unknown } | null)?.message;
  return new Error(`Échec : ${action} (HTTP ${response.status}${message ? ` : ${JSON.stringify(message)}` : ''})`);
}

main().catch((error: Error) => {
  // `fetch failed` de Node cache la vraie raison (connexion refusée, socket fermé…) dans `cause`.
  const cause = error.cause instanceof Error ? ` (${error.cause.message})` : '';
  console.error(`\n${error.message}${cause}`);
  process.exit(1);
});
