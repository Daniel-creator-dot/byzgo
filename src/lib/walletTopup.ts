export const PENDING_WALLET_TOPUP_KEY = 'bytzgo_pending_topup_ref';
export const WALLET_PENDING_EVENT = 'bytzgo-wallet-pending';

export function getPendingWalletTopupRef(): string {
  try {
    return localStorage.getItem(PENDING_WALLET_TOPUP_KEY)?.trim() || '';
  } catch {
    return '';
  }
}

export function notifyWalletPendingChange() {
  if (typeof window !== 'undefined') {
    window.dispatchEvent(new Event(WALLET_PENDING_EVENT));
  }
}

export function setPendingWalletTopupRef(reference: string) {
  try {
    localStorage.setItem(PENDING_WALLET_TOPUP_KEY, reference);
    notifyWalletPendingChange();
  } catch {
    /* ignore */
  }
}

export function clearPendingWalletTopupRef() {
  try {
    localStorage.removeItem(PENDING_WALLET_TOPUP_KEY);
    notifyWalletPendingChange();
  } catch {
    /* ignore */
  }
}

/** MoMo SMS IDs are usually digits only — Paystack verify needs the Paystack reference. */
export function looksLikeMomoNetworkId(ref: string): boolean {
  const t = ref.trim();
  return /^\d{9,15}$/.test(t);
}

export function looksLikePaystackReference(ref: string): boolean {
  const t = ref.trim();
  if (!t) return false;
  if (/^bytzgo_/i.test(t)) return true;
  if (/^T[A-Za-z0-9]+$/i.test(t)) return true;
  return /^[A-Za-z0-9_-]{8,64}$/.test(t) && !/^\d+$/.test(t);
}

export function walletTopupReferenceHint(ref: string): string | null {
  const t = ref.trim();
  if (!t) return null;
  if (looksLikeMomoNetworkId(t)) {
    return 'That looks like a MoMo network ID (from your telco SMS), not a payment reference. Use the code from your payment receipt — it usually starts with T or bytzgo_.';
  }
  if (!looksLikePaystackReference(t)) {
    return 'Use the payment reference from the success screen, SMS, or email — not your bank/MoMo approval number.';
  }
  return null;
}

export function formatWalletTopupError(message: string | null | undefined): string {
  const m = (message || '').trim();
  if (!m) return 'Could not verify payment. Try again or contact support.';
  if (/reference not found/i.test(m)) {
    return 'No payment found with that reference. If you paid via MoMo, paste the payment reference (starts with T or bytzgo_), not the MTN/Vodafone transaction ID.';
  }
  if (/secret key/i.test(m)) {
    return 'Wallet top-up is not configured on the server. Contact support.';
  }
  return m;
}