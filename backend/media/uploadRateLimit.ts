import { MediaError } from './errors';

const windows = new Map<string, { count: number; resetAt: number }>();

const MAX_UPLOADS_PER_WINDOW = 30;
const WINDOW_MS = 60_000;

export function checkUploadRateLimit(userId: string): void {
  const now = Date.now();
  let entry = windows.get(userId);
  if (!entry || now >= entry.resetAt) {
    entry = { count: 0, resetAt: now + WINDOW_MS };
    windows.set(userId, entry);
  }
  entry.count += 1;
  if (entry.count > MAX_UPLOADS_PER_WINDOW) {
    throw new MediaError(
      'Too many uploads. Please wait a minute and try again.',
      429,
      'rate_limit_exceeded'
    );
  }
}
