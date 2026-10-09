"""Replace only the exact matching DXT1 mip payload in the shared YTD."""
from pathlib import Path
import zlib

folder = Path(__file__).resolve().parent
root = folder.parents[1]
target = root / 'fivem/stream/metacomics_vending_shared.ytd'
resource = target.read_bytes()
assert resource[:4] == b'RSC7'
raw = zlib.decompress(resource[16:], -15)
old = Path('C:/Users/troyr/Downloads/vending_basecolor_nopacks_2048.dds').read_bytes()[128:]
new = (folder / 'vending_basecolor_nopacks_2048_lock.dds').read_bytes()[128:]
assert len(old) == len(new) == 2796216
if raw.count(new) == 1:
    print('Shared YTD already contains the circular lock texture.')
else:
    assert raw.count(old) == 1, 'Expected one exact matching original texture; no file changed.'
    start = raw.index(old)
    updated = raw[:start] + new + raw[start + len(old):]
    assert len(updated) == len(raw)
    assert updated[:start] == raw[:start] and updated[start + len(old):] == raw[start + len(old):]
    backup = folder / 'metacomics_vending_shared-before-lock.ytd'
    if not backup.exists():
        backup.write_bytes(resource)
    output = resource[:16] + zlib.compress(updated, wbits=-15)
    assert zlib.decompress(output[16:], -15) == updated
    target.write_bytes(output)
    print(f'{target}: updated only the matching texture mip payload; header, names, pointers and other textures preserved.')
