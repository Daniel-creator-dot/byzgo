import axios from 'axios';

/** Shared API origin for REST and Socket.IO (empty = Vite dev proxy). */
export function getApiBaseUrl(): string {
  const raw = import.meta.env.VITE_API_URL;
  if (raw === undefined || raw === null || String(raw).trim() === '') {
    if (typeof window !== 'undefined') return window.location.origin;
    return 'http://localhost:5173';
  }
  return String(raw).replace(/\/$/, '');
}

export function configureApiClient() {
  const base = getApiBaseUrl();
  axios.defaults.baseURL = base;
  return base;
}

export function getApiError(err: unknown, fallback = 'Something went wrong'): string {
  if (axios.isAxiosError(err)) {
    const data = err.response?.data as { message?: string; error?: string } | undefined;
    return data?.message || data?.error || err.message || fallback;
  }
  if (err instanceof Error) return err.message;
  return fallback;
}
