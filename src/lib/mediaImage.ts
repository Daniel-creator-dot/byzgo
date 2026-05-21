/**
 * Normalize image URLs from API (Supabase CDN, legacy data URLs, external).
 */
export function isDisplayableImageUrl(url: string | null | undefined): boolean {
  if (!url?.trim()) return false;
  const u = url.trim();
  return (
    u.startsWith('https://') ||
    u.startsWith('http://') ||
    u.startsWith('data:image/')
  );
}

export function imageSrc(url: string | null | undefined, fallback?: string): string {
  if (isDisplayableImageUrl(url)) return url!.trim();
  return fallback ?? '';
}
