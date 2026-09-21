#!/usr/bin/env python3
"""Generates macos/packaging/dmg-background.png.

The DMG installer window background: create-dmg lays out the app icon
(left) and the Applications symlink (right) over this image. Palette comes
from the mosh-landing theme (dark #0a0b0c..#16181b, moss #b7d84a, moss
glow rgba(183,216,74,.16)) so the installer matches the site.

Standard library only: the image is encoded with zlib, so regeneration
needs nothing beyond python3.
"""

import pathlib
import struct
import zlib

# @2x of create-dmg's 660x400 window (retina rendering on macOS).
W, H = 1320, 800

# mosh-landing theme.css palette.
TOP = (0x0A, 0x0B, 0x0C)
BOTTOM = (0x16, 0x18, 0x1B)
MOSS = (0xB7, 0xD8, 0x4A)
GLOW_ALPHA = 0.14
ARROW_ALPHA = 0.55

# Layout, in @2x coordinates: app icon slot at (180, 190) in 1x, the
# Applications drop link at (480, 190); the arrow bridges the two.
ARROW_Y = 380
ARROW_X0 = 560
ARROW_X1 = 800
ARROW_HALF = 5
HEAD_WIDTH = 56
HEAD_HALF = 30
GLOW_CENTER = (360, 380)
GLOW_RADIUS = 360


def lerp(a, b, t):
    return a + (b - a) * t


def background(x, y):
    """Base pixel: vertical dark gradient + one soft moss glow."""
    t = y / (H - 1)
    r = lerp(TOP[0], BOTTOM[0], t)
    g = lerp(TOP[1], BOTTOM[1], t)
    b = lerp(TOP[2], BOTTOM[2], t)

    dx = x - GLOW_CENTER[0]
    dy = y - GLOW_CENTER[1]
    dist = (dx * dx + dy * dy) ** 0.5
    if dist < GLOW_RADIUS:
        falloff = 1 - dist / GLOW_RADIUS
        a = GLOW_ALPHA * falloff * falloff
        r = r * (1 - a) + MOSS[0] * a
        g = g * (1 - a) + MOSS[1] * a
        b = b * (1 - a) + MOSS[2] * a

    return r, g, b


def arrow_blend(x, y, r, g, b):
    """Draws the moss arrow pointing at the Applications slot."""
    dy = abs(y - ARROW_Y)
    tip = ARROW_X1 + HEAD_WIDTH
    in_shaft = ARROW_X0 <= x <= ARROW_X1 and dy <= ARROW_HALF
    # Arrowhead: triangle with its base at the shaft end, tip past it.
    in_head = (
        ARROW_X1 <= x <= tip
        and dy <= max(ARROW_HALF, HEAD_HALF * (tip - x) / HEAD_WIDTH)
    )
    if not (in_shaft or in_head):
        return r, g, b
    return (
        r * (1 - ARROW_ALPHA) + MOSS[0] * ARROW_ALPHA,
        g * (1 - ARROW_ALPHA) + MOSS[1] * ARROW_ALPHA,
        b * (1 - ARROW_ALPHA) + MOSS[2] * ARROW_ALPHA,
    )


def png_chunk(tag, data):
    payload = tag + data
    return (
        struct.pack(">I", len(data))
        + payload
        + struct.pack(">I", zlib.crc32(payload) & 0xFFFFFFFF)
    )


def encode(pixels):
    """pixels: flat RGBA buffer, W*H*4 bytes."""
    stride = W * 4
    raw = b"".join(
        b"\x00" + pixels[y * stride : (y + 1) * stride] for y in range(H)
    )
    ihdr = struct.pack(">IIBBBBB", W, H, 8, 6, 0, 0, 0)
    return b"".join(
        (
            b"\x89PNG\r\n\x1a\n",
            png_chunk(b"IHDR", ihdr),
            png_chunk(b"IDAT", zlib.compress(raw, 9)),
            png_chunk(b"IEND", b""),
        )
    )


def main():
    pixels = bytearray()
    for y in range(H):
        for x in range(W):
            r, g, b = background(x, y)
            r, g, b = arrow_blend(x, y, r, g, b)
            pixels += bytes(
                (int(r + 0.5), int(g + 0.5), int(b + 0.5), 0xFF)
            )

    out = pathlib.Path(__file__).resolve().parents[1] / "macos" / "packaging"
    out.mkdir(parents=True, exist_ok=True)
    target = out / "dmg-background.png"
    target.write_bytes(encode(pixels))
    print(f"wrote {target} ({W}x{H})")


if __name__ == "__main__":
    main()
