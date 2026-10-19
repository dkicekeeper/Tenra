#!/usr/bin/env python3
"""Compose the App Store's header and search art (iOS 27): screenshots/raw/ -> screenshots/art/.

    header.jpg          3840x1646 (21:9), the product page's header: Ten and a phrase.
    search.jpg          3840x2560 (3:2), the search result: a headline and one screen in an
                        iPhone; search-<page>.jpg the same for each custom product page.

Both go to every page in its locale: the default product page and the custom product pages
(appstore/product-pages.json: a page's `searchFrame` is the caption key of its search art, the
default page's is `ten`). What matters stays inside Apple's safe areas (SAFE below): on iPhone
the header shows only its middle, under the status bar and above the app's name, and search
shows its art at about 365 pt wide, a tenth of 3840 px (--preview writes that size).

    python3 scripts/compose_store_art.py                  # every locale in screenshots/raw
    python3 scripts/compose_store_art.py ru en-US --preview /tmp/art   # and copies to look at

The background is the screenshots' (the dark field with colour glows of screenshots/templates),
drawn at full size. Ten comes from `--ten` (default screenshots/art/ten, from Actions →
Screenshots with `art`: TenraTests/Views/StoreArtRenderTests); the phrase from `header` in
scripts/screenshot_captions.json, the headline from the frame's caption. Fonts as in
compose_screenshots.py. JPEG, no transparency: Apple refuses an alpha channel.
asc.py push-creatives uploads the files.
"""
import argparse
import io
import json
import os
import sys

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import compose_screenshots as shots  # noqa: E402  (fonts, line breaking, captions)

ROOT = shots.ROOT
ART = os.path.join(ROOT, "screenshots", "art")
PAGES = os.path.join(ROOT, "appstore", "product-pages.json")

HEADER_SIZE = (3840, 1646)
SEARCH_SIZE = (3840, 2560)
# Apple's safe areas (x0, y0, x1, y1): what every device shows.
SAFE = {"header": (1097, 493, 2743, 1154), "search": (836, 765, 3004, 1795)}

BASE = (15, 15, 15)
# The templates' glows.
RED, LIME, BLUE, ORANGE, TEAL = (200, 18, 22), (160, 232, 16), (8, 132, 246), (226, 104, 22), (22, 170, 196)

TEN_MOOD = "happy"
TEN_SCHEME = "dark"


# MARK: - Background

