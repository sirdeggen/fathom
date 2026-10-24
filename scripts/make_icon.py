#!/usr/bin/env python3
"""Draw Fathom's app icon and write a 1024 PNG into the asset catalog.

The mark is an invented coastline, not a real country or state. Python
standard library only.
"""

from __future__ import annotations

import struct
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "App" / "Fathom" / "Assets.xcassets" / "AppIcon.appiconset" / "AppIcon.png"

SIZE = 1024
SCALE = 3
PAPER = (30, 51, 48)       # #1E3330
CREAM = (231, 220, 203)    # #E7DCCB
CLAY = (196, 93, 38)       # #C45D26


def catmull_rom(points: list[tuple[float, float]], samples: int = 18) -> list[tuple[float, float]]:
    count = len(points)
    curve: list[tuple[float, float]] = []
    for index in range(count):
        p0 = points[(index - 1) % count]
        p1 = points[index]
        p2 = points[(index + 1) % count]
        p3 = points[(index + 2) % count]
        for step in range(samples):
            t = step / samples
            t2 = t * t
            t3 = t2 * t
            x = 0.5 * (
                (2 * p1[0])
                + (-p0[0] + p2[0]) * t
                + (2 * p0[0] - 5 * p1[0] + 4 * p2[0] - p3[0]) * t2
                + (-p0[0] + 3 * p1[0] - 3 * p2[0] + p3[0]) * t3
            )
            y = 0.5 * (
                (2 * p1[1])
                + (-p0[1] + p2[1]) * t
                + (2 * p0[1] - 5 * p1[1] + 4 * p2[1] - p3[1]) * t2
                + (-p0[1] + 3 * p1[1] - 3 * p2[1] + p3[1]) * t3
            )
            curve.append((x, y))
    return curve


def fill_polygon(pixels: bytearray, width: int, height: int, polygon: list[tuple[float, float]], color: tuple[int, int, int]) -> None:
    if len(polygon) < 3:
        return
    y_min = max(0, int(min(point[1] for point in polygon)))
    y_max = min(height - 1, int(max(point[1] for point in polygon)))
    count = len(polygon)
    red, green, blue = color
    for y in range(y_min, y_max + 1):
        scan = y + 0.5
        crossings: list[float] = []
        for index in range(count):
            x1, y1 = polygon[index]
            x2, y2 = polygon[(index + 1) % count]
            if (y1 <= scan < y2) or (y2 <= scan < y1):
                crossings.append(x1 + (scan - y1) * (x2 - x1) / (y2 - y1))
        crossings.sort()
        row = y * width * 3
        pair = 0
        while pair + 1 < len(crossings):
            start = max(0, int(crossings[pair]))
            end = min(width, int(crossings[pair + 1] + 1))
            for x in range(start, end):
                offset = row + x * 3
                pixels[offset] = red
                pixels[offset + 1] = green
                pixels[offset + 2] = blue
            pair += 2


def fill_circle(
    pixels: bytearray,
    width: int,
    height: int,
    center_x: float,
    center_y: float,
    radius: float,
    color: tuple[int, int, int],
) -> None:
    red, green, blue = color
    radius_sq = radius * radius
    y0 = max(0, int(center_y - radius))
    y1 = min(height - 1, int(center_y + radius))
    x0 = max(0, int(center_x - radius))
    x1 = min(width - 1, int(center_x + radius))
    for y in range(y0, y1 + 1):
        dy = y + 0.5 - center_y
        row = y * width * 3
        for x in range(x0, x1 + 1):
            dx = x + 0.5 - center_x
            if dx * dx + dy * dy <= radius_sq:
                offset = row + x * 3
                pixels[offset] = red
                pixels[offset + 1] = green
                pixels[offset + 2] = blue


def downsample(source: bytearray, width: int, height: int, factor: int) -> bytearray:
    out_w = width // factor
    out_h = height // factor
    output = bytearray(out_w * out_h * 3)
    area = factor * factor
    for y in range(out_h):
        for x in range(out_w):
            totals = [0, 0, 0]
            for dy in range(factor):
                row = ((y * factor + dy) * width + x * factor) * 3
                for dx in range(factor):
                    offset = row + dx * 3
                    totals[0] += source[offset]
                    totals[1] += source[offset + 1]
                    totals[2] += source[offset + 2]
            dest = (y * out_w + x) * 3
            output[dest] = totals[0] // area
            output[dest + 1] = totals[1] // area
            output[dest + 2] = totals[2] // area
    return output


def write_png(path: Path, rgb: bytes, width: int, height: int) -> None:
    def chunk(tag: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    raw = b"".join(b"\x00" + rgb[y * width * 3 : (y + 1) * width * 3] for y in range(height))
    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 9))
    png += chunk(b"IEND", b"")
    path.write_bytes(png)


def coastline(scale: int) -> list[tuple[float, float]]:
    # An invented shore: a bay on the east, a spur to the northwest.
    # Coordinates are fractions of the icon.
    guides = [
        (0.58, 0.16),
        (0.74, 0.20),
        (0.84, 0.32),
        (0.72, 0.42),
        (0.80, 0.54),
        (0.86, 0.68),
        (0.70, 0.82),
        (0.50, 0.88),
        (0.32, 0.80),
        (0.20, 0.64),
        (0.18, 0.46),
        (0.30, 0.34),
        (0.24, 0.22),
        (0.40, 0.16),
    ]
    margin = 0.08 * scale
    span = 0.84 * scale
    return [(margin + x * span, margin + y * span) for x, y in catmull_rom(guides)]


def main() -> None:
    width = SIZE * SCALE
    height = SIZE * SCALE
    pixels = bytearray(PAPER * (width * height))
    fill_polygon(pixels, width, height, coastline(SCALE), CREAM)
    # A clay sounding mark sitting in the eastern bay.
    fill_circle(pixels, width, height, 0.78 * width, 0.40 * height, 0.045 * width, CLAY)
    icon = downsample(pixels, width, height, SCALE)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    write_png(OUT, bytes(icon), SIZE, SIZE)
    print(f"wrote {OUT} ({OUT.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
