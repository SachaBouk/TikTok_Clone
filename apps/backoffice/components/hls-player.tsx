'use client';

import { useEffect, useRef, useState } from 'react';

// Lecture HLS (ADR-008) pour vérifier une vidéo signalée : lecture native dans Safari, hls.js ailleurs.
// Les fichiers sont servis par le stockage public (le CDN en production), directement au navigateur.
export function HlsPlayer({ src, poster }: { src: string; poster: string | null }) {
  const video = useRef<HTMLVideoElement>(null);
  const [error, setError] = useState(false);

  useEffect(() => {
    const element = video.current;
    if (!element) return;
    if (element.canPlayType('application/vnd.apple.mpegurl')) {
      element.src = src;
      return;
    }
    let destroy: (() => void) | undefined;
    let cancelled = false;
    void import('hls.js').then(({ default: Hls }) => {
      if (cancelled) return;
      if (!Hls.isSupported()) return setError(true);
      const hls = new Hls();
      hls.on(Hls.Events.ERROR, (_event, data) => data.fatal && setError(true));
      hls.loadSource(src);
      hls.attachMedia(element);
      destroy = () => hls.destroy();
    });
    return () => {
      cancelled = true;
      destroy?.();
    };
  }, [src]);

  return (
    <div className="w-full max-w-xs">
      <video ref={video} poster={poster ?? undefined} controls playsInline className="aspect-[9/16] w-full rounded-lg bg-black" />
      {error && <p className="mt-2 text-sm text-destructive">Lecture impossible dans ce navigateur.</p>}
    </div>
  );
}
