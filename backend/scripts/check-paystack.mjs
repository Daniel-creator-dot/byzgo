import dotenv from 'dotenv';
import path from 'path';
import { fileURLToPath } from 'url';
import axios from 'axios';
import pg from 'pg';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
dotenv.config({ path: path.join(__dirname, '..', '.env') });
dotenv.config({ path: path.join(__dirname, '..', '..', '.env.local') });

const pool = new pg.Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: { rejectUnauthorized: false },
});

const settings = await pool.query(
  `SELECT key, value FROM system_settings WHERE key LIKE 'paystack%'`
);
await pool.end();

const pub =
  settings.rows.find((r) => r.key === 'paystack_public_key')?.value ||
  process.env.PAYSTACK_PUBLIC_KEY ||
  '';
const sec =
  settings.rows.find((r) => r.key === 'paystack_secret_key')?.value ||
  process.env.PAYSTACK_SECRET_KEY ||
  '';

console.log('public:', pub ? `${pub.slice(0, 12)}… (${pub.startsWith('pk_test') ? 'test' : pub.startsWith('pk_live') ? 'live' : 'unknown'})` : 'MISSING');
console.log('secret:', sec ? `${sec.slice(0, 12)}… (${sec.startsWith('sk_test') ? 'test' : sec.startsWith('sk_live') ? 'live' : 'unknown'})` : 'MISSING');

if (!sec) {
  console.log('\nFAIL: No Paystack secret key. Set in Admin → Settings or PAYSTACK_SECRET_KEY.');
  process.exit(1);
}

const pubTest = pub.startsWith('pk_test_');
const pubLive = pub.startsWith('pk_live_');
const secTest = sec.startsWith('sk_test_');
const secLive = sec.startsWith('sk_live_');
if ((pubTest && !secTest) || (pubLive && !secLive)) {
  console.log('\nFAIL: Public and secret keys must both be test or both be live.');
  process.exit(1);
}

try {
  const res = await axios.get('https://api.paystack.co/transaction/verify/invalid-ref-test', {
    headers: { Authorization: `Bearer ${sec}` },
    validateStatus: () => true,
  });
  if (res.status === 401) {
    console.log('\nFAIL: Paystack rejected secret key (401).');
    process.exit(1);
  }
  console.log('\nOK: Paystack API accepts secret key (verify endpoint reachable).');
  console.log('Sample response status:', res.status, res.data?.message || '');
} catch (e) {
  console.log('\nFAIL: Could not reach Paystack:', e.message);
  process.exit(1);
}