def glow_field(size, blobs, blur=0.11):
    """The dark field with soft colour glows, RGBA: each blob (cx, cy, rx, ry, colour, strength)
    in fractions of the size, drawn small, blurred and scaled up so the gradients stay smooth."""
    w, h = size
    small = (w // 8, h // 8)
    acc = np.zeros((small[1], small[0], 3), np.float32)
    for cx, cy, rx, ry, colour, strength in blobs:
        layer = Image.new("L", small, 0)
        ImageDraw.Draw(layer).ellipse(
            ((cx - rx) * small[0], (cy - ry) * small[1], (cx + rx) * small[0], (cy + ry) * small[1]), fill=255)
        layer = layer.filter(ImageFilter.GaussianBlur(blur * small[0]))
        alpha = np.asarray(layer).astype(np.float32)[..., None] / 255 * strength
        acc = acc * (1 - alpha) + np.array(colour, np.float32) * alpha
    acc = np.maximum(acc, np.array(BASE, np.float32))
    field = Image.fromarray(np.clip(acc.round(), 0, 255).astype(np.uint8), "RGB").resize(size, Image.BICUBIC)
    # A little noise so the long gradients don't band.
    noise = Image.effect_noise(size, 3).convert("RGB")
    field = ImageChops.add(field, noise, scale=1, offset=-128)
    return field.convert("RGBA")


def to_image(canvas):
    return canvas.convert("RGB")


def paste(canvas, image, x, y):
    """Alpha-composite an RGBA `image` onto the canvas at (x, y), clipped to the canvas."""
    layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    layer.paste(image, (x, y))
    canvas.alpha_composite(layer)


# MARK: - Text

HIRAGANA = range(0x3041, 0x3097)
JA_PARTICLES = set("はがをにでともへの")


def ja_tokens(paragraph, locale):
    """Where a Japanese line may break in the art's long lines: after 、 and 。, and after a
    particle that ends a word (the next character is not hiragana), so a word never splits;
    other locales as in the screenshots."""
    if locale != "ja":
        return screenshot_tokens(paragraph, locale)
    out, current = [], ""
    for i, ch in enumerate(paragraph):
        current += ch
        following = paragraph[i + 1] if i + 1 < len(paragraph) else ""
        if ch in "、。" or (ch in JA_PARTICLES and following and ord(following) not in HIRAGANA and following not in "、。"):
            out.append(current)
            current = ""
    if current:
        out.append(current)
    return out, ""


screenshot_tokens = shots.tokens
shots.tokens = ja_tokens

def text_layer(size, lines, font, pitch, fill=(255, 255, 255, 255), align="left"):
    """Lines of text on a transparent layer: the first baseline at the font's ascent."""
    w, h = size
    layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    ascent = font.getmetrics()[0]
    for i, line in enumerate(lines):
        x = {"left": 0, "center": w / 2}[align]
        draw.text((x, ascent + i * pitch), line, font=font, fill=fill, anchor="ls" if align == "left" else "ms")
    return layer


def fitted(text, locale, weight, size, width, max_lines, two_lines_down_to=None):
    """The largest font up to `size` whose lines fit `width` in at most `max_lines`; with
    `two_lines_down_to`, two lines at a font down to that size come first."""
    def attempt(lines_allowed, smallest):
        current = size
        while current >= smallest:
            font = shots.load_font(locale, weight, current)
            lines = shots.wrap(text, font, width, locale)
            if len(lines) <= lines_allowed and all(shots.ink_width(font, l) <= width for l in lines):
                return font, lines, current
            current -= 4
        return None
    found = two_lines_down_to and attempt(2, two_lines_down_to)
    found = found or attempt(max_lines, 24)
    if not found:
        sys.exit(f"{locale}: {text!r} does not fit")
    return found


# MARK: - iPhone

def iphone(screen, width):
    """An iPhone in the templates' style (a lavender metal band, a black bezel, the Dynamic
    Island) around `screen` (a 1206x2622 capture), `width` px wide, RGBA."""
    band, bezel = round(width * 0.016), round(width * 0.034)
    screen_w = width - 2 * (band + bezel)
    screen_h = round(screen_w * 2622 / 1206)
    height = screen_h + 2 * (band + bezel)
    radius = round(screen_w * 0.123) + band + bezel
    scale = 2
    W, H, R = width * scale, height * scale, radius * scale
    body = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    draw = ImageDraw.Draw(body)
    # The band: a vertical gradient from light to deep lavender, a light rim inside.
    top, bottom = np.array((206, 198, 236), np.float32), np.array((104, 96, 138), np.float32)
    ramp = np.linspace(0, 1, 256, dtype=np.float32)[:, None, None]
    strip = Image.fromarray((top * (1 - ramp) + bottom * ramp).round().astype(np.uint8), "RGB")
    metal = strip.resize((W, H), Image.BILINEAR)
    mask = Image.new("L", (W, H), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, W - 1, H - 1), radius=R, fill=255)
    body.paste(metal, (0, 0), mask)
    b = band * scale
    draw.rounded_rectangle((b * 0.45, b * 0.45, W - 1 - b * 0.45, H - 1 - b * 0.45), radius=R - b * 0.45,
                           outline=(232, 226, 250, 255), width=max(1, round(b * 0.18)))
    draw.rounded_rectangle((b, b, W - 1 - b, H - 1 - b), radius=R - b, fill=(0, 0, 0, 255))
    body = body.resize((width, height), Image.LANCZOS)

    inset = band + bezel
    shot = screen.convert("RGB").resize((screen_w, screen_h), Image.LANCZOS)
    screen_mask = Image.new("L", (screen_w * scale, screen_h * scale), 0)
    ImageDraw.Draw(screen_mask).rounded_rectangle(
        (0, 0, screen_w * scale - 1, screen_h * scale - 1), radius=round(screen_w * 0.123) * scale, fill=255)
    body.paste(shot, (inset, inset), screen_mask.resize((screen_w, screen_h), Image.LANCZOS))
    # The Dynamic Island, where the template has it.
    island = Image.new("L", (screen_w * scale, screen_h * scale), 0)
    ix0, iy0, ix1, iy1 = (v / 854 * screen_w * scale for v in shots.ISLAND)
    ImageDraw.Draw(island).rounded_rectangle((ix0, iy0, ix1, iy1), radius=(iy1 - iy0) / 2, fill=255)
    body.paste((0, 0, 0, 255), (inset, inset), island.resize((screen_w, screen_h), Image.LANCZOS))
    return body


