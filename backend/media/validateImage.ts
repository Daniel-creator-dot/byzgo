import sharp from 'sharp';

import { ALLOWED_UPLOAD_MIME, MAX_IMAGE_EDGE_PX, UUID_RE } from './constants';
import { MediaError } from './errors';

/** Magic-byte sniffing (OWASP file upload guidance). */
function detectImageMime(buffer: Buffer): string | null {
  if (buffer.length < 12) return null;
  if (buffer[0] === 0xff && buffer[1] === 0xd8 && buffer[2] === 0xff) {
    return 'image/jpeg';
  }
  if (
    buffer[0] === 0x89 &&
    buffer[1] === 0x50 &&
    buffer[2] === 0x4e &&
    buffer[3] === 0x47
  ) {
    return 'image/png';
  }
  if (
    buffer[0] === 0x52 &&
    buffer[1] === 0x49 &&
    buffer[2] === 0x46 &&
    buffer[3] === 0x46 &&
    buffer[8] === 0x57 &&
    buffer[9] === 0x45 &&
    buffer[10] === 0x42 &&
    buffer[11] === 0x50
  ) {
    return 'image/webp';
  }
  return null;
}

export function assertAllowedMime(declaredMime?: string): void {
  const m = (declaredMime || '').toLowerCase().split(';')[0].trim();
  if (!m || !ALLOWED_UPLOAD_MIME.has(m)) {
    throw new MediaError(
      'Only JPEG, PNG, or WebP images are allowed.',
      415,
      'unsupported_media_type'
    );
  }
}

export async function validateImageBuffer(
  buffer: Buffer,
  declaredMime?: string
): Promise<{ width: number; height: number; detectedMime: string }> {
  if (!buffer?.length) {
    throw new MediaError('Empty file.', 400, 'empty_file');
  }

  assertAllowedMime(declaredMime);

  const detected = detectImageMime(buffer);
  if (!detected) {
    throw new MediaError(
      'File is not a valid image. Upload a photo from your camera or gallery.',
      415,
      'invalid_image'
    );
  }

  let meta: sharp.Metadata;
  try {
    meta = await sharp(buffer, { failOn: 'error' }).metadata();
  } catch {
    throw new MediaError('Could not read image. Try another photo.', 415, 'corrupt_image');
  }

  const width = meta.width ?? 0;
  const height = meta.height ?? 0;
  if (width < 1 || height < 1) {
    throw new MediaError('Invalid image dimensions.', 415, 'invalid_dimensions');
  }
  if (width > MAX_IMAGE_EDGE_PX || height > MAX_IMAGE_EDGE_PX) {
    throw new MediaError(
      'Image is too large. Use a photo under 8000 pixels wide or tall.',
      413,
      'dimensions_exceeded'
    );
  }

  return { width, height, detectedMime: detected };
}

export function assertSafeUserId(userId: string): void {
  if (!UUID_RE.test(userId)) {
    throw new MediaError('Invalid user id for storage path.', 400, 'invalid_path');
  }
}
