#!/usr/bin/env python3
"""Compose the image of Apple's retention message: screenshots/art/retention.png, 3840x2160.

The retention message (appstore/retention-message.json, asc.py push-retention-message) is what
Apple shows when someone starts to cancel Tenra Pro. Its image is one for every language (it
belongs to the message's version, not to a locale), so it carries no words: Ten, glad, with a
bubble that holds a calendar page with a 2 and a bell, the reminder two days before the trial
ends. The header and body above it say the same in each language.

    python3 scripts/compose_retention_art.py [--preview /tmp/art]

Background, Ten and fonts as in compose_store_art.py (Ten from screenshots/art/ten, drawn by
Actions → Screenshots with `art`). Everything stays in the middle 70%, so a card that crops the
edges keeps it. PNG without transparency: Apple refuses an alpha channel.
"""
import argparse
import os
import sys

from PIL import Image, ImageDraw, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import compose_store_art as art  # noqa: E402  (background, Ten, paste, shadow)
import compose_screenshots as shots  # noqa: E402  (fonts)

SIZE = (3840, 2160)
OUT = os.path.join(art.ART, "retention.png")

TAIL = 300
GLASS = (255, 255, 255, 34)
GLASS_EDGE = (255, 255, 255, 92)
PAPER = (250, 250, 248, 255)
INK = (24, 24, 28, 255)
CALENDAR_RED = (236, 72, 64, 255)
BELL = (255, 204, 64, 255)
BELL_SHADE = (226, 160, 30, 255)


def rounded(size, radius, fill, outline=None, width=0):
    layer = Image.new("RGBA", size, (0, 0, 0, 0))
    ImageDraw.Draw(layer).rounded_rectangle((0, 0, size[0] - 1, size[1] - 1), radius, fill=fill,
                                            outline=outline, width=width)
    return layer


