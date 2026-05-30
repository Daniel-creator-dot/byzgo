/** Paystack Inline checkout helpers for BytzGo (GHS / MoMo) */

export type PaystackSuccessHandler = (reference: string) => void | Promise<void>;

declare global {
  interface Window {
    PaystackPop?: {
      setup: (options: Record<string, unknown>) => { openIframe: () => void };
    };
  }
}

export function isPaystackPublicKeyValid(key: string): boolean {
  return /^pk_(test|live)_[a-zA-Z0-9]+$/.test(key.trim());
}

export function paystackPaymentEmail(user: {
  email?: string;
  phone?: string;
  id: string;
}): string {
  const email = user.email?.trim();
  if (email && email.includes('@')) return email;
  const digits = user.phone?.replace(/\D/g, '');
  if (digits && digits.length >= 9) return `user${digits}@bytzgo.app`;
  return `user${user.id.replace(/-/g, '').slice(0, 12)}@bytzgo.app`;
}

export function loadPaystackScript(): Promise<void> {
  if (typeof window === 'undefined') return Promise.reject(new Error('Not in browser'));
  if (window.PaystackPop) return Promise.resolve();

  return new Promise((resolve, reject) => {
    const existing = document.querySelector<HTMLScriptElement>('script[src*="paystack.co"]');
    if (existing) {
      if (window.PaystackPop) {
        resolve();
        return;
      }
      existing.addEventListener('load', () => resolve());
      existing.addEventListener('error', () => reject(new Error('Payment service failed to load. Refresh and try again.')));
      return;
    }

    const script = document.createElement('script');
    script.src = 'https://js.paystack.co/v1/inline.js';
    script.async = true;
    script.onload = () => resolve();
    script.onerror = () => reject(new Error('Payment service failed to load. Refresh and try again.'));
    document.head.appendChild(script);
  });
}

function paystackOpenHint(publicKey: string): string | null {
  if (typeof window === 'undefined') return null;
  const host = window.location.hostname;
  if ((host === 'localhost' || host === '127.0.0.1') && publicKey.startsWith('pk_live_')) {
    return 'Live payment keys often fail on localhost. Use test keys in admin for local development.';
  }
  return null;
}

export function openPaystackCheckout(options: {
  publicKey: string;
  email: string;
  amountGhs: number;
  onSuccess: PaystackSuccessHandler;
  onClose?: () => void;
  /** Called as soon as the checkout reference is created (for wallet recovery). */
  onReferenceReady?: (reference: string) => void;
  metadata?: Record<string, unknown>;
}): Promise<void> {
  const { publicKey, email, amountGhs, onSuccess, onClose, onReferenceReady, metadata } = options;

  if (!isPaystackPublicKeyValid(publicKey)) {
    return Promise.reject(new Error('Payments are not configured. Contact support.'));
  }

  const amount = Math.round(amountGhs * 100);
  if (!Number.isFinite(amount) || amount < 100) {
    return Promise.reject(new Error('Minimum top-up is ₵1'));
  }

  const localhostHint = paystackOpenHint(publicKey);

  return loadPaystackScript().then(
    () =>
      new Promise<void>((resolve, reject) => {
        const PaystackPop = window.PaystackPop;
        if (!PaystackPop) {
          reject(new Error('Payment service not loaded. Refresh and try again.'));
          return;
        }

        const ref = `bytzgo_${Date.now()}_${Math.random().toString(36).slice(2, 10)}`;
        onReferenceReady?.(ref);

        let handler: { openIframe: () => void };
        try {
          handler = PaystackPop.setup({
            key: publicKey.trim(),
            email: email.trim(),
            amount,
            currency: 'GHS',
            ref,
            channels: ['card', 'mobile_money', 'bank'],
            metadata: metadata ?? {},
            callback: (response: { reference: string }) => {
              void Promise.resolve(onSuccess(response.reference)).catch((err) =>
                console.error('Paystack success handler error:', err)
              );
            },
            onClose: () => {
              onClose?.();
              resolve();
            },
          });
        } catch (err) {
          const msg = err instanceof Error ? err.message : 'Could not start payment';
          reject(new Error(localhostHint ? `${msg}. ${localhostHint}` : msg));
          return;
        }

        if (!handler?.openIframe) {
          reject(
            new Error(
              localhostHint ?? 'Could not start payment. Try again later.'
            )
          );
          return;
        }

        // Open after modal animations / stacking contexts settle
        window.setTimeout(() => {
          try {
            handler.openIframe();
          } catch (err) {
            const msg = err instanceof Error ? err.message : 'Could not open payment window';
            reject(new Error(localhostHint ? `${msg}. ${localhostHint}` : msg));
          }
        }, 150);
      })
  );
}
