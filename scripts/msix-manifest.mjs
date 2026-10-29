import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

const IDENTITY_FIELDS = ['name', 'publisher', 'publisherDisplayName', 'displayName'];

/** The pubspec release as the four-part version the Store accepts (revision 0). */
export function msixVersion(pubspecVersion) {
  const match = /^(\d+)\.(\d+)\.(\d+)(?:[-+].*)?$/.exec(pubspecVersion);
  const parts = match?.slice(1).map(Number);
  if (!parts || parts.some(part => part > 65535)) throw new Error(`Invalid MSIX version: ${pubspecVersion}`);
  return `${parts.join('.')}.0`;
}

const escapeXml = value => value.replace(/[&<>"']/g, char =>
  ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&apos;' })[char]);

/** Fills the AppxManifest.xml template with the Partner Center identity and the version. */
export function msixManifest(template, identity, version) {
  for (const field of IDENTITY_FIELDS) {
    if (typeof identity[field] !== 'string' || !identity[field]) throw new Error(`MSIX identity needs ${field}`);
  }
  if (!/^[A-Za-z0-9.-]{3,50}$/.test(identity.name)) throw new Error('Invalid MSIX identity name');
  if (!identity.publisher.startsWith('CN=')) throw new Error('MSIX publisher must be a CN= subject');
  const values = { ...identity, version };
  return template.replace(/\{\{(\w+)\}\}/g, (_, key) => {
    if (!(key in values)) throw new Error(`Unknown MSIX placeholder ${key}`);
    return escapeXml(values[key]);
  });
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  const path = process.argv[2];
  if (!path) throw new Error('Usage: node scripts/msix-manifest.mjs <AppxManifest.xml>');
  const root = new URL('../', import.meta.url);
  const read = file => readFile(new URL(file, root), 'utf8');
  const pubspec = (await read('pubspec.yaml')).match(/^version:\s*(\S+)/m)?.[1] ?? '';
  const identity = JSON.parse(await read('windows/msix/identity.json'));
  const version = msixVersion(pubspec);
  await mkdir(dirname(path), { recursive: true });
  await writeFile(path, msixManifest(await read('windows/msix/AppxManifest.xml'), identity, version));
  process.stdout.write(`MSIX: ${identity.name} ${version}\n`);
}
