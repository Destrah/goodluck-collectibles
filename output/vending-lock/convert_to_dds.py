"""Convert the edited atlas to the original DXT1 format with all mip levels."""
from pathlib import Path
from io import BytesIO
import struct
import zlib
from PIL import Image, ImageChops

folder = Path(__file__).resolve().parent
source = Image.open(folder / 'vending_basecolor_nopacks_2048_lock.png').convert('RGBA')
original = Image.open('C:/Users/troyr/Downloads/vending_basecolor_nopacks_2048.png').convert('RGBA')
assert source.size == original.size == (2048, 2048)
box = ImageChops.difference(source.convert('RGB'), original.convert('RGB')).getbbox()
assert box and box[0] >= 532 and box[1] >= 343 and box[2] <= 576 and box[3] <= 387, box
chunks = []
level = source
while True:
    buffer = BytesIO()
    level.save(buffer, format='DDS', pixel_format='DXT1')
    encoded = buffer.getvalue()
    if not chunks:
        header = bytearray(encoded[:128])
    chunks.append(encoded[128:])
    if level.size == (1, 1):
        break
    level = level.resize((max(1, level.width // 2), max(1, level.height // 2)), Image.Resampling.LANCZOS)
struct.pack_into('<I', header, 8, struct.unpack_from('<I', header, 8)[0] | 0x20000)
struct.pack_into('<I', header, 20, len(chunks[0]))
struct.pack_into('<I', header, 28, len(chunks))
struct.pack_into('<I', header, 108, 0x1000 | 0x8 | 0x400000)
dds = folder / 'vending_basecolor_nopacks_2048_lock.dds'
dds.write_bytes(header + b''.join(chunks))
assert len(chunks) == 12
assert Image.open(dds).size == source.size
print(f'{dds}: DXT1, 2048x2048, 12 mip levels, {dds.stat().st_size:,} bytes; PNG changes confined to {box}.')

# Read-only check: can the shared dictionary's existing pixels be safely replaced?
root = folder.parents[1]
ytd = root / 'fivem/stream/metacomics_vending_shared.ytd'
raw = zlib.decompress(ytd.read_bytes()[16:], -15)
for path in [Path('C:/Users/troyr/Downloads/vending_basecolor_nopacks_2048.dds'),
             root / 'fivem/stream/metacomics_vending_body/vending_basecolor_2048.dds']:
    payload = path.read_bytes()[128:]
    print(f'Exact existing texture match ({path.name}): {raw.count(payload)}; payload bytes: {len(payload):,}')
