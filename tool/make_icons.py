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

The tray icons are drawn here: a monochrome template for the macOS menu
bar (assets/tray/tray_icon_macos.png: a terminal window with cat ears and
a ">_" cut out; macOS tints it) and the app icon for the Windows
notification area (assets/tray/tray_icon.ico).

Needs Pillow (pip install pillow).
"""

from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
APP_SOURCE = ROOT / "design" / "app-icon-source.png"
SIDEBAR_SOURCE = ROOT / "design" / "sidebar-logo-source.png"
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


def tray_template(size: int = 44) -> Image.Image:
    """Black-on-transparent menu bar icon (macOS colours template images).

    Drawn at 8x and scaled down for smooth edges; 44px = 22pt @2x.
    """
    s = 8
    n = size * s
    img = Image.new("L", (n, n), 0)
    d = ImageDraw.Draw(img)
    u = n / 22  # one unit of a 22-unit grid

    # Cat ears.
    d.polygon([(4 * u, 8 * u), (5.2 * u, 1.8 * u), (9.4 * u, 6 * u)], fill=255)
    d.polygon([(18 * u, 8 * u), (16.8 * u, 1.8 * u), (12.6 * u, 6 * u)], fill=255)
    # Terminal window body.
    d.rounded_rectangle([2.2 * u, 5.2 * u, 19.8 * u, 19.8 * u], radius=3.4 * u, fill=255)
    # ">_" cut out of it.
    w = 1.7 * u
    d.line([(6.2 * u, 9.6 * u), (9.4 * u, 12.4 * u), (6.2 * u, 15.2 * u)], fill=0, width=int(w), joint="curve")
    d.line([(11.2 * u, 15.6 * u), (15.6 * u, 15.6 * u)], fill=0, width=int(w))

    alpha = img.resize((size, size), Image.LANCZOS)
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    out.putalpha(alpha)
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
