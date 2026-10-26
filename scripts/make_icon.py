#!/usr/bin/env python3
import math
import subprocess
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

SIZE = 1024
SCALE = 2
W = SIZE * SCALE
OUT = Path(__file__).resolve().parent.parent / "CameraTuner" / "Resources"
OUT.mkdir(parents=True, exist_ok=True)


def lerp(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def radial(size, center, radius, inner, outer, gamma=1.0):
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32)
    d = np.sqrt((xx - center[0]) ** 2 + (yy - center[1]) ** 2) / radius
    d = np.clip(d, 0, 1) ** gamma
    arr = np.zeros((size, size, 4), dtype=np.uint8)
    for c in range(3):
        arr[..., c] = (inner[c] * (1 - d) + outer[c] * d).astype(np.uint8)
    arr[..., 3] = 255
    return Image.fromarray(arr, "RGBA")


def circle_mask(size, center, radius):
    yy, xx = np.mgrid[0:size, 0:size].astype(np.float32)
    mask = (np.sqrt((xx - center[0]) ** 2 + (yy - center[1]) ** 2) <= radius)
    return Image.fromarray((mask * 255).astype(np.uint8), "L")


def polar(center, radius, degrees):
    a = math.radians(degrees)
    return (center[0] + radius * math.cos(a), center[1] + radius * math.sin(a))


canvas = Image.new("RGBA", (W, W), (0, 0, 0, 0))

margin = int(100 * SCALE)
radius = int(185 * SCALE)
box = (margin, margin, W - margin, W - margin)

shadow = Image.new("RGBA", (W, W), (0, 0, 0, 0))
sd = ImageDraw.Draw(shadow)
sd.rounded_rectangle(
    (box[0], box[1] + int(26 * SCALE), box[2], box[3] + int(26 * SCALE)),
    radius=radius,
    fill=(0, 0, 0, 105),
)
shadow = shadow.filter(ImageFilter.GaussianBlur(38 * SCALE))
canvas = Image.alpha_composite(canvas, shadow)

yy, xx = np.mgrid[0:W, 0:W].astype(np.float32)
gx = xx / W
gy = yy / W
t = np.clip(0.58 * gx + 0.42 * gy, 0, 1)
c0 = np.array([17, 24, 39], dtype=np.float32)
c1 = np.array([30, 27, 75], dtype=np.float32)
bg = c0[None, None, :] * (1 - t[..., None]) + c1[None, None, :] * t[..., None]

teal = np.array([13, 148, 136], dtype=np.float32)
indigo = np.array([79, 70, 229], dtype=np.float32)
for center, color, rad, strength in (
    ((W * 0.18, W * 0.16), teal, W * 0.62, 0.45),
    ((W * 0.86, W * 0.80), indigo, W * 0.55, 0.35),
):
    d = np.sqrt((xx - center[0]) ** 2 + (yy - center[1]) ** 2) / rad
    glow = np.clip(1 - d, 0, 1) ** 2 * strength
    bg = bg + color[None, None, :] * glow[..., None]

arr = np.zeros((W, W, 4), dtype=np.uint8)
arr[..., :3] = np.clip(bg, 0, 255).astype(np.uint8)
arr[..., 3] = 255
gradient = Image.fromarray(arr, "RGBA")

mask = Image.new("L", (W, W), 0)
ImageDraw.Draw(mask).rounded_rectangle(box, radius=radius, fill=255)
canvas.paste(gradient, (0, 0), mask)

border = Image.new("RGBA", (W, W), (0, 0, 0, 0))
bd = ImageDraw.Draw(border)
bd.rounded_rectangle(box, radius=radius, outline=(255, 255, 255, 38), width=3 * SCALE)
bd.rounded_rectangle(
    (box[0] + 5 * SCALE, box[1] + 5 * SCALE, box[2] - 5 * SCALE, box[3] - 5 * SCALE),
    radius=radius - 5 * SCALE,
    outline=(255, 255, 255, 18),
    width=2 * SCALE,
)
canvas = Image.alpha_composite(canvas, border)

cx, cy = W // 2, int(W * 0.445)
ring_radius = int(286 * SCALE)
ring_width = int(24 * SCALE)

arc_layer = Image.new("RGBA", (W, W), (0, 0, 0, 0))
glow_layer = Image.new("RGBA", (W, W), (0, 0, 0, 0))
ad = ImageDraw.Draw(arc_layer)
gd = ImageDraw.Draw(glow_layer)

segments = [
    (210, 315, (244, 63, 94, 255)),
    (326, 70, (34, 197, 94, 255)),
    (81, 195, (59, 130, 246, 255)),
]
for start, end, color in segments:
    bbox = (cx - ring_radius, cy - ring_radius, cx + ring_radius, cy + ring_radius)
    gd.arc(bbox, start=start, end=end, fill=color[:3] + (75,), width=ring_width * 2)
    ad.arc(bbox, start=start, end=end, fill=color, width=ring_width)
    for angle in (start, end):
        p = polar((cx, cy), ring_radius, angle)
        r = ring_width // 2
        gd.ellipse((p[0] - r * 2, p[1] - r * 2, p[0] + r * 2, p[1] + r * 2), fill=color[:3] + (75,))
        ad.ellipse((p[0] - r, p[1] - r, p[0] + r, p[1] + r), fill=color)

glow_layer = glow_layer.filter(ImageFilter.GaussianBlur(18 * SCALE))
canvas = Image.alpha_composite(canvas, glow_layer)
canvas = Image.alpha_composite(canvas, arc_layer)

