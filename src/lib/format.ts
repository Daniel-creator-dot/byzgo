/** Ghana cedi display — always use literal ₵ (UTF-8). */
export function formatCedis(amount: number | string | null | undefined, decimals = 2): string {
  const n = Number(amount);
  if (!Number.isFinite(n)) return `₵0.${'0'.repeat(decimals)}`;
  return `₵${n.toFixed(decimals)}`;
}

export function formatCedisCompact(amount: number | string | null | undefined): string {
  const n = Number(amount);
  if (!Number.isFinite(n)) return '₵0';
  if (n >= 1_000_000) return `₵${(n / 1_000_000).toFixed(1)}M`;
  if (n >= 1_000) return `₵${(n / 1_000).toFixed(1)}k`;
  return `₵${n.toFixed(2)}`;
}
