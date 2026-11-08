"""Builds the app icons and the sidebar logo from the files in design/.

    python3 tool/make_icons.py

design/app-icon-source.png (full-bleed square art) becomes the app icon
everywhere the system shows it: Dock, Finder, desktop, Launchpad (macOS
AppIcon) and taskbar, title bar, .exe, shortcuts (Windows app_icon.ico).
It is cut to a rounded square; on macOS it sits on Apple's 1024px grid
(824px artwork, 100px margin) with a soft shadow, so it matches the size
of other Dock icons.

design/sidebar-logo-source.png (art with its own frame, transparent
background) becomes the sidebar logo, assets/branding/logo.png.

design/tray-icon-source.png (a silhouette on a transparent background;
only its shape counts) becomes the macOS menu bar icon,
assets/tray/tray_icon_macos.png: a template image that macOS tints for
light and dark menu bars. The Windows notification area uses the app
icon (assets/tray/tray_icon.ico).

Needs Pillow (pip install pillow).
"""

from pathlib import Path

from PIL import Image, ImageChops, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
APP_SOURCE = ROOT / "design" / "app-icon-source.png"
SIDEBAR_SOURCE = ROOT / "design" / "sidebar-logo-source.png"
TRAY_SOURCE = ROOT / "design" / "tray-icon-source.png"
MAC_DIR = ROOT / "macos" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"
WIN_ICO = ROOT / "windows" / "runner" / "resources" / "app_icon.ico"
SIDEBAR_LOGO = ROOT / "assets" / "branding" / "logo.png"
PREVIEW = ROOT / "design" / "app-icon-macos-1024.png"
TRAY_MAC = ROOT / "assets" / "tray" / "tray_icon_macos.png"
TRAY_WIN = ROOT / "assets" / "tray" / "tray_icon.ico"

CANVAS = 1024
ARTWORK = 824  # Apple icon grid
ICO_SIZES = [(s, s) for s in (16, 24, 32, 48, 64, 128, 256)]


def trimmed_square(img: Image.Image) -> Image.Image:
    """Crop transparent margins, then pad back to a centered square.

    Near-invisible specks (alpha <= 8) don't count as content.
    """
    solid = img.getchannel("A").point(lambda v: 255 if v > 8 else 0)
    crop = img.crop(solid.getbbox())
    side = max(crop.size)
    sq = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    sq.paste(crop, ((side - crop.width) // 2, (side - crop.height) // 2))
    return sq


def squircle_mask(size: int, n: float = 5.0, supersample: int = 4) -> Image.Image:
    """Superellipse |x|^n + |y|^n <= 1: close to Apple's continuous corners."""
    big = size * supersample
    mask = Image.new("L", (big, big), 0)
    px = mask.load()
    r = big / 2
    for y in range(big):
        dy = abs((y + 0.5 - r) / r) ** n
        if dy > 1:
            continue
        half = (1 - dy) ** (1 / n) * r
        for x in range(max(int(r - half), 0), min(int(r + half), big)):
            px[x, y] = 255
    return mask.resize((size, size), Image.LANCZOS)


def rounded(img: Image.Image, size: int) -> Image.Image:
    """Resize a full-bleed square and cut it to a rounded square."""
    out = img.resize((size, size), Image.LANCZOS)
    out.putalpha(ImageChops.multiply(out.getchannel("A"), squircle_mask(size)))
    return out


def on_mac_grid(art: Image.Image) -> Image.Image:
    """Place 824px artwork on a 1024px canvas with a soft drop shadow."""
    offset = (CANVAS - ARTWORK) // 2
    shadow_alpha = Image.new("L", (CANVAS, CANVAS), 0)
    shadow_alpha.paste(art.getchannel("A"), (offset, offset + 12))
    shadow_alpha = shadow_alpha.filter(ImageFilter.GaussianBlur(18))
    shadow_alpha = shadow_alpha.point(lambda v: v * 0.3)
    canvas = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    canvas.putalpha(shadow_alpha)
    canvas.alpha_composite(art, (offset, offset))
    return canvas


def tray_template(size: int = 44, glyph: int = 36) -> Image.Image:
    """Black-on-transparent menu bar icon from the tray source's shape.

    44px = 22pt @2x, the menu bar height; the glyph is 36px (18pt) tall,
    centred, like other menu bar icons. macOS colours template images, so
    only the alpha channel matters.
    """
    shape = trimmed_square(Image.open(TRAY_SOURCE).convert("RGBA"))
    alpha = shape.getchannel("A").resize((glyph, glyph), Image.LANCZOS)
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    mask = Image.new("L", (size, size), 0)
    mask.paste(alpha, ((size - glyph) // 2, (size - glyph) // 2))
    out.putalpha(mask)
    return out


def main() -> None:
    app = Image.open(APP_SOURCE).convert("RGBA")

    mac = on_mac_grid(rounded(app, ARTWORK))
    mac.save(PREVIEW, optimize=True)
    for size in (16, 32, 64, 128, 256, 512, 1024):
        mac.resize((size, size), Image.LANCZOS).save(
            MAC_DIR / f"app_icon_{size}.png", optimize=True
        )
    rounded(app, 256).save(WIN_ICO, sizes=ICO_SIZES)

    sidebar = trimmed_square(Image.open(SIDEBAR_SOURCE).convert("RGBA"))
    sidebar.resize((256, 256), Image.LANCZOS).save(SIDEBAR_LOGO, optimize=True)

    tray_template().save(TRAY_MAC, optimize=True)
    rounded(app, 256).save(TRAY_WIN, sizes=[(s, s) for s in (16, 20, 24, 32, 48)])

    print("tray icons ->", TRAY_MAC.parent.relative_to(ROOT))
    print("macOS app icon ->", MAC_DIR.relative_to(ROOT))
    print("Windows app icon ->", WIN_ICO.relative_to(ROOT))
    print("sidebar logo ->", SIDEBAR_LOGO.relative_to(ROOT))
    print("preview ->", PREVIEW.relative_to(ROOT))


if __name__ == "__main__":
    main()
