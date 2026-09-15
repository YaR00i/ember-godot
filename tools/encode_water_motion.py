"""Encode native rendered water frames as a GIF with one shared palette."""
import argparse
from pathlib import Path
from PIL import Image

parser = argparse.ArgumentParser()
parser.add_argument("directory", type=Path)
args = parser.parse_args()
paths = sorted(args.directory.glob("motion-*.png"))
assert len(paths) == 48, f"expected 48 native frames, got {len(paths)}"
frames = [Image.open(path).convert("RGB") for path in paths]
palette = frames[0].quantize(colors=256)
indexed = [frame.quantize(palette=palette, dither=Image.Dither.NONE) for frame in frames]
output = args.directory / "water-motion.gif"
indexed[0].save(output, save_all=True, append_images=indexed[1:], duration=83, loop=0, optimize=False)
assert len({frame.tobytes() for frame in indexed}) > 1, "motion frames are identical"
print(f"PASS motion GIF: {len(paths)} actual native frames, 12 fps, shared palette; {output}")
