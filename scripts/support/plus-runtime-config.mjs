import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { mkdtemp, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { promisify } from 'node:util';

const run = promisify(execFile);
const config = new URL('../../lib/src/features/plus/plus_config.dart', import.meta.url);
const channelSource = new URL('../../lib/src/app/distribution_channel.dart', import.meta.url);
const dart = process.env.FLUTTER_ROOT
  ? join(process.env.FLUTTER_ROOT, 'bin', 'cache', 'dart-sdk', 'bin',
    process.platform === 'win32' ? 'dart.exe' : 'dart')
  : 'dart';

/** Verify the same configuration factories Flutter uses, after AOT compilation. */
export async function verifyPlusRuntimeConfig(env) {
  const directory = await mkdtemp(join(tmpdir(), 'mosh-plus-config-'));
  try {
    const source = join(directory, 'main.dart');
    const executable = join(directory, process.platform === 'win32' ? 'probe.exe' : 'probe');
    await writeFile(source, `
import 'dart:convert';
import '${config.href}';
import '${channelSource.href}';
void main() {
  final config = PlusConfig.fromEnvironment();
  print(jsonEncode({'issuerKey': config.issuerKey, 'serverUrl': config.serverUrl,
    'mainnet': config.mainnet, 'enabled': config.enabled, 'canPurchase': config.canPurchase,
    'channel': DistributionChannel.fromEnvironment().name}));
}
`);
    const pin = env.MOSH_PLUS_ISSUER_KEY || '';
    const server = env.MOSH_PLUS_SERVER_URL || '';
    const network = env.MOSH_PLUS_NETWORK || 'solana-mainnet';
    // Passed through as a workflow would, empty when unset.
    const channel = env.MOSH_DISTRIBUTION_CHANNEL || '';
    await run(dart, ['compile', 'exe', `-DMOSH_PLUS_ISSUER_KEY=${pin}`,
      `-DMOSH_PLUS_SERVER_URL=${server}`, `-DMOSH_PLUS_NETWORK=${network}`,
      `-DMOSH_DISTRIBUTION_CHANNEL=${channel}`,
      source, '-o', executable], { timeout: 120000 });
    const { stdout } = await run(executable, [], { timeout: 10000 });
    assert.deepEqual(JSON.parse(stdout), { issuerKey: pin, serverUrl: server,
      mainnet: network === 'solana-mainnet', enabled: Boolean(pin),
      canPurchase: Boolean(pin && server), channel: channel || 'github' },
    'AOT build configuration differs from build inputs');
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
}
