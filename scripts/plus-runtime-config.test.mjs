import { test } from 'node:test';
import { verifyPlusRuntimeConfig } from './support/plus-runtime-config.mjs';

test('mainnet AOT keeps the issuer and billing origin that make the card visible', async () => {
  await verifyPlusRuntimeConfig({ MOSH_PLUS_NETWORK: 'solana-mainnet',
    MOSH_PLUS_ISSUER_KEY: 'independent-test-pin',
    MOSH_PLUS_SERVER_URL: 'https://billing.example' });
});

test('an unconfigured AOT proof build keeps Mosh+ disabled', async () => {
  await verifyPlusRuntimeConfig({});
});

test('AOT preserves explicit devnet configuration', async () => {
  await verifyPlusRuntimeConfig({ MOSH_PLUS_NETWORK: 'solana-devnet',
    MOSH_PLUS_ISSUER_KEY: 'devnet-test-pin',
    MOSH_PLUS_SERVER_URL: 'http://127.0.0.1:8787' });
});

test('AOT keeps the store channel the manifest records', async () => {
  await verifyPlusRuntimeConfig({ MOSH_DISTRIBUTION_CHANNEL: 'rustore' });
});
