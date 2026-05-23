import {
  IMAGE_PROFILES,
  type PictureFolder,
  PICTURE_FOLDERS,
} from './constants';
import { MediaError } from './errors';
import { processImageForProfile } from './processImage';
import {
  isSupabaseStorageConfigured,
  uploadPicture,
} from './supabaseStorage';
import { assertSafeUserId, validateImageBuffer } from './validateImage';

export interface PersistImageResult {
  url: string;
  storage: 'supabase' | 'inline';
  contentType: string;
  width: number;
  height: number;
  objectKey?: string;
}

export function parseUploadFolder(raw: unknown, fallback: PictureFolder): PictureFolder {
  const f = String(raw ?? '').trim().toLowerCase();
  return PICTURE_FOLDERS.includes(f as PictureFolder) ? (f as PictureFolder) : fallback;
}

export function resolveUploadFileName(folder: PictureFolder, docType?: string): string {
  if (folder === 'avatars') return 'avatar';
  if (folder === 'covers') return 'cover';
  if (folder === 'stories') return 'drop';
  if (folder === 'rider-documents' && docType) {
    return docType.replace(/[^a-z0-9_-]/gi, '');
  }
  return `${Date.now()}`;
}

export async function persistUploadedImage(params: {
  folder: PictureFolder;
  userId: string;
  fileName: string;
  buffer: Buffer;
  mime?: string;
}): Promise<PersistImageResult> {
  assertSafeUserId(params.userId);

  const profile = IMAGE_PROFILES[params.folder];
  if (params.buffer.length > profile.maxInputBytes) {
    throw new MediaError(
      `Image must be under ${Math.round(profile.maxInputBytes / (1024 * 1024))} MB.`,
      413,
      'file_too_large'
    );
  }

  await validateImageBuffer(params.buffer, params.mime);
  const processed = await processImageForProfile(params.buffer, profile);

  const relativePath = `${params.userId}/${params.fileName}.${processed.extension}`;
  const bustCache =
    params.folder === 'avatars' || params.folder === 'covers' || params.folder === 'stories';

  if (isSupabaseStorageConfigured()) {
    const { url, objectKey } = await uploadPicture({
      folder: params.folder,
      relativePath,
      buffer: processed.buffer,
      contentType: processed.contentType,
      cacheControl: profile.cacheControl,
      bustCache,
    });
    return {
      url,
      storage: 'supabase',
      contentType: processed.contentType,
      width: processed.width,
      height: processed.height,
      objectKey,
    };
  }

  const dataUrl = `data:${processed.contentType};base64,${processed.buffer.toString('base64')}`;
  if (dataUrl.length > 900_000) {
    throw new MediaError(
      'Image is still too large after compression. Try a smaller photo or enable Supabase Storage.',
      413,
      'inline_too_large'
    );
  }

  return {
    url: dataUrl,
    storage: 'inline',
    contentType: processed.contentType,
    width: processed.width,
    height: processed.height,
  };
}
