# Example snippet: apply a circular alpha mask with Pillow (not a CLI script).
from PIL import Image, ImageDraw

image = Image.open("filename.jpg").convert("RGBA")

alpha_mask = Image.new("L", image.size, 0)
draw = ImageDraw.Draw(alpha_mask)
draw.ellipse([2, 2, 700, 700], fill=255)

image.putalpha(alpha_mask)
image.save("output.png")
