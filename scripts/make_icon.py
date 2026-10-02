"""Generate Arc's code-native arrow/arc mark; requires Pillow only when changing the icon."""
from pathlib import Path
from PIL import Image, ImageDraw

size = 2048
image = Image.new("RGB", (size, size), "#0C1C37")
draw = ImageDraw.Draw(image)
# An open arc cradles the heading arrow. iOS applies its own icon mask.
draw.arc((360, 340, 1688, 1668), 28, 305, fill="#5B9DFF", width=120)
draw.polygon([(1030, 470), (1380, 1400), (1030, 1180), (680, 1400)], fill="#FFFFFF")
path = Path(__file__).resolve().parents[1] / "Arc/Resources/Assets.xcassets/AppIcon.appiconset/ArcIcon.png"
image.resize((1024, 1024), Image.Resampling.LANCZOS).save(path)
print("Generated Arc app icon.")