lens_shadow = Image.new("RGBA", (W, W), (0, 0, 0, 0))
lsd = ImageDraw.Draw(lens_shadow)
lsd.ellipse(
    (cx - 238 * SCALE, cy - 224 * SCALE, cx + 238 * SCALE, cy + 252 * SCALE),
    fill=(0, 0, 0, 100),
)
lens_shadow = lens_shadow.filter(ImageFilter.GaussianBlur(24 * SCALE))
canvas = Image.alpha_composite(canvas, lens_shadow)

layer = Image.new("RGBA", (W, W), (0, 0, 0, 0))
ld = ImageDraw.Draw(layer)
ld.ellipse(
    (cx - 232 * SCALE, cy - 232 * SCALE, cx + 232 * SCALE, cy + 232 * SCALE),
    fill=(7, 11, 22, 255),
)
ld.ellipse(
    (cx - 214 * SCALE, cy - 214 * SCALE, cx + 214 * SCALE, cy + 214 * SCALE),
    fill=(51, 65, 85, 255),
)
ld.ellipse(
    (cx - 194 * SCALE, cy - 194 * SCALE, cx + 194 * SCALE, cy + 194 * SCALE),
    fill=(9, 14, 28, 255),
)
canvas = Image.alpha_composite(canvas, layer)

lens = radial(
    W,
    (cx - 40 * SCALE, cy - 60 * SCALE),
    int(250 * SCALE),
    (14, 116, 144),
    (2, 6, 23),
    gamma=1.5,
)
lens_mask = circle_mask(W, (cx, cy), 190 * SCALE)
canvas.paste(lens, (0, 0), lens_mask)

ring_highlight = Image.new("RGBA", (W, W), (0, 0, 0, 0))
rhd = ImageDraw.Draw(ring_highlight)
rhd.arc(
    (cx - 204 * SCALE, cy - 204 * SCALE, cx + 204 * SCALE, cy + 204 * SCALE),
    start=196,
    end=318,
    fill=(226, 232, 240, 145),
    width=int(9 * SCALE),
)
rhd.arc(
    (cx - 204 * SCALE, cy - 204 * SCALE, cx + 204 * SCALE, cy + 204 * SCALE),
    start=20,
    end=140,
    fill=(2, 6, 23, 150),
    width=int(10 * SCALE),
)
ring_highlight = ring_highlight.filter(ImageFilter.GaussianBlur(2 * SCALE))
canvas = Image.alpha_composite(canvas, ring_highlight)

iris = Image.new("RGBA", (W, W), (0, 0, 0, 0))
idr = ImageDraw.Draw(iris)
outer = [polar((cx, cy), 118 * SCALE, 30 + i * 60) for i in range(6)]
inner = [polar((cx, cy), 54 * SCALE, 30 + i * 60) for i in range(6)]
idr.polygon(outer, outline=(255, 255, 255, 55), width=int(5 * SCALE))
for i in range(6):
    idr.line([inner[i], outer[i]], fill=(255, 255, 255, 38), width=int(4 * SCALE))
idr.ellipse(
    (cx - 28 * SCALE, cy - 28 * SCALE, cx + 28 * SCALE, cy + 28 * SCALE),
    fill=(2, 6, 23, 235),
)
idr.ellipse(
    (cx - 10 * SCALE, cy - 15 * SCALE, cx + 2 * SCALE, cy - 3 * SCALE),
    fill=(165, 243, 252, 190),
)
canvas = Image.alpha_composite(canvas, iris)

highlight = Image.new("RGBA", (W, W), (0, 0, 0, 0))
hd = ImageDraw.Draw(highlight)
hd.arc(
    (cx - 166 * SCALE, cy - 166 * SCALE, cx + 166 * SCALE, cy + 166 * SCALE),
    start=202,
    end=292,
    fill=(255, 255, 255, 92),
    width=int(16 * SCALE),
)
highlight = highlight.filter(ImageFilter.GaussianBlur(7 * SCALE))
canvas = Image.alpha_composite(canvas, highlight)

sparkle = Image.new("RGBA", (W, W), (0, 0, 0, 0))
sp = ImageDraw.Draw(sparkle)
sx, sy = int(W * 0.735), int(W * 0.205)
long, short = int(34 * SCALE), int(9 * SCALE)
sp.polygon(
    [(sx, sy - long), (sx + short, sy - short), (sx + long, sy),
     (sx + short, sy + short), (sx, sy + long), (sx - short, sy + short),
     (sx - long, sy), (sx - short, sy - short)],
    fill=(255, 255, 255, 175),
)
sparkle = sparkle.filter(ImageFilter.GaussianBlur(1 * SCALE))
canvas = Image.alpha_composite(canvas, sparkle)

canvas = canvas.resize((SIZE, SIZE), Image.Resampling.LANCZOS)
png_path = OUT / "AppIcon-1024.png"
canvas.save(png_path)

iconset = OUT / "AppIcon.iconset"
if iconset.exists():
    for path in iconset.iterdir():
        path.unlink()
    iconset.rmdir()
iconset.mkdir()

specs = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png"),
]
for size, name in specs:
    canvas.resize((size, size), Image.Resampling.LANCZOS).save(iconset / name)

icns_path = OUT / "AppIcon.icns"
subprocess.run(["iconutil", "-c", "icns", str(iconset), "-o", str(icns_path)], check=True)
for path in iconset.iterdir():
    path.unlink()
iconset.rmdir()

print(f"Wrote {png_path}")
print(f"Wrote {icns_path}")
