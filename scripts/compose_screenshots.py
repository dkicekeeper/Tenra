#!/usr/bin/env python3
"""Compose the App Store frames: screenshots/raw/<locale>/ -> screenshots/final/<locale>/.

Each frame is a template from screenshots/templates/ (a background and the iPhone, taken from
the Figma file "Tenra", page "Screenshots L10n"), the raw capture placed in the phone's display
with the Dynamic Island over it, and the caption from scripts/screenshot_captions.json: title
Inter SemiBold 98, subtitle Inter Medium 58 (Noto Sans JP / KR for ja and ko), white, centred,
at most two lines each, the lines balanced. Output is 1320x2868, the 6.9" size.

    python3 scripts/compose_screenshots.py                    # every locale in screenshots/raw
    python3 scripts/compose_screenshots.py ru en-US           # these locales
    python3 scripts/compose_screenshots.py ru --frames 13-ten-answer 15-goal

Needs Pillow and numpy. Fonts come from the system or are downloaded once into
~/.cache/tenra-fonts (Inter from its GitHub release, Noto Sans JP/KR from Google Fonts).
"""
import argparse
import functools
import io
import json
import os
import sys
import urllib.request
import zipfile

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RAW = os.path.join(ROOT, "screenshots", "raw")
FINAL = os.path.join(ROOT, "screenshots", "final")
TEMPLATES = os.path.join(ROOT, "screenshots", "templates")
CAPTIONS = os.path.join(ROOT, "scripts", "screenshot_captions.json")
FONT_CACHE = os.path.expanduser("~/.cache/tenra-fonts")

# The display inside every template: the raw capture (1206x2622) scaled to SW x SH at (SX, SY).
SX, SY, SW, SH = 234, 845, 854, 1858
# Inside that rect: the visible display (the bezel covers a few pixels at the edges), its corner
# radius, and the Dynamic Island.
DISPLAY = (0, 5, 853, 1853)
RADIUS = 105
ISLAND = (300, 29, 552, 105)

TITLE_SIZE, SUBTITLE_SIZE = 98, 58
# Baselines: the title's first line, then line pitch; the subtitle starts SUBTITLE_GAP below the
# title's last baseline.
TITLE_BASELINE, TITLE_PITCH, SUBTITLE_GAP, SUBTITLE_PITCH = 274.3, 118.67, 121.0, 70.2
CENTER_X = 659.5
# Figma's 1120-wide text box; the Inter 4 used here sets ~1.3% wider than Figma's Inter.
TITLE_WIDTH, SUBTITLE_WIDTH = 1135, 1125

# Frame file -> its caption key and template. Six backgrounds (a-f) cycle so that neither the
# default order nor tr's, nor a custom product page's (appstore/product-pages.json), puts the
# same background twice in a row. 13 is on e since 1.7's order puts it after 03 (c).
FRAMES = {
    "01-home": ("home", "a"),
    "02-finances": ("finances", "b"),
    "03-insights": ("insights", "c"),
    "04-health-score": ("score", "d"),
    "05-top-category": ("topcat", "e"),
    "06-history": ("history", "f"),
    "07-voice": ("voice", "a"),
    "08-multicurrency": ("fx", "b"),
    "09-subscriptions": ("subscriptions", "b"),
    "10-subscription-detail": ("subscription", "c"),
    "11-deposit": ("deposit", "f"),
    "12-loans": ("loans", "d"),
    "13-ten-answer": ("ten", "e"),
    "14-ten-draft": ("draft", "d"),
    "15-goal": ("goal", "c"),
    "16-debts": ("debts", "f"),
    "17-ten-subscriptions": ("tensubs", "e"),
    "18-ten-currencies": ("tenfx", "d"),
    "19-ten-loan": ("tenloan", "c"),
    "20-autocapture": ("autocapture", "f"),
    "21-merchant": ("merchant", "a"),
}

