import axios from 'axios';

import type { PictureFolder } from './constants';
import { SIGNED_URL_TTL_SEC } from './constants';
import { MediaError } from './errors';

function envSupabaseUrl(): string {
  return (process.env.SUPABASE_URL || '').replace(/\/$/, '');
}

function envServiceKey(): string {
  return (process.env.SUPABASE_SERVICE_ROLE_KEY || '').trim();
}

function envBucket(): string {
  return (process.env.SUPABASE_STORAGE_BUCKET || 'pictures').trim();
}

export interface StorageConfig {
  configured: boolean;
  bucket: string;
  publicBaseUrl: string | null;
}

export function getStorageConfig(): StorageConfig {
  const url = envSupabaseUrl();
  const key = envServiceKey();
  const bucket = envBucket();
  const configured = Boolean(url && key && bucket);
  return {
    configured,
    bucket,
    publicBaseUrl: configured ? `${url}/storage/v1/object/public/${bucket}` : null,
  };
}

export function isSupabaseStorageConfigured(): boolean {
  return getStorageConfig().configured;
}

export function publicPictureUrl(objectPath: string): string {
  const path = objectPath.replace(/^\/+/, '');
  return `${envSupabaseUrl()}/storage/v1/object/public/${envBucket()}/${path}`;
}

export function storageObjectKey(folder: PictureFolder, relativePath: string): string {
  const safe = relativePath.replace(/^\/+/, '').replace(/\.\./g, '');
  return `${folder}/${safe}`;
}

export function isStorageObjectKey(value: string): boolean {
  if (!value || value.includes('://')) return false;
  return /^(avatars|products|covers|stories|rider-documents)\/[a-zA-Z0-9/_\-.]+$/.test(value);
}

/** Extract canonical storage key from object key or Supabase public/signed URL. */
export function extractPictureObjectKey(stored: string): string | null {
  const trimmed = stored.trim();
  if (!trimmed) return null;
  const pathOnly = trimmed.split('?')[0];
  if (isStorageObjectKey(pathOnly)) return pathOnly;
  const match = pathOnly.match(
    /\/storage\/v1\/object\/(?:public|sign)\/[^/]+\/((?:avatars|products|covers|stories|rider-documents)\/.+)$/i
  );
  return match ? match[1] : null;
}

/** Normalize profile/product image refs for Postgres (prefer stable object keys). */
export function normalizeImageRefForDb(value: unknown): string | null | undefined {
  if (value === undefined) return undefined;
  if (value === null) return null;
  const s = String(value).trim();
  if (!s) return null;
  const key = extractPictureObjectKey(s);
  if (key) return key;
  if (s.startsWith('data:') || s.startsWith('http://') || s.startsWith('https://')) return s;
  return s;
}

function cacheBustUrl(baseUrl: string): string {
  const sep = baseUrl.includes('?') ? '&' : '?';
  return `${baseUrl}${sep}v=${Date.now()}`;
}

export async function uploadPicture(params: {
  folder: PictureFolder;
  relativePath: string;
  buffer: Buffer;
  contentType: string;
  cacheControl: string;
  bustCache?: boolean;
}): Promise<{ url: string; objectKey: string }> {
  if (!isSupabaseStorageConfigured()) {
    throw new MediaError('Object storage is not configured on the server.', 503, 'storage_unavailable');
  }

  const supabaseUrl = envSupabaseUrl();
  const serviceKey = envServiceKey();
  const bucket = envBucket();
  const objectKey = storageObjectKey(params.folder, params.relativePath);
  const uploadUrl = `${supabaseUrl}/storage/v1/object/${bucket}/${objectKey}`;

  try {
    await axios.post(uploadUrl, params.buffer, {
      headers: {
        Authorization: `Bearer ${serviceKey}`,
        'Content-Type': params.contentType,
        'Cache-Control': params.cacheControl,
        'x-upsert': 'true',
      },
      maxBodyLength: Infinity,
      maxContentLength: Infinity,
      timeout: 60_000,
    });
  } catch (err: unknown) {
    const status = (err as { response?: { status?: number; data?: { message?: string } } })
      ?.response?.status;
    const detail = (err as { response?: { data?: { message?: string } } })?.response?.data
      ?.message;
    console.error('[storage] upload failed:', status, detail || err);
    throw new MediaError(
      detail || 'Could not save image to storage. Try again in a moment.',
      status === 413 ? 413 : 502,
      'storage_upload_failed'
    );
  }

  const profile = params.folder;
  const isPublic =
    profile === 'avatars' ||
    profile === 'products' ||
    profile === 'covers' ||
    profile === 'stories';

  if (!isPublic) {
    return { objectKey, url: objectKey };
  }

  const base = publicPictureUrl(objectKey);
  return {
    objectKey,
    url: params.bustCache ? cacheBustUrl(base) : base,
  };
}

