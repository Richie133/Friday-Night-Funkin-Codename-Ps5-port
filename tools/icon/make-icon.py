"""Draws sce_sys/icon0.png (512x512): four note arrows on a purple field.

An original picture for the port (no Codename Engine or Friday Night Funkin'
artwork in it). Run: python3 tools/icon/make-icon.py
"""
import math
import os
import sys

from PIL import Image, ImageDraw, ImageFont

SIZE = 512
SCALE = 4  # drawn large, then scaled down for smooth edges
root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(root, "sce_sys", "icon0.png")

S = SIZE * SCALE
img = Image.new("RGB", (S, S))
px = img.load()
# vertical gradient
top, bottom = (38, 14, 74), (12, 6, 28)
d = ImageDraw.Draw(img)
for y in range(S):
    t = y / (S - 1)
    c = tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3))
    d.line([(0, y), (S, y)], fill=c)

# soft rings
for r, alpha in ((S * 0.62, 40), (S * 0.48, 30)):
    ring = Image.new("L", (S, S), 0)
    ImageDraw.Draw(ring).ellipse([S / 2 - r, S * 0.42 - r, S / 2 + r, S * 0.42 + r], outline=alpha, width=S // 60)
    img.paste((160, 110, 255), (0, 0), ring)

def arrow(cx, cy, size, angle, fill):
    # an arrow pointing up, rotated by angle (degrees, clockwise)
    pts = [(0, -1.0), (0.95, -0.05), (0.42, -0.05), (0.42, 0.9), (-0.42, 0.9), (-0.42, -0.05), (-0.95, -0.05)]
    a = math.radians(angle)
    out = []
    for x, y in pts:
        rx = x * math.cos(a) - y * math.sin(a)
        ry = x * math.sin(a) + y * math.cos(a)
        out.append((cx + rx * size, cy + ry * size))
    d.polygon(out, fill=(0, 0, 0))
    inner = [(cx + (p[0] - cx) * 0.8, cy + (p[1] - cy) * 0.8) for p in out]
    # outline: black polygon, then the colour a little smaller
    shrink = [(cx + (p[0] - cx) * 0.86, cy + (p[1] - cy) * 0.86) for p in out]
    d.polygon(shrink, fill=fill)
    d.polygon(inner, fill=tuple(min(255, int(v * 1.18) + 20) for v in fill))

colors = [(194, 75, 153), (0, 255, 255), (18, 250, 5), (249, 57, 63)]
angles = [-90, 180, 0, 90]  # left, down, up, right
spacing = S * 0.215
y = S * 0.40
for i in range(4):
    arrow(S / 2 + (i - 1.5) * spacing, y, S * 0.088, angles[i], colors[i])

def font(size):
    for name in ("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
                 "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf"):
        if os.path.exists(name):
            return ImageFont.truetype(name, size)
    return ImageFont.load_default()

def centered(text, cy, size, fill):
    f = font(size)
    w = d.textlength(text, font=f)
    d.text(((S - w) / 2 + S * 0.004, cy + S * 0.004), text, font=f, fill=(0, 0, 0))
    d.text(((S - w) / 2, cy), text, font=f, fill=fill)

centered("CODENAME", S * 0.60, int(S * 0.115), (255, 255, 255))
centered("ENGINE", S * 0.725, int(S * 0.085), (210, 190, 255))
centered("unofficial PS5 port", S * 0.86, int(S * 0.05), (170, 150, 220))

img = img.resize((SIZE, SIZE), Image.LANCZOS)
img.save(out, optimize=True)
print(out)
