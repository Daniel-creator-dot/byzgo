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
  if (!audioCtx) return;
  if (audioCtx.state === 'suspended') {
    void audioCtx.resume().then(() => playIncomingRidePulse());
    return;
  }
  if (audioCtx.state !== 'running') return;

  const t = audioCtx.currentTime;
  [523.25, 659.25, 783.99, 1046.5].forEach((freq, i) => {
    const osc = audioCtx.createOscillator();
    const gain = audioCtx.createGain();
    osc.type = 'sine';
    osc.frequency.value = freq;
    gain.gain.setValueAtTime(0.0001, t + i * 0.12);
    gain.gain.exponentialRampToValueAtTime(0.55, t + i * 0.12 + 0.02);
    gain.gain.exponentialRampToValueAtTime(0.0001, t + i * 0.12 + 0.2);
    osc.connect(gain);
    gain.connect(audioCtx.destination);
    osc.start(t + i * 0.12);
    osc.stop(t + i * 0.12 + 0.22);
  });
}

export function closeIncomingRideAudio(): void {
  if (!sharedCtx) return;
  void sharedCtx.close().catch(() => {});
  sharedCtx = null;
}
