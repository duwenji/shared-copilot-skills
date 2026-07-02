#!/usr/bin/env python3
"""
Assemble a KDP Paperback full-wrap cover PNG.

Layout (left to right):
  [bleed | back-cover | spine | front-cover | bleed]

Height: bleed + trim_height + bleed

Physical dimensions are printed to stdout as key=value pairs so the
calling PowerShell script can pass them to paperback-to-pdf.mjs:
  WRAP_WIDTH_IN=<float>
  WRAP_HEIGHT_IN=<float>
  DPI=<int>
"""
import sys
import argparse
import importlib.util
import subprocess
from pathlib import Path


def _ensure_pillow():
    if importlib.util.find_spec('PIL') is None:
        subprocess.check_call(
            [sys.executable, '-m', 'pip', 'install', '--quiet', 'pillow']
        )


_ensure_pillow()

from PIL import Image, ImageDraw, ImageFont  # noqa: E402


def _hex_to_rgb(hex_str: str) -> tuple:
    h = hex_str.lstrip('#')
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def _find_cjk_font_path(user_path: str) -> str | None:
    """Return the first existing CJK-capable font path, or None."""
    candidates = []
    if user_path:
        candidates.append(user_path)
    candidates += [
        r'C:\Windows\Fonts\YuGothM.ttc',
        r'C:\Windows\Fonts\YuGothR.ttc',
        r'C:\Windows\Fonts\meiryo.ttc',
        r'C:\Windows\Fonts\msgothic.ttc',
        r'C:\Windows\Fonts\YuGothB.ttc',
        '/System/Library/Fonts/Hiragino Sans GB.ttc',
        '/System/Library/Fonts/ヒラギノ角ゴシック W3.ttc',
        '/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc',
        '/usr/share/fonts/noto-cjk/NotoSansCJK-Regular.ttc',
    ]
    for path in candidates:
        if path and Path(path).exists():
            return path
    return None


def _draw_spine_text(
    canvas: Image.Image,
    spine_x: int,
    bleed_px: int,
    spine_px: int,
    trim_h_px: int,
    spine_color: tuple,
    title: str,
    author: str,
    font_path: str,
) -> None:
    """Draw rotated title + author text centred in the spine strip.

    Text is rotated 90° clockwise so it reads top-to-bottom when the
    book stands upright (standard Japanese spine convention).
    """
    font_size = max(int(spine_px * 0.55), 8)
    found_path = _find_cjk_font_path(font_path)
    if not found_path:
        print('WARNING: No CJK font found — spine text skipped.', file=sys.stderr)
        return

    try:
        title_font = ImageFont.truetype(found_path, font_size)
        author_font = ImageFont.truetype(found_path, max(int(font_size * 0.7), 6))
    except Exception as exc:
        print(f'WARNING: Failed to load font {found_path}: {exc}', file=sys.stderr)
        return

    # Create a horizontal band: width = trim_h_px, height = spine_px
    # We will rotate it -90° so it becomes the vertical spine strip.
    band = Image.new('RGB', (trim_h_px, spine_px), spine_color)
    draw = ImageDraw.Draw(band)
    text_color = (255, 255, 255)

    parts: list[tuple[str, ImageFont.FreeTypeFont]] = []
    if title:
        parts.append((title, title_font))
    if author:
        parts.append((author, author_font))

    if not parts:
        return

    gap = max(int(trim_h_px * 0.04), 8)

    # Measure each part
    blocks: list[tuple[str, ImageFont.FreeTypeFont, int, int]] = []
    total_text_w = 0
    for text, fnt in parts:
        bb = draw.textbbox((0, 0), text, font=fnt)
        tw = bb[2] - bb[0]
        th = bb[3] - bb[1]
        blocks.append((text, fnt, tw, th))
        total_text_w += tw
    total_text_w += gap * (len(blocks) - 1)

    # Draw centred along the long axis of the band
    x = (trim_h_px - total_text_w) // 2
    for text, fnt, tw, th in blocks:
        y = (spine_px - th) // 2
        draw.text((x, y), text, fill=text_color, font=fnt)
        x += tw + gap

    # Rotate -90° (clockwise) → text reads top-to-bottom in the PDF
    rotated = band.rotate(-90, expand=True)  # result: (spine_px, trim_h_px)
    canvas.paste(rotated, (spine_x, bleed_px))


