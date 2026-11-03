#!/usr/bin/env python3
"""Generate the Lottery Lab app icon.

The mark is a laboratory flask holding three lottery balls: the app is a
statistics lab for lottery draws, not a prediction tool.

Outputs:
  frontend/android/app/src/main/res/mipmap-*/ic_launcher.png
  frontend/android/app/src/main/res/mipmap-anydpi-v26/ic_launcher*.xml
  frontend/android/app/src/main/res/drawable-*/ic_launcher_foreground.png
  frontend/android/app/src/main/res/drawable-*/ic_launcher_background.png
  frontend/web/icons/*.png, frontend/web/favicon.png
  frontend/windows/runner/resources/app_icon.ico
"""

from __future__ import annotations

import math
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
ANDROID_RES = ROOT / "frontend" / "android" / "app" / "src" / "main" / "res"
WEB = ROOT / "frontend" / "web"
WINDOWS = ROOT / "frontend" / "windows" / "runner" / "resources"

MASTER = 1024
SS = 4  # design coordinates are 0..1024; render at 4096 for smooth edges
CANVAS = MASTER * SS

BG_TOP = (10, 16, 28)
BG_BOTTOM = (22, 38, 60)
GRID = (255, 255, 255, 12)
RIM = (232, 241, 255, 242)
FLASK_FILL = (228, 240, 255, 14)
RED = (255, 91, 96)
BLUE = (77, 155, 255)
AMBER = (255, 194, 75)


def s(value: float) -> int:
    """Scale a MASTER-space coordinate into the supersampled canvas."""
    return int(round(value * SS))


def cubic(p0, p1, p2, p3, steps=48):
    points = []
    for i in range(steps + 1):
        t = i / steps
        u = 1 - t
        x = u**3 * p0[0] + 3 * u**2 * t * p1[0] + 3 * u * t**2 * p2[0] + t**3 * p3[0]
        y = u**3 * p0[1] + 3 * u**2 * t * p1[1] + 3 * u * t**2 * p2[1] + t**3 * p3[1]
        points.append((x, y))
    return points


def flask_path():
    """Conical flask with a flat, rounded bottom and an open neck."""
    pts = [(455, 250), (455, 360)]
    pts += cubic((455, 360), (455, 520), (350, 650), (320, 760))
    pts += cubic((320, 760), (310, 792), (332, 818), (370, 818))
    pts += [(654, 818)]
    pts += cubic((654, 818), (692, 818), (714, 792), (704, 760))
    pts += cubic((704, 760), (674, 650), (574, 520), (574, 360))
    pts += [(574, 250)]
    return [(s(x), s(y)) for x, y in pts]


def radial_glow(canvas_size, center, radius, color):
    """Soft circular glow; cheap enough at icon sizes."""
    layer = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))
    mask = Image.new("L", (256, 256), 0)
    px = mask.load()
    for y in range(256):
        for x in range(256):
            dx = (x - 127.5) / 127.5
            dy = (y - 127.5) / 127.5
            d = math.hypot(dx, dy)
            if d < 1:
                px[x, y] = int(255 * (1 - d) ** 2)
    mask = mask.resize((radius * 2, radius * 2), Image.LANCZOS)
    solid = Image.new("RGBA", (radius * 2, radius * 2), color)
    layer.paste(solid, (center[0] - radius, center[1] - radius), mask)
    return layer


