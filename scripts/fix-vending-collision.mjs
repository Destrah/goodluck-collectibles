// CodeWalker Drawable/BoundComposite layout:
// https://github.com/dexyfex/CodeWalker/blob/master/CodeWalker.Core/GameFiles/Resources/Bounds.cs
// Retain the original collision box; enable object/world collision in both filters.
import fs from 'node:fs';
import zlib from 'node:zlib';
import assert from 'node:assert/strict';

const file = process.argv[2] || 'fivem/stream/metacomics_vending_machine.ydr';
const resource = fs.readFileSync(file);
assert.equal(resource.subarray(0, 4).toString(), 'RSC7');
const data = zlib.inflateRawSync(resource.subarray(16));
const offset = (pointer) => {
  const result = Number(pointer) - 0x50000000;
  assert.ok(result >= 0 && result + 8 <= data.length, 'Invalid system pointer');
  return result;
};
const root = offset(data.readBigUInt64LE(0xc8));
assert.equal(data[root + 0x10], 10, 'Expected composite collision');
assert.equal(data.readUInt16LE(root + 0xa0), 1, 'Expected one collision box');
const children = offset(data.readBigUInt64LE(root + 0x70));
assert.equal(data[offset(data.readBigUInt64LE(children)) + 0x10], 3, 'Expected box collision');
const before = Buffer.from(data);
const changed = new Set();
for (const field of [0x90, 0x98]) {
  const flags = offset(data.readBigUInt64LE(root + field));
  // Flags1: this bound participates as an OBJECT as well as a map object.
  // Flags2: accept map/world contacts as well as vehicles, peds and objects.
  data.writeUInt32LE(data.readUInt32LE(flags) | 0x2000, flags);
  data.writeUInt32LE(data.readUInt32LE(flags + 4) | 0x3e, flags + 4);
  for (let i = flags; i < flags + 8; i++) changed.add(i);
}
for (let i = 0; i < data.length; i++) {
  assert.ok(data[i] === before[i] || changed.has(i), 'Changed data outside collision filters');
}
assert.equal(data.length, before.length);
const output = Buffer.concat([resource.subarray(0, 16), zlib.deflateRawSync(data)]);
assert.deepEqual(zlib.inflateRawSync(output.subarray(16)), data);
if (!data.equals(before)) fs.writeFileSync(file, output);
console.log('Vending collision filters verified; geometry, textures and resource header preserved.');
