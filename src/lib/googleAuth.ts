/** Web Google Sign-In client id (must match backend GOOGLE_WEB_CLIENT_ID). */
export const googleWebClientId =
  import.meta.env.VITE_GOOGLE_CLIENT_ID?.trim() ||
  import.meta.env.VITE_GOOGLE_WEB_CLIENT_ID?.trim() ||
  '';

export const isGoogleSignInConfigured = googleWebClientId.length > 10;
