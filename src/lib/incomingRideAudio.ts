/** Shared ring audio — must be unlocked after a user gesture (tap Go Online, etc.). */

let sharedCtx: AudioContext | null = null;

export function unlockIncomingRideAudio(): void {
  if (typeof window === 'undefined') return;
  try {
    if (!sharedCtx) sharedCtx = new AudioContext();
    if (sharedCtx.state === 'suspended') {
      void sharedCtx.resume();
    }
  } catch {
    /* Web Audio unavailable */
  }
}

export function playIncomingRidePulse(): void {
  unlockIncomingRideAudio();
  const audioCtx = sharedCtx;
  if (!audioCtx || audioCtx.state !== 'running') return;

  const t = audioCtx.currentTime;
  [523.25, 659.25, 783.99].forEach((freq, i) => {
    const osc = audioCtx.createOscillator();
    const gain = audioCtx.createGain();
    osc.type = 'sine';
    osc.frequency.value = freq;
    gain.gain.setValueAtTime(0.0001, t + i * 0.18);
    gain.gain.exponentialRampToValueAtTime(0.4, t + i * 0.18 + 0.03);
    gain.gain.exponentialRampToValueAtTime(0.0001, t + i * 0.18 + 0.22);
    osc.connect(gain);
    gain.connect(audioCtx.destination);
    osc.start(t + i * 0.18);
    osc.stop(t + i * 0.18 + 0.24);
  });
}

export function closeIncomingRideAudio(): void {
  if (!sharedCtx) return;
  void sharedCtx.close().catch(() => {});
  sharedCtx = null;
}
