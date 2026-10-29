// Store listing texts and screenshots under fastlane/metadata: the limits each
// store enforces at submission, and the rule that every store promises the
// same things without a price.
import assert from 'node:assert/strict';
import { readdir, readFile } from 'node:fs/promises';
import { test } from 'node:test';

const root = new URL('../fastlane/metadata/', import.meta.url);
const locales = ['en-US', 'ru-RU'];
const read = (path) => readFile(new URL(path, root), 'utf8').then((text) => text.trim());
const lines = (text) => text.split('\n').filter(Boolean);
const price = /USDC|CLXAI|[$€₽]|\bprices?\b|\bbuy\b|цен[аы]|купи/i;

/** Width and height from a PNG's IHDR chunk. */
async function pngSize(path) {
  const bytes = await readFile(new URL(path, root));
  assert.equal(bytes.toString('ascii', 1, 4), 'PNG', path);
  return [bytes.readUInt32BE(16), bytes.readUInt32BE(20)];
}

for (const locale of locales) {
  const android = `android/${locale}/`;
  const msstore = `msstore/${locale}/`;

  test(`${locale}: Android texts fit F-Droid and RuStore limits`, async () => {
    // RuStore caps the name at 30 characters, stricter than F-Droid's 50.
    assert.ok((await read(`${android}title.txt`)).length <= 30);
    assert.ok((await read(`${android}short_description.txt`)).length <= 80);
    assert.ok((await read(`${android}full_description.txt`)).length <= 4000);
    for (const file of await readdir(new URL(`${android}changelogs/`, root))) {
      assert.match(file, /^\d+\.txt$/, 'changelogs are named by versionCode');
      assert.ok((await read(`${android}changelogs/${file}`)).length <= 500, file);
    }
  });

  test(`${locale}: Microsoft Store repeats the Android listing`, async () => {
    const full = await read(`${android}full_description.txt`);
    const description = await read(`${msstore}description.txt`);
    assert.ok(description.length <= 10000);
    assert.doesNotMatch(description, /https?:\/\//, 'Partner Center takes links in their own fields');
    for (const paragraph of description.split('\n\n')) assert.ok(full.includes(paragraph), paragraph);
    // Some views show only the first 270 characters of the short description.
    assert.ok((await read(`${msstore}short_description.txt`)).length <= 270);
    const features = lines(await read(`${msstore}features.txt`));
    assert.ok(features.length <= 20);
    for (const feature of features) {
      assert.ok(feature.length <= 200, feature);
      assert.ok(full.includes(`• ${feature}`), `not in the Android list: ${feature}`);
    }
  });

  test(`${locale}: no listing names a price or asks to buy`, async () => {
    for (const path of [
      `${android}short_description.txt`,
      `${android}full_description.txt`,
      `${msstore}short_description.txt`,
      `${msstore}description.txt`,
      `${msstore}features.txt`,
    ]) {
      assert.doesNotMatch(await read(path), price, path);
    }
  });

  test(`${locale}: screenshots have the sizes the stores accept`, async () => {
    const shots = [
      [`${android}images/phoneScreenshots/`, [1080, 1920]],
      [`${msstore}screenshots/`, [1920, 1080]],
    ];
    for (const [folder, size] of shots) {
      const files = await readdir(new URL(folder, root));
      assert.ok(files.length >= 4 && files.length <= 10, folder);
      for (const file of files) assert.deepEqual(await pngSize(folder + file), size, folder + file);
    }
  });
}