def bubble(size, tail_tip):
    """A glass speech bubble `size` big on a canvas wider by `TAIL` on the left: the body and a
    tail from its lower left to `tail_tip` (canvas coordinates) as one shape with one edge.
    Returns the canvas and where the body starts on it."""
    w, h = size
    canvas_size = (w + TAIL, h + TAIL)
    ox = TAIL
    radius = round(h * 0.28)
    mask = Image.new("L", canvas_size, 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle((ox, 0, ox + w, h), radius, fill=255)
    draw.polygon([(ox + round(w * 0.10), h - radius), (ox + round(w * 0.30), h - 1), tail_tip], fill=255)
    # One edge around body and tail: the shape grown by the edge's width, minus the shape.
    grown = mask.filter(ImageFilter.MaxFilter(9))
    ring = Image.composite(Image.new("L", canvas_size, 0), grown, mask)
    canvas = Image.new("RGBA", canvas_size, GLASS[:3] + (0,))
    canvas.putalpha(mask.point(lambda v: round(v * GLASS[3] / 255)))
    edge_layer = Image.new("RGBA", canvas_size, GLASS_EDGE[:3] + (0,))
    edge_layer.putalpha(ring.point(lambda v: round(v * GLASS_EDGE[3] / 255)))
    canvas.alpha_composite(edge_layer)
    return canvas, ox, mask


def calendar(side, number):
    """A calendar page `side` px wide: a red band with two rings, the number large under it."""
    w, h = side, round(side * 1.08)
    radius = round(side * 0.16)
    page = rounded((w, h), radius, PAPER)
    draw = ImageDraw.Draw(page)
    band = round(h * 0.27)
    mask = rounded((w, h), radius, (255, 255, 255, 255)).getchannel("A")
    red = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ImageDraw.Draw(red).rectangle((0, 0, w, band), fill=CALENDAR_RED)
    red.putalpha(Image.composite(red.getchannel("A"), Image.new("L", (w, h), 0), mask))
    page.alpha_composite(red)
    ring_w, ring_h = round(w * 0.07), round(band * 0.62)
    for cx in (round(w * 0.30), round(w * 0.70)):
        draw.rounded_rectangle((cx - ring_w // 2, -round(ring_h * 0.35), cx + ring_w // 2, round(ring_h * 0.65)),
                               ring_w // 2, fill=(255, 255, 255, 235))
    font = shots.load_font("en-US", "SemiBold", round(h * 0.62))
    draw.text((w / 2, band + (h - band) * 0.52), number, font=font, fill=INK, anchor="mm")
    return page


def bell(side):
    """A bell `side` px tall: dome, flared rim, the clapper under it and a knob on top."""
    w, h = round(side * 0.95), side
    layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    cx = w / 2
    knob = h * 0.10
    draw.ellipse((cx - knob * 0.55, 0, cx + knob * 0.55, knob * 1.1), fill=BELL_SHADE)
    top, rim = h * 0.09, h * 0.76
    draw.pieslice((cx - w * 0.30, top, cx + w * 0.30, top + w * 0.60), 180, 360, fill=BELL)
    draw.polygon([(cx - w * 0.30, top + w * 0.30), (cx + w * 0.30, top + w * 0.30),
                  (cx + w * 0.47, rim), (cx - w * 0.47, rim)], fill=BELL)
    draw.rounded_rectangle((cx - w * 0.50, rim - h * 0.02, cx + w * 0.50, rim + h * 0.08), round(h * 0.05), fill=BELL_SHADE)
    clapper = h * 0.085
    draw.ellipse((cx - clapper, rim + h * 0.07, cx + clapper, rim + h * 0.07 + clapper * 2), fill=BELL_SHADE)
    return layer


def compose():
    w, h = SIZE
    base = art.glow_field(SIZE, [
        (0.34, 0.55, 0.14, 0.30, art.TEAL, 0.55),
        (0.38, 0.45, 0.09, 0.22, art.LIME, 0.35),
        (0.06, 0.25, 0.16, 0.36, art.RED, 0.70),
        (0.94, 0.78, 0.16, 0.36, art.BLUE, 0.80),
        (0.80, 0.18, 0.10, 0.24, art.LIME, 0.40),
        (0.16, 0.90, 0.12, 0.26, art.ORANGE, 0.45),
    ])
    # Ten, glad, left of the middle.
    ten, box = art.ten_picture(os.path.join(art.ART, "ten"), round(h * 0.50))
    ten_w, ten_h = box[2] - box[0], box[3] - box[1]
    ten_cx, ten_cy = round(w * 0.36), round(h * 0.58)
    art.paste(base, ten, ten_cx - ten_w // 2 - box[0], ten_cy - ten_h // 2 - box[1])

    # The bubble above and right of Ten, its tail toward Ten's face.
    bw, bh = round(w * 0.30), round(h * 0.33)
    bx, by = round(w * 0.50), round(h * 0.17)
    left, top = bx - TAIL, by
    tip = (ten_cx + round(ten_w * 0.36) - left, ten_cy - round(ten_h * 0.28) - top)
    shape, _, mask = bubble((bw, bh), tip)
    # Frosted: the background under the bubble, blurred, shows through its glass.
    under = base.crop((left, top, left + shape.width, top + shape.height)).filter(ImageFilter.GaussianBlur(40))
    art.paste(base, Image.composite(under, Image.new("RGBA", shape.size, (0, 0, 0, 0)), mask), left, top)
    art.paste(base, shape, left, top)

    # Inside: the calendar page with a 2 and the bell beside it.
    page = calendar(round(bh * 0.58), "2")
    page_s, pad = art.shadowed(page, 24, opacity=0.45, offset=(0, 10))
    ring = bell(round(bh * 0.50))
    ring_s, rpad = art.shadowed(ring, 20, opacity=0.40, offset=(0, 8))
    gap = round(bw * 0.07)
    total = page.width + gap + ring.width
    x0 = bx + (bw - total) // 2
    art.paste(base, page_s, x0 - pad, by + (bh - page.height) // 2 - pad)
    art.paste(base, ring_s, x0 + page.width + gap - rpad, by + (bh - ring.height) // 2 - rpad)
    return art.to_image(base)


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--preview", help="also write a 1280x720 copy into this folder")
    parser.add_argument("--out", default=OUT)
    args = parser.parse_args()
    image = compose()
    image.save(args.out, optimize=True)
    print(f"{args.out}: {image.size[0]}x{image.size[1]}")
    if args.preview:
        os.makedirs(args.preview, exist_ok=True)
        preview = os.path.join(args.preview, "retention.png")
        image.resize((1280, 720), Image.LANCZOS).save(preview)
        print(preview)


if __name__ == "__main__":
    main()
