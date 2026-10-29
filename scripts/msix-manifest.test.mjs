import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { test } from 'node:test';
import { msixManifest, msixVersion } from './msix-manifest.mjs';

const template = await readFile(new URL('../windows/msix/AppxManifest.xml', import.meta.url), 'utf8');
const identity = JSON.parse(await readFile(new URL('../windows/msix/identity.json', import.meta.url), 'utf8'));

test('the package version is the pubspec release with a zero revision', () => {
  assert.equal(msixVersion('0.25.1'), '0.25.1.0');
  assert.equal(msixVersion('1.2.3-rc.1'), '1.2.3.0');
  assert.equal(msixVersion('1.2.3+45'), '1.2.3.0');
  for (const version of ['1.2', 'v1.2.3', '1.70000.0']) assert.throws(() => msixVersion(version));
});

test('the manifest carries the Partner Center identity and the version', () => {
  const manifest = msixManifest(template, identity, '0.25.1.0');
  assert.match(manifest, /<Identity Name="redstone\.md\.MoshMessenger"\s+Publisher="CN=C0C4D47C-912F-43D4-8BBF-FE47FBB8F883"\s+Version="0\.25\.1\.0"/);
  assert.match(manifest, /<DisplayName>Mosh Messenger<\/DisplayName>/);
  assert.match(manifest, /<PublisherDisplayName>redstone\.md<\/PublisherDisplayName>/);
  assert.doesNotMatch(manifest, /\{\{/);
});

test('identity values are escaped and an incomplete identity fails the build', () => {
  const manifest = msixManifest(template, { ...identity, publisherDisplayName: 'R & D <x>' }, '1.0.0.0');
  assert.match(manifest, /<PublisherDisplayName>R &amp; D &lt;x&gt;<\/PublisherDisplayName>/);
  for (const broken of [
    { ...identity, name: '' },
    { ...identity, name: 'has space' },
    { ...identity, publisher: 'redstone.md' },
    { ...identity, displayName: undefined },
  ]) assert.throws(() => msixManifest(template, broken, '1.0.0.0'));
});

test('notification clicks reach the activator the app registers', async () => {
  const dart = await readFile(new URL('../lib/src/state/notifications_provider.dart', import.meta.url), 'utf8');
  const guid = dart.match(/_kWindowsGuid = '([0-9a-f-]{36})'/)[1];
  assert.match(template, new RegExp(`ToastActivatorCLSID="${guid}"`));
  assert.match(template, new RegExp(`<com:Class Id="${guid}"`));
});