def background(size=CANVAS):
    gradient = Image.new("RGB", (1, size))
    for y in range(size):
        t = y / max(1, size - 1)
        color = tuple(
            int(BG_TOP[i] * (1 - t) + BG_BOTTOM[i] * t) for i in range(3)
        )
        gradient.putpixel((0, y), color)
    image = gradient.resize((size, size), Image.BILINEAR).convert("RGBA")

    # Faint graph-paper grid: analysis, not decoration.
    grid = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(grid)
    step = s(128)
    for pos in range(step, size, step):
        draw.line([(pos, 0), (pos, size)], fill=GRID, width=max(1, s(1.5)))
        draw.line([(0, pos), (size, pos)], fill=GRID, width=max(1, s(1.5)))
    image = Image.alpha_composite(image, grid)

    glow = radial_glow(size, (size // 2, int(size * 0.55)), int(size * 0.42), (255, 180, 70, 30))
    image = Image.alpha_composite(image, glow)

    # Darken the edges a little so the mark pops.
    vignette = radial_glow(size, (size // 2, size // 2), int(size * 0.72), (0, 0, 0, 55))
    inverted = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    inverted.paste((0, 0, 0, 55), (0, 0, size, size), vignette.split()[3].point(lambda v: 255 - v))
    image = Image.alpha_composite(image, inverted)
    return image


def draw_flask(draw):
    path = flask_path()
    draw.polygon(path, fill=FLASK_FILL)
    draw.line(path + [path[0]], fill=RIM, width=s(34), joint="curve")

    # Neck rim: an open lip, drawn as a thick bar with round ends.
    draw.line(
        [(s(432), s(252)), (s(597), s(252))],
        fill=RIM,
        width=s(38),
    )
    for cx in (432, 597):
        draw.ellipse(
            [s(cx - 19), s(252 - 19), s(cx + 19), s(252 + 19)],
            fill=RIM,
        )


def draw_ball(draw, cx, cy, r, color):
    draw.ellipse(
        [s(cx - r - 5), s(cy - r - 3), s(cx + r + 5), s(cy + r + 7)],
        fill=(0, 0, 0, 80),
    )
    draw.ellipse([s(cx - r), s(cy - r), s(cx + r), s(cy + r)], fill=color)
    draw.ellipse(
        [s(cx - r * 0.58), s(cy - r * 0.62), s(cx - r * 0.02), s(cy - r * 0.06)],
        fill=(255, 255, 255, 155),
    )
    draw.arc(
        [s(cx - r * 0.86), s(cy - r * 0.86), s(cx + r * 0.86), s(cy + r * 0.86)],
        start=200,
        end=340,
        fill=(255, 255, 255, 55),
        width=s(5),
    )


def draw_sparkle(draw, cx, cy, size, color):
    points = [
        (cx, cy - size),
        (cx + size * 0.22, cy - size * 0.22),
        (cx + size, cy),
        (cx + size * 0.22, cy + size * 0.22),
        (cx, cy + size),
        (cx - size * 0.22, cy + size * 0.22),
        (cx - size, cy),
        (cx - size * 0.22, cy - size * 0.22),
    ]
    draw.polygon([(s(x), s(y)) for x, y in points], fill=color)


def foreground(size=CANVAS, scale=1.0):
    layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)

    glow = radial_glow(size, (size // 2, int(size * 0.57)), int(size * 0.30), (255, 196, 92, 38))
    layer = Image.alpha_composite(layer, glow)
    draw = ImageDraw.Draw(layer)

    draw_flask(draw)
    draw_ball(draw, 430, 648, 80, RED)
    draw_ball(draw, 598, 648, 80, BLUE)
    draw_ball(draw, 514, 738, 66, AMBER)

    for cx, cy, r, alpha in (
        (392, 520, 13, 70),
        (622, 528, 10, 62),
        (520, 468, 8, 55),
        (352, 700, 9, 45),
    ):
        draw.ellipse(
            [s(cx - r), s(cy - r), s(cx + r), s(cy + r)],
            outline=(230, 242, 255, alpha),
            width=s(3),
        )

    draw_sparkle(draw, 724, 326, 30, (255, 222, 148, 225))
    draw_sparkle(draw, 676, 268, 15, (255, 230, 170, 180))

    if scale != 1.0:
        inner = int(size * scale)
        resized = layer.resize((inner, inner), Image.LANCZOS)
        layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        offset = (size - inner) // 2
        layer.paste(resized, (offset, offset), resized)
    return layer


def legacy_icon(size=MASTER):
    """Rounded-square legacy launcher icon."""
    bg = background(CANVAS)
    fg = foreground(CANVAS)
    image = Image.alpha_composite(bg, fg)

    mask = Image.new("L", (CANVAS, CANVAS), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [0, 0, CANVAS - 1, CANVAS - 1], radius=int(CANVAS * 0.225), fill=255
    )
    image.putalpha(mask)

    border = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    ImageDraw.Draw(border).rounded_rectangle(
        [s(4), s(4), CANVAS - s(4), CANVAS - s(4)],
        radius=int(CANVAS * 0.22),
        outline=(255, 255, 255, 34),
        width=s(5),
    )
    image = Image.alpha_composite(image, border)
    return image.resize((size, size), Image.LANCZOS)


def rounded(size, image, radius_ratio=0.225):
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [0, 0, size - 1, size - 1], radius=int(size * radius_ratio), fill=255
    )
    out = image.copy()
    out.putalpha(mask)
    return out


def save_png(image: Image.Image, path: Path, size: int):
    path.parent.mkdir(parents=True, exist_ok=True)
    image.resize((size, size), Image.LANCZOS).save(path, "PNG", optimize=True)


def main():
    legacy = legacy_icon()
    adaptive_bg = background(CANVAS).resize((MASTER, MASTER), Image.LANCZOS)
    adaptive_fg = foreground(CANVAS, scale=0.88)

    # Android legacy icons.
    densities = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
    for name, px in densities.items():
        save_png(legacy, ANDROID_RES / f"mipmap-{name}" / "ic_launcher.png", px)
        save_png(legacy, ANDROID_RES / f"mipmap-{name}" / "ic_launcher_round.png", px)

    # Adaptive foreground/background (108dp canvas).
    adaptive_densities = {"mdpi": 108, "hdpi": 162, "xhdpi": 216, "xxhdpi": 324, "xxxhdpi": 432}
    for name, px in adaptive_densities.items():
        save_png(adaptive_fg, ANDROID_RES / f"drawable-{name}" / "ic_launcher_foreground.png", px)
        save_png(adaptive_bg, ANDROID_RES / f"drawable-{name}" / "ic_launcher_background.png", px)

    anydpi = ANDROID_RES / "mipmap-anydpi-v26"
    anydpi.mkdir(parents=True, exist_ok=True)
    adaptive_xml = """<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@drawable/ic_launcher_background" />
    <foreground android:drawable="@drawable/ic_launcher_foreground" />
</adaptive-icon>
"""
    (anydpi / "ic_launcher.xml").write_text(adaptive_xml, encoding="utf-8")
    (anydpi / "ic_launcher_round.xml").write_text(adaptive_xml, encoding="utf-8")

    colors = ANDROID_RES / "values" / "colors.xml"
    colors.parent.mkdir(parents=True, exist_ok=True)
    colors.write_text(
        """<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="ic_launcher_background">#0A101C</color>
</resources>
""",
        encoding="utf-8",
    )

    # Web icons (maskable variants keep the mark inside the safe circle).
    save_png(legacy, WEB / "icons" / "Icon-192.png", 192)
    save_png(legacy, WEB / "icons" / "Icon-512.png", 512)
    maskable = legacy_icon()
    maskable = maskable.resize((int(MASTER * 0.8), int(MASTER * 0.8)), Image.LANCZOS)
    canvas = Image.new("RGBA", (MASTER, MASTER), (10, 16, 28, 255))
    offset = (MASTER - maskable.width) // 2
    canvas.paste(maskable, (offset, offset), maskable)
    save_png(canvas, WEB / "icons" / "Icon-maskable-192.png", 192)
    save_png(canvas, WEB / "icons" / "Icon-maskable-512.png", 512)
    save_png(legacy, WEB / "favicon.png", 32)

    # Windows .ico (multi-resolution).
    WINDOWS.mkdir(parents=True, exist_ok=True)
    legacy.save(
        WINDOWS / "app_icon.ico",
        format="ICO",
        sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)],
    )

    print("icons written")
    print(f"  android: {ANDROID_RES.relative_to(ROOT)}")
    print(f"  web:     {(WEB / 'icons').relative_to(ROOT)}")
    print(f"  windows: {(WINDOWS / 'app_icon.ico').relative_to(ROOT)}")


if __name__ == "__main__":
    main()
