import sharp from 'sharp';

import type { ImageProfile } from './constants';
import { MediaError } from './errors';

export interface ProcessedImage {
  buffer: Buffer;
  contentType: string;
  extension: string;
  width: number;
  height: number;
}

/** Normalize, strip EXIF, resize, encode — production CDN-friendly output. */
export async function processImageForProfile(
  input: Buffer,
  profile: ImageProfile
): Promise<ProcessedImage> {
  try {
    let pipeline = sharp(input, { failOn: 'error' })
      .rotate()
      .resize(profile.maxWidth, profile.maxHeight, {
        fit: 'inside',
        withoutEnlargement: true,
      });

    if (profile.format === 'webp') {
      pipeline = pipeline.webp({ quality: profile.quality, effort: 4 });
    } else {
      pipeline = pipeline.jpeg({
        quality: profile.quality,
        mozjpeg: true,
        chromaSubsampling: '4:4:4',
      });
    }

    const { data, info } = await pipeline.toBuffer({ resolveWithObject: true });

    if (!data.length) {
      throw new MediaError('Image processing produced an empty file.', 500, 'process_failed');
    }

    const contentType = profile.format === 'webp' ? 'image/webp' : 'image/jpeg';
    const extension = profile.format === 'webp' ? 'webp' : 'jpg';

    return {
      buffer: data,
      contentType,
      extension,
      width: info.width,
      height: info.height,
    };
  } catch (err) {
    if (err instanceof MediaError) throw err;
    throw new MediaError('Could not process image. Try a different photo.', 415, 'process_failed');
  }
}