# Inter has the Kazakh letters too (ә ғ қ ң ө ұ ү һ і and their capitals; Inter 4.0 and 4.1
# checked with fontTools), so kk needs no fallback.
FONTS = {
    "SemiBold": ("Inter-SemiBold.otf", None),
    "Medium": ("Inter-Medium.otf", None),
    "ja": ("NotoSansJP.ttf", "https://raw.githubusercontent.com/google/fonts/main/ofl/notosansjp/NotoSansJP%5Bwght%5D.ttf"),
    "ko": ("NotoSansKR.ttf", "https://raw.githubusercontent.com/google/fonts/main/ofl/notosanskr/NotoSansKR%5Bwght%5D.ttf"),
}
INTER_ZIP = "https://github.com/rsms/inter/releases/download/v4.1/Inter-4.1.zip"
SYSTEM_INTER = ["/usr/share/fonts/opentype/inter", os.path.expanduser("~/Library/Fonts"), "/Library/Fonts"]


def font_file(key):
    name, url = FONTS[key]
    if url is None:
        for folder in SYSTEM_INTER:
            if os.path.exists(os.path.join(folder, name)):
                return os.path.join(folder, name)
    path = os.path.join(FONT_CACHE, name)
    if os.path.exists(path):
        return path
    os.makedirs(FONT_CACHE, exist_ok=True)
    if url is None:
        with urllib.request.urlopen(INTER_ZIP) as r:
            archive = zipfile.ZipFile(io.BytesIO(r.read()))
        for member in archive.namelist():
            if member.endswith("/" + name) and "/otf/" in member:
                with open(path, "wb") as f:
                    f.write(archive.read(member))
                return path
        sys.exit(f"{name} not found in {INTER_ZIP}")
    urllib.request.urlretrieve(url, path)
    return path


@functools.lru_cache(maxsize=None)
def load_font(locale, weight, size):
    if locale in ("ja", "ko"):
        f = ImageFont.truetype(font_file(locale), size)
        f.set_variation_by_axes([{"SemiBold": 600, "Medium": 500}[weight]])
        return f
    return ImageFont.truetype(font_file(weight), size)


def ink_width(f, text):
    box = f.getbbox(text)
    return box[2] - box[0]


def tokens(paragraph, locale):
    """Where a line may break: between words, or between characters in Japanese (never
    before closing punctuation or a small kana)."""
    if locale != "ja":
        return paragraph.split(" "), " "
    no_start = set("、。，．・：；？！ー）」』】〕ぁぃぅぇぉっゃゅょゎァィゥェォッャュョヮヵヶ")
    out = []
    for ch in paragraph:
        if out and ch in no_start:
            out[-1] += ch
        else:
            out.append(ch)
    return out, ""


def wrap(text, f, width, locale):
    """The fewest lines that fit, broken where they come out most even. A "\\n" in the caption
    forces a break."""
    lines = []
    for paragraph in text.split("\n"):
        toks, sep = tokens(paragraph, locale)
        count, current = 1, ""
        for t in toks:
            candidate = t if not current else current + sep + t
            if current and ink_width(f, candidate) > width:
                count, current = count + 1, t
            else:
                current = candidate
        if count == 1:
            lines.append(paragraph)
            continue

        def splits(start, k):
            if k == 1:
                yield [sep.join(toks[start:])]
                return
            for i in range(start + 1, len(toks) - k + 2):
                head = sep.join(toks[start:i])
                if ink_width(f, head) > width:
                    break
                for rest in splits(i, k - 1):
                    yield [head] + rest

        best = None
        for candidate in splits(0, count):
            widest = max(ink_width(f, l) for l in candidate)
            if widest <= width and (best is None or widest < best[0]):
                best = (widest, candidate)
        lines.extend(best[1] if best else [paragraph])
    return lines


def rounded_alpha(box, radius, scale=4):
    """Anti-aliased rounded rectangle over the display rect, 0...1."""
    im = Image.new("L", (SW * scale, SH * scale), 0)
    x0, y0, x1, y1 = box
    ImageDraw.Draw(im).rounded_rectangle(
        (x0 * scale, y0 * scale, x1 * scale - 1, y1 * scale - 1), radius=radius * scale, fill=255)
    return np.asarray(im.resize((SW, SH), Image.BOX)).astype(float)[..., None] / 255


