/**
 * Load backend/.env then repo .env.local (local overrides win).
 * Import first in backend maintenance scripts.
 */
import dotenv from 'dotenv';
import { dirname, join } from 'path';
import { fileURLToPath } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));
export const backendRoot = join(__dirname, '..');
export const repoRoot = join(backendRoot, '..');

dotenv.config({ path: join(backendRoot, '.env') });
dotenv.config({ path: join(repoRoot, '.env.local'), override: true });
