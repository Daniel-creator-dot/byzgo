/** ISO-style media profiles — tuned for mobile bandwidth & CDN caching. */
export type PictureFolder = 'avatars' | 'products' | 'covers' | 'stories' | 'rider-documents';

export const PICTURE_FOLDERS: PictureFolder[] = [
  'avatars',
  'products',
  'covers',
  'stories',
  'rider-documents',
];

export type ImageOutputFormat = 'webp' | 'jpeg';

export interface ImageProfile {
  readonly folder: PictureFolder;
  readonly maxWidth: number;
  readonly maxHeight: number;
  readonly maxInputBytes: number;
  readonly format: ImageOutputFormat;
  readonly quality: number;
  readonly cacheControl: string;
  readonly isPublic: boolean;
}

export const IMAGE_PROFILES: Record<PictureFolder, ImageProfile> = {
  avatars: {
    folder: 'avatars',
    maxWidth: 512,
    maxHeight: 512,
    maxInputBytes: 3 * 1024 * 1024,
    format: 'webp',
    quality: 82,
    cacheControl: 'public, max-age=3600',
    isPublic: true,
  },
  products: {
    folder: 'products',
    maxWidth: 1200,
    maxHeight: 1200,
    maxInputBytes: 5 * 1024 * 1024,
    format: 'webp',
    quality: 80,
    cacheControl: 'public, max-age=31536000, immutable',
    isPublic: true,
  },
  covers: {
    folder: 'covers',
    maxWidth: 1920,
    maxHeight: 1080,
    maxInputBytes: 5 * 1024 * 1024,
    format: 'webp',
    quality: 80,
    cacheControl: 'public, max-age=3600',
    isPublic: true,
  },
  stories: {
    folder: 'stories',
    maxWidth: 1080,
    maxHeight: 1920,
    maxInputBytes: 6 * 1024 * 1024,
    format: 'webp',
    quality: 82,
    cacheControl: 'public, max-age=3600',
    isPublic: true,
  },
  'rider-documents': {
    folder: 'rider-documents',
    maxWidth: 2400,
    maxHeight: 2400,
    maxInputBytes: 4 * 1024 * 1024,
    format: 'jpeg',
    quality: 85,
    cacheControl: 'private, max-age=600',
    isPublic: false,
  },
};

export const ALLOWED_UPLOAD_MIME = new Set([
  'image/jpeg',
  'image/jpg',
  'image/pjpeg',
  'image/png',
  'image/webp',
]);

/** Max edge length before we reject (anti decompression-bomb). */
export const MAX_IMAGE_EDGE_PX = 8000;

export const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export const SIGNED_URL_TTL_SEC = {
  riderDocument: 900,
  adminReview: 3600,
} as const;