def shadowed(image, blur, opacity=0.55, offset=(0, 0)):
    """`image` on a transparent canvas with a soft shadow under it."""
    pad = blur * 3
    w, h = image.size
    canvas = Image.new("RGBA", (w + 2 * pad, h + 2 * pad), (0, 0, 0, 0))
    alpha = Image.new("L", canvas.size, 0)
    alpha.paste(image.getchannel("A"), (pad + offset[0], pad + offset[1]))
    alpha = alpha.filter(ImageFilter.GaussianBlur(blur)).point(lambda v: round(v * opacity))
    canvas.putalpha(alpha)
    canvas.alpha_composite(image, (pad, pad))
    return canvas, pad


# MARK: - Ten

def ten_picture(folder, side):
    path = os.path.join(folder, f"ten-{TEN_MOOD}-{TEN_SCHEME}.png")
    if not os.path.exists(path):
        sys.exit(f"{path} not found: run Actions → Screenshots with `art` and put its art/ folder there")
    image = Image.open(path).convert("RGBA")
    # The picture has room around the creature: crop to what it draws.
    box = image.getchannel("A").point(lambda v: 255 if v > 8 else 0).getbbox() or (0, 0, *image.size)
    image = image.crop(box)
    scale = side / max(image.size)
    return image.resize((round(image.width * scale), round(image.height * scale)), Image.LANCZOS)


# MARK: - Header

