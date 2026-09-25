import { Injectable } from '@nestjs/common';
import { VideosService } from '../../videos/application/videos.service';
import { AccountContentCleanup } from '../domain/account-content-cleanup';

// Adaptateur : programme le nettoyage des fichiers de toutes les vidéos du compte (module videos, ADR-003).
@Injectable()
export class VideoFilesAccountCleanup extends AccountContentCleanup {
  constructor(private readonly videos: VideosService) {
    super();
  }

  async scheduleCleanup(userId: string): Promise<void> {
    await this.videos.scheduleAuthorFilesCleanup(userId);
  }
}
