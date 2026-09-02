#!/usr/bin/env python3
"""Protect's Dock icon: deep navy body, champagne swirl.

⚠️ THE FAMILY IS TOLD APART BY THE BODY COLOUR, NOT THE MARK. The swirl is
shared on purpose, so the body is the only thing separating Protect from
Radiant (#5377B3) and AiOS (#857F5E) at 32pt in the Dock.

⚠️ THIS WAS CHAMPAGNE-ON-NAVY UNTIL 2026-09-02, and it was that way because an
earlier navy body read as Radiant. Tony asked for the inversion; what makes it
survivable is the *value* gap — Radiant is a mid periwinkle and this is a near
black navy, so they separate by lightness even where hue does not help. Do not
lighten it toward Radiant's blue. If the two ever start colliding in the Dock
again, the fix is a darker body, not a different mark.

⚠️ THE SWIRL IS LIFTED, NEVER RE-RENDERED. Radiant's icon was once rebuilt by
re-drawing the mark through a blur/threshold pass whose radius scaled with the
output size; the thin inner arcs were eaten and the rings became fat blobs
(ink density inside the swirl's own box fell 51.8% -> 28.2%). The artwork is
already right. Lift the exact pixels, resample once, composite.

Proportions match Radiant and AiOS so the three sit together in the Dock:
    body  0.896 of the canvas
    swirl 0.678
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image

HERE = Path(__file__).resolve().parent
CANVAS = 1024
CHAMPAGNE = (247, 215, 148)         # #F7D794  the swirl
# The body. #0B1329 is the app's own darkest surface, and the point of choosing
# it over #192A56 is distance from Radiant's #5377B3 at Dock size.
NAVY = (11, 19, 41)                 # #0B1329  the body
BODY = int(round(0.896 * CANVAS))
MARK = 694


def lift_swirl(img: Image.Image) -> Image.Image:
    """The white swirl as a soft coverage mask, cropped to the ink.

    Soft, not binary: a hard threshold discards the anti-aliased edge and the
    resize then stair-steps.
    """
    a = np.asarray(img.convert("RGBA")).astype(np.float32)
    rgb, alpha = a[..., :3], a[..., 3]
    lum = 0.2126 * rgb[..., 0] + 0.7152 * rgb[..., 1] + 0.0722 * rgb[..., 2]
    # ⚠️ THE LOW END IS 150, NOT 120. AiOS's own body blue measures lum ~116, so
    # a floor of 120 left every pixel in the box at 0.03-0.10 coverage — invisible
    # on Radiant's mid blue, but on Midnight Navy it painted a distinct lighter
    # SQUARE behind the swirl. 150 puts the old body firmly at zero and still
    # leaves the anti-aliased edge its gradient.
    cover = np.clip((lum - 150) / (235 - 150), 0, 1) * (alpha > 128)
    ys, xs = np.where(cover > 0.5)
    if not len(xs):
        raise SystemExit("no white swirl found in the source icon")
    return Image.fromarray((cover * 255).astype(np.uint8)).crop(
        (xs.min(), ys.min(), xs.max() + 1, ys.max() + 1))


def squircle(size: int) -> Image.Image:
    """Apple's rounded shape. A plain rounded rect reads as subtly wrong."""
    y, x = np.mgrid[0:size, 0:size]
    c = (size - 1) / 2
    e = (np.abs(x - c) / c) ** 5.0 + (np.abs(y - c) / c) ** 5.0
    return Image.fromarray((np.clip((1.0 - e) * size / 3.0 + 0.5, 0, 1) * 255).astype(np.uint8))


def main() -> None:
    src = Path(sys.argv[1]) if len(sys.argv) > 1 else Path.home() / "Projects/aios-claude/mac/icon-1024.png"
    mark = lift_swirl(Image.open(src))
    print(f"  lifted swirl {mark.size[0]}x{mark.size[1]} from {src.name}")

    mark = mark.resize((MARK, MARK), Image.LANCZOS)
    body = Image.new("RGBA", (BODY, BODY), (*NAVY, 255))
    body.putalpha(squircle(BODY))
    ink = Image.new("RGBA", mark.size, (*CHAMPAGNE, 255))
    ink.putalpha(mark)
    body.alpha_composite(ink, ((BODY - MARK) // 2,) * 2)

    icon = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    icon.paste(body, ((CANVAS - BODY) // 2,) * 2, body)
    icon.save(HERE / "icon-1024.png")
    print(f"  wrote icon-1024.png  body {BODY}  swirl {MARK}")
    write_icns(icon)


def write_icns(icon: Image.Image) -> None:
    """Protect.icns, from the same run.

    ⚠️ THE .icns IS WHAT SHIPS, NOT THE PNG. build.sh and release.sh copy
    Protect.icns and never look at icon-1024.png, so regenerating the png alone
    changes nothing you can see — the app keeps its old icon and the change
    looks like it silently failed. (Then it looks like it failed a second time,
    because a running app holds on to its old Dock icon until you quit it.)
    """
    import shutil, subprocess, tempfile
    with tempfile.TemporaryDirectory() as tmp:
        iconset = Path(tmp) / "Protect.iconset"
        iconset.mkdir()
        for px in (16, 32, 128, 256, 512):
            icon.resize((px, px), Image.LANCZOS).save(iconset / f"icon_{px}x{px}.png")
            icon.resize((px * 2, px * 2), Image.LANCZOS).save(iconset / f"icon_{px}x{px}@2x.png")
        out = Path(tmp) / "Protect.icns"
        subprocess.run(["iconutil", "-c", "icns", str(iconset), "-o", str(out)], check=True)
        shutil.copy(out, HERE / "Protect.icns")
    print("  wrote Protect.icns")


if __name__ == "__main__":
    main()
