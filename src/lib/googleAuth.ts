/** Google OAuth for web admin/customer login (optional — set VITE_GOOGLE_CLIENT_ID). */
export function getGoogleClientId(): string {
  return (import.meta.env.VITE_GOOGLE_CLIENT_ID as string | undefined)?.trim() || '';
}

export function isGoogleSignInConfigured(): boolean {
  return getGoogleClientId().length > 10;
}
