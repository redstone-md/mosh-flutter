import assert from 'node:assert/strict';
import { generateKeyPairSync } from 'node:crypto';
import { test } from 'node:test';
import { plusBuildConfig } from './plus-build-config.mjs';

const pin = generateKeyPairSync('rsa', { modulusLength: 2048 }).publicKey
  .export({ format: 'der', type: 'spki' }).toString('base64');

test('ordinary proof builds keep purchases disabled, configured builds preserve the explicit network', () => {
  assert.equal(plusBuildConfig({}).purchases_configured, false);
  for (const network of ['solana-mainnet', 'solana-devnet']) {
    const result = plusBuildConfig({ MOSH_PLUS_NETWORK: network, MOSH_PLUS_ISSUER_KEY: pin,
      MOSH_PLUS_SERVER_URL: 'https://billing.example', GITHUB_SHA: 'revision' });
    assert.equal(result.network, network);
    assert.equal(result.commit, 'revision');
    assert.equal(result.purchases_configured, true);
    assert.match(result.issuer_key_id, /^[a-f0-9]{64}$/);
  }
});

test('misconfigured builds fail before packaging', () => {
  for (const values of [
    { MOSH_PLUS_NETWORK: 'unknown' },
    { MOSH_PLUS_SERVER_URL: 'https://billing.example' },
    { MOSH_PLUS_ISSUER_KEY: 'invalid' },
    ...['http://billing.example', 'https://name:secret@billing.example',
      'https://billing.example/?secret=x', 'https://billing.example/v2'].map(server =>
      ({ MOSH_PLUS_ISSUER_KEY: pin, MOSH_PLUS_SERVER_URL: server })),
  ]) assert.throws(() => plusBuildConfig(values));
});
