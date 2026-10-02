// Worker de transcodage vidéo (Node + FFmpeg), isolé de l'API (ADR-001).
// Consomme la queue BullMQ `video-transcode`, produit le HLS (ADR-008) et publie chaque résultat dans
// `video-transcode-results`, que l'API applique en base (ADR-012) : le worker n'accède jamais à PostgreSQL.
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { TRANSCODE_QUEUE, TRANSCODE_RESULTS_QUEUE, type TranscodeJobData, type TranscodeResult } from '@repo/shared';
import { Job, Queue, UnrecoverableError, Worker, type ConnectionOptions } from 'bullmq';
import { loadConfig, type WorkerConfig } from './config';
import { InvalidMediaError } from './media/ffmpeg';
import { RawVideoNotFoundError, VideoStorage } from './storage';
import { transcode } from './transcode';

const execFileAsync = promisify(execFile);

async function main() {
  let config: WorkerConfig;
  try {
    config = loadConfig();
  } catch (error) {
    console.error(`[worker] ${(error as Error).message}`);
    process.exit(1);
  }

  try {
    const { stdout } = await execFileAsync(config.ffmpegPath, ['-version']);
    console.log(`[worker] ${stdout.split('\n')[0]}`);
  } catch {
    console.error(`[worker] FFmpeg introuvable (${config.ffmpegPath}). Installez-le ou définissez FFMPEG_PATH.`);
    process.exit(1);
  }

  const connection: ConnectionOptions = { url: config.redisUrl };
  const storage = new VideoStorage(config.s3);

  const results = new Queue<TranscodeResult>(TRANSCODE_RESULTS_QUEUE, { connection });
  // jobId dérivé de la vidéo : un résultat publié deux fois (tentative rejouée) n'est pris qu'une fois.
  const publish = (result: TranscodeResult) =>
    results.add('result', result, { jobId: `${result.videoId}-${result.status}`, removeOnComplete: true, removeOnFail: { age: 7 * 24 * 3600 } });

  const worker = new Worker<TranscodeJobData>(
    TRANSCODE_QUEUE,
    async (job) => {
      const started = Date.now();
      let output;
      try {
        output = await transcode(job.data, config, storage);
      } catch (error) {
        // Fichier illisible ou disparu : les nouvelles tentatives échoueraient de la même façon.
        if (error instanceof InvalidMediaError || error instanceof RawVideoNotFoundError) {
          throw new UnrecoverableError(error.message);
        }
        throw error;
      }
      await publish({ videoId: job.data.videoId, status: 'ready', ...output });
      console.log(`[worker] ${job.data.videoId} transcodée en ${((Date.now() - started) / 1000).toFixed(1)} s`);
    },
    // Verrou long : un transcodage peut durer plusieurs minutes, BullMQ le renouvelle tant que le worker vit.
    { connection, concurrency: config.concurrency, lockDuration: 5 * 60_000 },
  );

  worker.on('failed', (job, error) => {
    if (!job) return;
    void onFailed(job, error, publish);
  });
  worker.on('error', (error) => console.error(`[worker] ${error.message}`));

  await worker.waitUntilReady();
  console.log(`[worker] prêt : queue ${TRANSCODE_QUEUE}, ${config.concurrency} job(s) à la fois`);

  // Arrêt propre : le job en cours se termine avant la fermeture (sinon BullMQ le reprendra).
  const shutdown = async () => {
    console.log('[worker] arrêt…');
    await worker.close();
    await results.close();
    process.exit(0);
  };
  process.once('SIGTERM', () => void shutdown());
  process.once('SIGINT', () => void shutdown());
}

// BullMQ relance le job avec un backoff exponentiel (options fixées par l'API). L'échec est définitif
// après la dernière tentative, ou tout de suite pour une UnrecoverableError : la vidéo passe en `failed`.
async function onFailed(job: Job<TranscodeJobData>, error: Error, publish: (result: TranscodeResult) => Promise<unknown>) {
  const attempts = job.opts.attempts ?? 1;
  const final = error instanceof UnrecoverableError || job.attemptsMade >= attempts;
  if (!final) {
    console.warn(`[worker] ${job.data.videoId} : tentative ${job.attemptsMade}/${attempts} en échec (${error.message}), nouvel essai prévu`);
    return;
  }
  console.error(`[worker] ${job.data.videoId} : échec définitif après ${job.attemptsMade} tentative(s) (${error.message})`);
  try {
    await publish({ videoId: job.data.videoId, status: 'failed', reason: error.message });
  } catch (publishError) {
    // La vidéo reste en `processing` ; la maintenance de l'API la remettra dans la file.
    console.error(`[worker] résultat d'échec non publié pour ${job.data.videoId} : ${(publishError as Error).message}`);
  }
}

void main();
