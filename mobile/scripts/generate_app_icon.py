#!/usr/bin/env python3
"""Generate modern squircle app icons from BytzGo rider branding source."""
from __future__ import annotations

import math
import shutil
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
REPO = ROOT.parent
DEFAULT_SOURCE = (
    REPO.parent
    / ".cursor"
    / "projects"
    / "c-Users-user-projectgo-byzgo"
    / "assets"
    / "c__Users_user_AppData_Roaming_Cursor_User_workspaceStorage_60f20d5f5b5927dcad8078937328cdc3_images_ChatGPT_Image_May_19__2026__06_00_55_PM-3f73a8d2-ceee-4c0a-adfb-30f535791cb8.png"
)

# Fallback if run from repo with copied asset
LOCAL_SOURCE = ROOT / "assets" / "branding" / "app_icon_source.png"

ANDROID_SIZES = {
    "mipmap-mdpi": 48,
    "mipmap-hdpi": 72,
    "mipmap-xhdpi": 96,
    "mipmap-xxhdpi": 144,
    "mipmap-xxxhdpi": 192,
}

ADAPTIVE_SIZES = {
    "mipmap-mdpi": 108,
    "mipmap-hdpi": 162,
    "mipmap-xhdpi": 216,
    "mipmap-xxhdpi": 324,
    "mipmap-xxxhdpi": 432,
}

WEB_SIZES = {
    "favicon.png": 32,
    "icons/Icon-192.png": 192,
    "icons/Icon-512.png": 512,
    "icons/Icon-maskable-192.png": 192,
    "icons/Icon-maskable-512.png": 512,
}


def squircle_mask(size: int, corner_ratio: float = 0.22) -> Image.Image:
    """Smooth rounded-rect mask (iOS-style squircle approximation)."""
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    radius = int(size * corner_ratio)
    draw.rounded_rectangle((0, 0, size - 1, size - 1), radius=radius, fill=255)
    # Soften edges slightly for a more premium look
    return mask.filter(ImageFilter.GaussianBlur(radius=max(1, size // 256)))


def superellipse_alpha(size: int, n: float = 4.8, inset: float = 0.04) -> Image.Image:
    """True squircle alpha mask via superellipse."""
    mask = Image.new("L", (size, size), 0)
    cx = cy = (size - 1) / 2
    a = b = (size / 2) * (1 - inset)
    pixels = mask.load()
    for y in range(size):
        for x in range(size):
            nx = abs(x - cx) / a
            ny = abs(y - cy) / b
            if (nx**n + ny**n) <= 1:
                pixels[x, y] = 255
    return mask.filter(ImageFilter.GaussianBlur(radius=max(1, size // 384)))


def load_source(path: Path) -> Image.Image:
    img = Image.open(path).convert("RGBA")
    # Center-crop to square
    w, h = img.size
    side = min(w, h)
    left = (w - side) // 2
    top = (h - side) // 2
    img = img.crop((left, top, left + side, top + side))
    return img


def build_icon(source: Image.Image, size: int, *, padding: float = 0.06) -> Image.Image:
    """Resize with padding inside a squircle clip."""
    canvas = Image.new("RGBA", (size, size), (255, 255, 255, 0))
    inner = int(size * (1 - padding * 2))
    resized = source.resize((inner, inner), Image.Resampling.LANCZOS)
    offset = (size - inner) // 2
    layer = Image.new("RGBA", (size, size), (255, 255, 255, 255))
    layer.paste(resized, (offset, offset), resized)
    mask = superellipse_alpha(size, n=4.6, inset=0.02)
    layer.putalpha(mask)
    # Subtle lift shadow
    shadow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    sh_draw = ImageDraw.Draw(shadow)
    sh_draw.rounded_rectangle(
        (size // 12, size // 10, size - size // 14, size - size // 14),
        radius=int(size * 0.2),
        fill=(0, 0, 0, 28),
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(radius=max(2, size // 48)))
    out = Image.alpha_composite(shadow, layer)
    return out


def build_adaptive_foreground(source: Image.Image, size: int) -> Image.Image:
    """Android adaptive foreground — logo in safe zone on transparent bg."""
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    inner = int(size * 0.62)
    resized = source.resize((inner, inner), Image.Resampling.LANCZOS)
    offset = (size - inner) // 2
    canvas.paste(resized, (offset, offset), resized)
    return canvas


def save_png(img: Image.Image, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if img.mode == "RGBA":
        img.save(path, "PNG", optimize=True)
    else:
        img.convert("RGB").save(path, "PNG", optimize=True)


def main() -> int:
    source_path = LOCAL_SOURCE if LOCAL_SOURCE.exists() else DEFAULT_SOURCE
    if len(sys.argv) > 1:
        source_path = Path(sys.argv[1])

    if not source_path.exists():
        print(f"Source not found: {source_path}", file=sys.stderr)
        return 1

    branding = ROOT / "assets" / "branding"
    branding.mkdir(parents=True, exist_ok=True)
    dest_source = branding / "app_icon_source.png"
    if source_path.resolve() != dest_source.resolve():
        shutil.copy2(source_path, dest_source)

    src = load_source(source_path)
    master = build_icon(src, 1024, padding=0.05)
    save_png(master, branding / "app_icon.png")

    res = ROOT / "android" / "app" / "src" / "main" / "res"
    for folder, px in ANDROID_SIZES.items():
        icon = build_icon(src, px, padding=0.05)
        save_png(icon, res / folder / "ic_launcher.png")

    for folder, px in ADAPTIVE_SIZES.items():
        fg = build_adaptive_foreground(src, px)
        save_png(fg, res / folder / "ic_launcher_foreground.png")

    anydpi = res / "mipmap-anydpi-v26"
    anydpi.mkdir(parents=True, exist_ok=True)
    (anydpi / "ic_launcher.xml").write_text(
        """<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background"/>
    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>
</adaptive-icon>
""",
        encoding="utf-8",
    )
    (anydpi / "ic_launcher_round.xml").write_text(
        (anydpi / "ic_launcher.xml").read_text(encoding="utf-8"),
        encoding="utf-8",
    )

    values = res / "values"
    values.mkdir(parents=True, exist_ok=True)
    colors_file = values / "colors.xml"
    colors_xml = """<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="ic_launcher_background">#FFFFFF</color>
</resources>
"""
    colors_file.write_text(colors_xml, encoding="utf-8")

    web = ROOT / "web"
    for rel, px in WEB_SIZES.items():
        if "maskable" in rel:
            icon = build_adaptive_foreground(src, px)
        else:
            icon = build_icon(src, px, padding=0.05)
        save_png(icon, web / rel)

    # Web app + map marker assets in repo root
    public = REPO / "public"
    if public.exists():
        marker = build_icon(src, 96, padding=0.08)
        save_png(marker, public / "rider-icon.png")
        save_png(build_icon(src, 192, padding=0.05), public / "bytzgo-icon-192.png")

    print(f"Generated icons from {source_path}")
    print(f"  Master: {branding / 'app_icon.png'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
