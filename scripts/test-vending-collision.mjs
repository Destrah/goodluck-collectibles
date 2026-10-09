// Reproduce Sollumz exports losing the tow collision filters on either model.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import zlib from 'node:zlib';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';

const root = path.resolve(import.meta.dirname, '..');
const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'collectibles-collision-test-'));
const script = path.join(root, 'scripts/fix-vending-collision.mjs');
const files = [];
try {
  for (const name of ['metacomics_vending_machine', 'metacomics_vending_body']) {
    const resource = fs.readFileSync(path.join(root, 'fivem/stream', `${name}.ydr`));
    const data = zlib.inflateRawSync(resource.subarray(16));
    const pointer = at => Number(data.readBigUInt64LE(at)) - 0x50000000;
    const bound = pointer(0xc8);
    const allowed = new Set();
    for (const field of [0x90, 0x98]) {
      const flags = pointer(bound + field);
      data.writeUInt32LE(data.readUInt32LE(flags) & ~0x2000, flags);
      data.writeUInt32LE(data.readUInt32LE(flags + 4) & ~0x3e, flags + 4);
      for (let byte = flags; byte < flags + 8; byte++) allowed.add(byte);
    }
    const file = path.join(directory, `${name}.ydr`);
    const broken = Buffer.concat([resource.subarray(0, 16), zlib.deflateRawSync(data)]);
    fs.writeFileSync(file, broken); files.push(file);
    const check = spawnSync(process.execPath, [script, '--check', file]);
    assert.notEqual(check.status, 0, 'Check must reject newly exported missing filters');
    assert.deepEqual(fs.readFileSync(file), broken, 'Check must not modify the asset');
    const fix = spawnSync(process.execPath, [script, file]);
    assert.equal(fix.status, 0, fix.stderr.toString());
    const fixed = fs.readFileSync(file);
    assert.deepEqual(fixed.subarray(0, 16), resource.subarray(0, 16));
    const actual = zlib.inflateRawSync(fixed.subarray(16));
    assert.deepEqual(actual, zlib.inflateRawSync(resource.subarray(16)), 'Repair must restore the known working asset data');
    for (let byte = 0; byte < data.length; byte++) {
      assert.ok(actual[byte] === data[byte] || allowed.has(byte), 'Geometry, textures and box must remain unchanged');
    }
    assert.equal(spawnSync(process.execPath, [script, file]).status, 0);
    assert.deepEqual(fs.readFileSync(file), fixed, 'Repair must be idempotent');
    assert.equal(spawnSync(process.execPath, [script, '--check', file]).status, 0);
  }
  console.log('Both vending models: export regression detected; non-mutating check, flags-only repair and idempotence passed.');
} finally {
  for (const file of files) fs.unlinkSync(file);
  fs.rmdirSync(directory);
}
