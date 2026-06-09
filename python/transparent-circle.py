# Example snippet: apply a circular alpha mask with Pillow (not a CLI script).
from __future__ import annotations

from pathlib import Path


def apply_circular_mask(input_path: Path, output_path: Path) -> None:
    from PIL import Image, ImageDraw

    image = Image.open(input_path).convert("RGBA")
    alpha_mask = Image.new("L", image.size, 0)
    draw = ImageDraw.Draw(alpha_mask)
    draw.ellipse([2, 2, min(image.size) - 2, min(image.size) - 2], fill=255)
    image.putalpha(alpha_mask)
    image.save(output_path)


if __name__ == "__main__":
    apply_circular_mask(Path("filename.jpg"), Path("output.png"))
