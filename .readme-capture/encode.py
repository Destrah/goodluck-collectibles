from pathlib import Path
from PIL import Image

root = Path(__file__).resolve().parent
out = root.parent / 'docs' / 'media'
out.mkdir(parents=True, exist_ok=True)
for folder in sorted((root / 'frames').iterdir()):
    files = sorted(folder.glob('*.png'))
    if len(files) < 75:
        continue
    # One palette for the whole loop prevents color flicker between frames.
    samples = files[::6]
    sheet = Image.new('RGB', (160 * len(samples), 100))
    for i, file in enumerate(samples):
        with Image.open(file) as image:
            sheet.paste(image.convert('RGB').resize((160, 100)), (i * 160, 0))
    palette = sheet.quantize(colors=256, method=Image.Quantize.MEDIANCUT)
    frames = []
    for file in files:
        with Image.open(file) as image:
            frames.append(image.convert('RGB').quantize(palette=palette, dither=Image.Dither.NONE))
    durations = [100] * len(frames)
    durations[-1] = 1500
    dest = out / f'{folder.name}.gif'
    frames[0].save(dest, save_all=True, append_images=frames[1:], duration=durations, loop=0, optimize=True, disposal=1)
    with Image.open(dest) as gif:
        print(f'{dest.name}: {gif.n_frames} frames, {gif.size}, {dest.stat().st_size / 1024 / 1024:.2f} MB')