def main() -> None:
    p = argparse.ArgumentParser(
        description='Assemble a KDP Paperback full-wrap cover PNG.'
    )
    p.add_argument('--input-image',  required=True, help='Front cover JPEG or PNG')
    p.add_argument('--output-image', required=True, help='Output PNG path')
    p.add_argument('--trim-width',   type=float, default=6.0,   help='Trim width in inches')
    p.add_argument('--trim-height',  type=float, default=9.0,   help='Trim height in inches')
    p.add_argument('--spine-width',  type=float, required=True, help='Spine width in inches')
    p.add_argument('--bleed',        type=float, default=0.125, help='Bleed in inches (default 0.125)')
    p.add_argument('--back-color',   default='#0b1220',         help='Back cover hex colour')
    p.add_argument('--spine-color',  default='',                help='Spine strip hex colour (default = back-color)')
    p.add_argument('--spine-title',  default='',                help='Title text for spine')
    p.add_argument('--spine-author', default='',                help='Author text for spine')
    p.add_argument('--font-path',    default='',                help='Path to CJK-capable TTF/TTC font')
    a = p.parse_args()

    # -----------------------------------------------------------------------
    # Load front cover and derive DPI
    # -----------------------------------------------------------------------
    front = Image.open(a.input_image)
    front_w, front_h = front.size
    dpi = round(front_w / a.trim_width)

    def px(inches: float) -> int:
        return round(inches * dpi)

    # Resize front cover to exactly match trim dimensions (avoids KDP
    # "outside the margins" error when image aspect ratio is not exactly 2:3).
    target_w = px(a.trim_width)
    target_h = px(a.trim_height)
    if front_w != target_w or front_h != target_h:
        print(
            f'INFO: Resizing cover {front_w}x{front_h} → {target_w}x{target_h} '
            f'to match trim {a.trim_width}in×{a.trim_height}in at {dpi} DPI',
            file=sys.stderr,
        )
        front = front.resize((target_w, target_h), Image.LANCZOS)
        front_w, front_h = target_w, target_h

    bleed_px = px(a.bleed)
    spine_px = px(a.spine_width)

    # Canvas dimensions
    total_w = bleed_px + front_w + spine_px + front_w + bleed_px
    total_h = bleed_px + front_h + bleed_px

    back_color  = _hex_to_rgb(a.back_color)
    spine_color = _hex_to_rgb(a.spine_color) if a.spine_color else back_color

    # -----------------------------------------------------------------------
    # Build canvas
    # -----------------------------------------------------------------------
    canvas = Image.new('RGB', (total_w, total_h), back_color)

    # Spine strip background (only paint if colour differs from back cover)
    spine_x = bleed_px + front_w
    if spine_color != back_color:
        draw = ImageDraw.Draw(canvas)
        draw.rectangle(
            [spine_x, 0, spine_x + spine_px - 1, total_h - 1],
            fill=spine_color,
        )

    # Front cover (placed in the right panel, vertically centred in trim area)
    canvas.paste(front.convert('RGB'), (spine_x + spine_px, bleed_px))

    # Spine text (requires ≥ 0.1" spine and page count check is upstream)
    if (a.spine_title or a.spine_author) and a.spine_width > 0.1:
        _draw_spine_text(
            canvas, spine_x, bleed_px, spine_px, front_h,
            spine_color, a.spine_title, a.spine_author, a.font_path,
        )

    # -----------------------------------------------------------------------
    # Save
    # -----------------------------------------------------------------------
    canvas.save(a.output_image, dpi=(dpi, dpi))

    wrap_w_in = total_w / dpi
    wrap_h_in = total_h / dpi
    print(f'WRAP_WIDTH_IN={wrap_w_in:.6f}')
    print(f'WRAP_HEIGHT_IN={wrap_h_in:.6f}')
    print(f'DPI={dpi}')


if __name__ == '__main__':
    main()
