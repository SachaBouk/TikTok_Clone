import { describe, expect, it } from 'vitest';
import { HOST_CHECK_JOB, lifecycleJobId, TIME_LIMIT_JOB } from './bullmq-live-lifecycle.queue';

describe('identifiants des jobs du live', () => {
  it('un par live et par nom, sans « : » (refusé par BullMQ)', () => {
    const liveId = '01a12100-c2da-744a-9e9e-6da4799c4027';
    expect(lifecycleJobId(TIME_LIMIT_JOB, liveId)).toBe(`timeLimit-${liveId}`);
    expect(lifecycleJobId(HOST_CHECK_JOB, liveId)).not.toBe(lifecycleJobId(TIME_LIMIT_JOB, liveId));
    expect(lifecycleJobId(HOST_CHECK_JOB, liveId)).not.toContain(':');
  });
});
