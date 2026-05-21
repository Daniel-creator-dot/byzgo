export class MediaError extends Error {
  constructor(
    message: string,
    readonly statusCode: number = 400,
    readonly code?: string
  ) {
    super(message);
    this.name = 'MediaError';
  }
}

export function isMediaError(err: unknown): err is MediaError {
  return err instanceof MediaError;
}
