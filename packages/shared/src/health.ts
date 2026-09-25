export type HealthStatus = 'ok' | 'degraded';

export interface HealthDto {
  status: HealthStatus;
  service: string;
  timestamp: string;
}
