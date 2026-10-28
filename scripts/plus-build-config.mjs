import { createHash, createPublicKey } from 'node:crypto';
import { mkdir, writeFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { verifyPlusRuntimeConfig } from './support/plus-runtime-config.mjs';

const CHANNELS = ['github', 'msstore', 'fdroid', 'rustore', 'play', 'appstore'];

/** Public build metadata only; no wallet, issuer secret or billing capabilities. */
export function plusBuildConfig(env) {
  const channel = env.MOSH_DISTRIBUTION_CHANNEL || 'github';
  if (!CHANNELS.includes(channel)) throw new Error('Invalid distribution channel');
  const network = env.MOSH_PLUS_NETWORK || 'solana-mainnet';
  if (!['solana-mainnet', 'solana-devnet'].includes(network)) throw new Error('Invalid PLUS network');
  const pin = env.MOSH_PLUS_ISSUER_KEY || '';
  const server = env.MOSH_PLUS_SERVER_URL || '';
  if (server && !pin) throw new Error('PLUS billing requires an independent issuer pin');
  if (server) {
    const url = new URL(server);
    const loopback = ['localhost', '127.0.0.1', '[::1]'].includes(url.hostname);
    if (!(url.protocol === 'https:' || url.protocol === 'http:' && loopback) ||
        url.username || url.password || url.search || url.hash || url.pathname !== '/') {
      throw new Error('PLUS billing requires an HTTPS origin (HTTP only on loopback)');
    }
  }
  if (pin) {
    const bytes = Buffer.from(pin, 'base64');
    if (bytes.toString('base64') !== pin) throw new Error('Invalid PLUS public SPKI base64');
    const key = createPublicKey({ key: bytes, format: 'der', type: 'spki' });
    const bits = key.asymmetricKeyDetails?.modulusLength ?? 0;
    if (key.asymmetricKeyType !== 'rsa' || bits < 2048 || bits > 4096) throw new Error('Invalid PLUS RSA issuer');
  }
  return { version: 1, commit: env.GITHUB_SHA || null, channel, network,
    verification_enabled: Boolean(pin), purchases_configured: Boolean(pin && server),
    billing_origin: server || null,
    issuer_key_id: pin ? createHash('sha256').update(pin).digest('hex') : null };
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  const manifest = plusBuildConfig(process.env);
  const path = process.argv[2];
  if (!path) throw new Error('Usage: node scripts/plus-build-config.mjs <manifest.json>');
  await verifyPlusRuntimeConfig(process.env);
  await mkdir(dirname(path), { recursive: true });
  await writeFile(path, JSON.stringify(manifest, null, 2) + '\n');
  process.stdout.write(`PLUS: ${manifest.channel}, ${manifest.network}, purchases configured: ${manifest.purchases_configured}; AOT configuration verified\n`);
}