const signedUrlCache = new Map<string, { url: string; expires: number }>();

export async function signedPictureUrl(
  objectKey: string,
  expiresInSec: number = SIGNED_URL_TTL_SEC.riderDocument
): Promise<string> {
  if (!isSupabaseStorageConfigured()) return objectKey;
  const cacheKey = `${objectKey}:${expiresInSec}`;
  const cached = signedUrlCache.get(cacheKey);
  if (cached && Date.now() < cached.expires) return cached.url;

  const supabaseUrl = envSupabaseUrl();
  const serviceKey = envServiceKey();
  const bucket = envBucket();
  const path = objectKey.replace(/^\/+/, '');
  try {
    const res = await axios.post<{ signedURL?: string }>(
      `${supabaseUrl}/storage/v1/object/sign/${bucket}/${path}`,
      { expiresIn: expiresInSec },
      {
        headers: {
          Authorization: `Bearer ${serviceKey}`,
          'Content-Type': 'application/json',
        },
        timeout: 15_000,
      }
    );
    const signed = res.data?.signedURL;
    let url: string;
    if (!signed) url = publicPictureUrl(path);
    else if (signed.startsWith('http')) url = signed;
    else url = `${supabaseUrl}${signed.startsWith('/') ? '' : '/'}${signed}`;
    signedUrlCache.set(cacheKey, {
      url,
      expires: Date.now() + Math.max(expiresInSec - 60, 30) * 1000,
    });
    return url;
  } catch (err) {
    console.error('[storage] sign URL failed:', err);
    return publicPictureUrl(path);
  }
}

export async function resolveImageUrlForClient(
  stored: string | null | undefined,
  options?: { adminReview?: boolean }
): Promise<string | null> {
  if (!stored || typeof stored !== 'string') return null;
  const trimmed = stored.trim();
  if (!trimmed) return null;

  const objectKey = extractPictureObjectKey(trimmed);
  if (objectKey) {
    if (objectKey.startsWith('rider-documents/')) {
      const ttl = options?.adminReview
        ? SIGNED_URL_TTL_SEC.adminReview
        : SIGNED_URL_TTL_SEC.riderDocument;
      return signedPictureUrl(objectKey, ttl);
    }
    const base = publicPictureUrl(objectKey);
    if (
      objectKey.startsWith('avatars/') ||
      objectKey.startsWith('covers/') ||
      objectKey.startsWith('stories/')
    ) {
      return cacheBustUrl(base);
    }
    return base;
  }

  if (
    trimmed.startsWith('data:') ||
    trimmed.startsWith('http://') ||
    trimmed.startsWith('https://')
  ) {
    return trimmed;
  }
  return trimmed;
}

/** Lightweight connectivity check for ops / health endpoint. */
export async function probeStorage(): Promise<{ ok: boolean; message?: string }> {
  if (!isSupabaseStorageConfigured()) {
    return { ok: false, message: 'SUPABASE_SERVICE_ROLE_KEY not set' };
  }
  const supabaseUrl = envSupabaseUrl();
  const serviceKey = envServiceKey();
  const bucket = envBucket();
  try {
    await axios.get(`${supabaseUrl}/storage/v1/bucket/${bucket}`, {
      headers: { Authorization: `Bearer ${serviceKey}`, apikey: serviceKey },
      timeout: 10_000,
    });
    return { ok: true };
  } catch (err: unknown) {
    const status = (err as { response?: { status?: number } })?.response?.status;
    if (status === 404) {
      return { ok: false, message: `Bucket "${bucket}" not found — run supabase-storage.sql` };
    }
    return { ok: false, message: (err as Error).message || 'Storage unreachable' };
  }
}
