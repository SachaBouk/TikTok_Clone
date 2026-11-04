import type { StoriesService } from '../../stories/application/stories.service';
import type { VideosService } from '../../videos/application/videos.service';
import type { MuxEvent } from '../domain/mux-event';

export type MuxEventOutcome = 'video' | 'story' | 'unknown';

// Module `mux` (ADR-074), sans données propres : il reçoit le webhook de Mux et le transmet au module de la vidéo ou de la
// story, qui relit son état chez Mux. Sans `passthrough` (versions statiques), la vidéo puis la story sont cherchées par
// leur envoi direct ou leur asset.
export class MuxEventsService {
  constructor(
    private readonly videos: VideosService,
    private readonly stories: StoriesService,
  ) {}

  async handle(event: MuxEvent): Promise<MuxEventOutcome> {
    const ref = { uploadId: event.uploadId, assetId: event.assetId };
    if (event.kind !== 'story' && (await this.videos.syncHostedVideoByRef({ ...ref, videoId: event.kind === 'video' ? event.id : null }))) {
      return 'video';
    }
    if (event.kind !== 'video' && (await this.stories.syncHostedStoryByRef({ ...ref, storyId: event.kind === 'story' ? event.id : null }))) {
      return 'story';
    }
    return 'unknown';
  }
}
