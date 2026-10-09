// CBaseArchetypeDef: https://github.com/dexyfex/CodeWalker/blob/master/CodeWalker.Core/GameFiles/MetaTypes/MetaTypes.cs
// External shader textures require the shared YTD in each prop's archetype, not its old embedded dictionary.
import fs from 'node:fs';
import zlib from 'node:zlib';
import assert from 'node:assert/strict';

export function joaat(name) {
  let value = 0;
  for (const byte of Buffer.from(name.toLowerCase())) {
    value = (value + byte) >>> 0;
    value = (value + (value << 10)) >>> 0;
    value ^= value >>> 6;
  }
  value = (value + (value << 3)) >>> 0;
  value ^= value >>> 11;
  return (value + (value << 15)) >>> 0;
}
export const props = ['metacomics_vending_body', 'metacomics_vending_machine', 'metacomics_vending_door',
  'metacomics_vending_cashlid', 'metacomics_vending_racklid', 'metacomics_card_skimmer'];

export function dictionaryFields(data) {
  return props.map(name => {
    const hash = joaat(name), matches = [];
    // name at +88, dictionary at +92, drawable asset type at +108, asset name at +112.
    for (let at = 88; at + 56 <= data.length; at += 4) {
      if (data.readUInt32LE(at) === hash && data.readUInt32LE(at + 24) === hash
        && data.readUInt32LE(at + 20) === 2) matches.push(at + 4);
    }
    assert.equal(matches.length, 1, `${name}: expected exactly one drawable archetype`);
    return { name, at: matches[0] };
  });
}

export function fix(file, checkOnly = false) {
  const resource = fs.readFileSync(file);
  assert.equal(resource.subarray(0, 4).toString(), 'RSC7');
  const data = zlib.inflateRawSync(resource.subarray(16)), before = Buffer.from(data);
  const expected = joaat('metacomics_vending_shared'), allowed = new Set();
  for (const { name, at } of dictionaryFields(data)) {
    if (checkOnly) assert.equal(data.readUInt32LE(at), expected, `${name}: Texture Dictionary must be metacomics_vending_shared`);
    else data.writeUInt32LE(expected, at);
    for (let byte = at; byte < at + 4; byte++) allowed.add(byte);
  }
  for (let byte = 0; byte < data.length; byte++) assert.ok(data[byte] === before[byte] || allowed.has(byte));
  if (!data.equals(before)) {
    const output = Buffer.concat([resource.subarray(0, 16), zlib.deflateRawSync(data)]);
    assert.deepEqual(zlib.inflateRawSync(output.subarray(16)), data);
    fs.writeFileSync(file, output);
  }
  console.log(`${file}: six shared texture dictionary links verified; slot pack, physics, bounds and other archetype fields preserved.`);
}

// Importing the helpers for regression tests must not modify the working assets.
import { pathToFileURL } from 'node:url';
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  fix(process.argv.slice(2).find(arg => arg !== '--check') || 'fivem/stream/metacomics_props.ytyp', process.argv.includes('--check'));
}