DISPLAY_ALPHA = rounded_alpha(DISPLAY, RADIUS)
ISLAND_ALPHA = rounded_alpha(ISLAND, (ISLAND[3] - ISLAND[1]) / 2)
ISLAND_INNER = rounded_alpha((ISLAND[0] + 3, ISLAND[1] + 3, ISLAND[2] - 3, ISLAND[3] - 3), (ISLAND[3] - ISLAND[1]) / 2 - 3)


def compose(raw_path, background, locale, title, subtitle):
    base = np.asarray(Image.open(os.path.join(TEMPLATES, f"background-{background}.png")).convert("RGB")).astype(float)
    raw = Image.open(raw_path).convert("RGB")
    if raw.size != (1206, 2622):
        sys.exit(f"{raw_path}: {raw.size[0]}x{raw.size[1]}, expected a 1206x2622 capture")
    screen = np.asarray(raw.resize((SW, SH), Image.LANCZOS)).astype(float)
    template = base[SY:SY + SH, SX:SX + SW]
    # The island: a black pill over the capture, the template's camera inside it.
    screen = screen * (1 - ISLAND_ALPHA)
    screen = screen * (1 - ISLAND_INNER) + template * ISLAND_INNER
    base[SY:SY + SH, SX:SX + SW] = template * (1 - DISPLAY_ALPHA) + screen * DISPLAY_ALPHA
    image = Image.fromarray(np.clip(base.round(), 0, 255).astype(np.uint8))

    draw = ImageDraw.Draw(image)
    title_font = load_font(locale, "SemiBold", TITLE_SIZE)
    subtitle_font = load_font(locale, "Medium", SUBTITLE_SIZE)
    title_lines = wrap(title, title_font, TITLE_WIDTH, locale)
    subtitle_lines = wrap(subtitle, subtitle_font, SUBTITLE_WIDTH, locale)
    for i, line in enumerate(title_lines):
        draw.text((CENTER_X, TITLE_BASELINE + i * TITLE_PITCH), line, font=title_font, fill="white", anchor="ms")
    y = TITLE_BASELINE + (len(title_lines) - 1) * TITLE_PITCH + SUBTITLE_GAP
    for i, line in enumerate(subtitle_lines):
        draw.text((CENTER_X, y + i * SUBTITLE_PITCH), line, font=subtitle_font, fill="white", anchor="ms")
    return image, title_lines, subtitle_lines


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("locales", nargs="*", help="ASC locales (default: every folder in screenshots/raw)")
    parser.add_argument("--frames", nargs="*", help="frame files without .png (default: every raw frame)")
    parser.add_argument("--raw", default=RAW, help="folder with <locale>/<frame>.png captures")
    parser.add_argument("--out", default=FINAL, help="folder for <locale>/<frame>.png frames")
    args = parser.parse_args()
    captions = json.load(open(CAPTIONS, encoding="utf-8"))["locales"]
    locales = args.locales or sorted(d for d in os.listdir(args.raw) if os.path.isdir(os.path.join(args.raw, d)))
    problems = 0
    for locale in locales:
        raw_dir = os.path.join(args.raw, locale)
        frames = args.frames or sorted(f[:-4] for f in os.listdir(raw_dir) if f[:-4] in FRAMES)
        os.makedirs(os.path.join(args.out, locale), exist_ok=True)
        for frame in frames:
            key, background = FRAMES[frame]
            caption = captions.get(locale, {}).get("frames", {}).get(key)
            if caption is None:
                print(f"{locale} {frame}: no caption for '{key}', skipped")
                continue
            image, title_lines, subtitle_lines = compose(
                os.path.join(raw_dir, f"{frame}.png"), background, locale, caption["title"], caption["subtitle"])
            image.save(os.path.join(args.out, locale, f"{frame}.png"))
            long = len(title_lines) > 2 or len(subtitle_lines) > 2
            problems += long
            print(f"{locale} {frame}: {' / '.join(title_lines)} | {' / '.join(subtitle_lines)}"
                  + ("   <-- more than two lines, shorten the caption" if long else ""))
    if problems:
        sys.exit(f"{problems} caption(s) over two lines")


if __name__ == "__main__":
    main()