def header(locale, phrase, ten_folder):
    w, h = HEADER_SIZE
    sx0, sy0, sx1, sy1 = SAFE["header"]
    base = glow_field(HEADER_SIZE, [
        (0.40, 0.50, 0.12, 0.30, TEAL, 0.55),
        (0.44, 0.40, 0.08, 0.22, LIME, 0.35),
        (0.10, 0.30, 0.16, 0.40, RED, 0.75),
        (0.90, 0.70, 0.16, 0.40, BLUE, 0.80),
        (0.78, 0.20, 0.10, 0.25, LIME, 0.45),
        (0.20, 0.85, 0.12, 0.28, ORANGE, 0.45),
    ])
    safe_w, safe_h = sx1 - sx0, sy1 - sy0
    ten_side = round(safe_h * 0.72)
    ten = ten_picture(ten_folder, ten_side)
    gap = round(safe_w * 0.04)
    text_w = safe_w - ten.width - gap
    font, lines, size = fitted(phrase, locale, "SemiBold", 132, text_w, 3, two_lines_down_to=100)
    pitch = round(size * 1.16)
    block_h = font.getmetrics()[0] + (len(lines) - 1) * pitch + font.getmetrics()[1] // 2
    text_widest = max(shots.ink_width(font, l) for l in lines)
    # Ten and the phrase together, centred in the safe area.
    total = ten.width + gap + text_widest
    x = sx0 + (safe_w - total) // 2
    paste(base, ten, x, sy0 + (safe_h - ten.height) // 2)
    text = text_layer((text_w + 40, block_h + 40), lines, font, pitch)
    paste(base, text, x + ten.width + gap, sy0 + (safe_h - block_h) // 2)
    return to_image(base), lines


# MARK: - Search

def search(locale, title, subtitle, screen, ten_folder):
    w, h = SEARCH_SIZE
    sx0, sy0, sx1, sy1 = SAFE["search"]
    base = glow_field(SEARCH_SIZE, [
        (0.66, 0.45, 0.14, 0.30, RED, 0.80),
        (0.76, 0.62, 0.12, 0.26, BLUE, 0.85),
        (0.58, 0.30, 0.10, 0.20, LIME, 0.45),
        (0.12, 0.85, 0.16, 0.30, ORANGE, 0.30),
        (0.08, 0.15, 0.12, 0.25, TEAL, 0.25),
    ])
    # The phone on the right, taller than the safe area: its middle (the answer's cards) is in it.
    phone = iphone(screen, 980).rotate(-6, resample=Image.BICUBIC, expand=True)
    phone, pad = shadowed(phone, 60, 0.7, (0, 40))
    px = sx1 - phone.width + pad + 300
    py = (h - phone.height) // 2
    paste(base, phone, px, py)

    # The headline on the left, Ten over it.
    left = sx0 + 40
    text_w = px + pad - left - 140
    title_font, title_lines, title_size = fitted(title, locale, "SemiBold", 184, text_w, 3, two_lines_down_to=140)
    sub_font, sub_lines, sub_size = fitted(subtitle, locale, "Medium", 88, text_w, 3, two_lines_down_to=76)
    ten = ten_picture(ten_folder, 260)
    title_pitch, sub_pitch = round(title_size * 1.12), round(sub_size * 1.25)
    title_h = title_font.getmetrics()[0] + (len(title_lines) - 1) * title_pitch + title_font.getmetrics()[1] // 2
    sub_h = sub_font.getmetrics()[0] + (len(sub_lines) - 1) * sub_pitch + sub_font.getmetrics()[1] // 2
    gap1, gap2 = 70, 56
    block = ten.height + gap1 + title_h + gap2 + sub_h
    y = sy0 + (sy1 - sy0 - block) // 2
    paste(base, ten, left - 20, y)
    y += ten.height + gap1
    paste(base, text_layer((text_w + 40, title_h + 40), title_lines, title_font, title_pitch), left, y)
    y += title_h + gap2
    paste(base, text_layer((text_w + 40, sub_h + 40), sub_lines, sub_font, sub_pitch, fill=(255, 255, 255, 200)), left, y)
    return to_image(base), title_lines, sub_lines


# MARK: - Main

def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("locales", nargs="*", help="ASC locales (default: every folder in screenshots/raw)")
    parser.add_argument("--raw", default=shots.RAW)
    parser.add_argument("--ten", default=os.path.join(ART, "ten"), help="folder with Ten's pictures")
    parser.add_argument("--out", default=ART)
    parser.add_argument("--preview", metavar="DIR", help="also write 384 px wide copies, and 1600 px ones, there")
    args = parser.parse_args()
    captions = json.load(io.open(shots.CAPTIONS, encoding="utf-8"))["locales"]
    pages = json.load(io.open(PAGES, encoding="utf-8"))
    searches = {"default": "ten", **{page["name"]: page["searchFrame"] for page in pages["customPages"]}}
    locales = args.locales or sorted(d for d in os.listdir(args.raw) if os.path.isdir(os.path.join(args.raw, d)))
    for locale in locales:
        out = os.path.join(args.out, locale)
        os.makedirs(out, exist_ok=True)
        meta = captions[locale]
        image, lines = header(locale, meta["header"], args.ten)
        outputs = [("header", image)]
        print(f"{locale} header: {' / '.join(lines)}")
        for name, key in searches.items():
            caption = meta["frames"][key]
            raw = os.path.join(args.raw, locale, pages["frames"][key] + ".png")
            if not os.path.exists(raw):
                print(f"{locale} search {name}: no {raw}, skipped")
                continue
            image, title_lines, sub_lines = search(locale, caption["title"], caption["subtitle"], Image.open(raw), args.ten)
            slug = "search" if name == "default" else "search-" + name.lower().replace(" ", "-")
            outputs.append((slug, image))
            print(f"{locale} {slug}: {' / '.join(title_lines)} | {' / '.join(sub_lines)}")
        for slug, image in outputs:
            # JPEG: the fine noise of the glows makes a PNG of it 6 MB.
            image.save(os.path.join(out, f"{slug}.jpg"), quality=90, optimize=True)
            if args.preview:
                folder = os.path.join(args.preview, locale)
                os.makedirs(folder, exist_ok=True)
                for width in (384, 1600):
                    image.resize((width, round(width * image.height / image.width)), Image.LANCZOS).save(
                        os.path.join(folder, f"{slug}-{width}.png"))


if __name__ == "__main__":
    main()
