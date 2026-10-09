import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import zlib from 'node:zlib';
import assert from 'node:assert/strict';
import { dictionaryFields, fix, joaat } from './fix-vending-textures.mjs';

const root = path.resolve(import.meta.dirname, '..');
const resource = fs.readFileSync(path.join(root, 'fivem/stream/metacomics_props.ytyp'));
const original = zlib.inflateRawSync(resource.subarray(16));
const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'collectibles-texture-test-'));
const file = path.join(directory, 'metacomics_props.ytyp');
try {
  const broken = Buffer.from(original);
  const rack = dictionaryFields(broken).find(field => field.name === 'metacomics_vending_racklid');
  broken.writeUInt32LE(joaat(rack.name), rack.at);
  const exported = Buffer.concat([resource.subarray(0, 16), zlib.deflateRawSync(broken)]);
  fs.writeFileSync(file, exported);
  assert.throws(() => fix(file, true), /metacomics_vending_racklid: Texture Dictionary/);
  assert.deepEqual(fs.readFileSync(file), exported, 'Check must not change the exported asset');
  fix(file);
  const fixed = fs.readFileSync(file), actual = zlib.inflateRawSync(fixed.subarray(16));
  assert.deepEqual(fixed.subarray(0, 16), resource.subarray(0, 16));
  assert.deepEqual(actual, original, 'Repair must restore only the incorrect dictionary link');
  for (let byte = 0; byte < broken.length; byte++) {
    assert.ok(actual[byte] === broken[byte] || (byte >= rack.at && byte < rack.at + 4), 'Unrelated archetype data changed');
  }
  fix(file); fix(file, true);
  assert.deepEqual(fs.readFileSync(file), fixed, 'Repeated repair must be idempotent');
  console.log('Shared-YTD regression passed: bad rack link detected, non-mutating check, four-byte repair and idempotence.');
} finally {
  if (fs.existsSync(file)) fs.unlinkSync(file);
  fs.rmdirSync(directory);
}
