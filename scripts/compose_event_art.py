#!/usr/bin/env python3
"""Compose the art of the App Store's in-app events: screenshots/art/events/<event>/.

    card.png      3840x2160 (16:9), the event card in search, on the product page and in Today.
    details.png   2160x3840 (9:16), the top of the event's own page.

No words in the art: the App Store sets the event's name, badge and short description over the
bottom of both, in the viewer's language, so one picture serves every locale and the lower part
stays quiet. The field and Ten are the store art's (scripts/compose_store_art.py): the dark
background with colour glows, Ten from screenshots/art/ten/. Each event has its own glows.
PNG without alpha: Apple refuses an alpha channel. asc.py push-app-event uploads them
(appstore/app-events.json names the files).

    python3 scripts/compose_event_art.py                 # every event below
    python3 scripts/compose_event_art.py year-review     # one
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import compose_store_art as art  # noqa: E402  (glow field, Ten, paste)

OUT = os.path.join(art.ART, "events")
TEN = os.path.join(art.ART, "ten")
CARD = (3840, 2160)
DETAILS = (2160, 3840)

# The glows of each event (cx, cy, rx, ry, colour, strength), in fractions of the picture.
EVENTS = {
    # The year in review: warm, festive (orange and red with a touch of lime).
    "year-review": [
        (0.70, 0.30, 0.16, 0.30, art.ORANGE, 0.75),
        (0.86, 0.62, 0.14, 0.30, art.RED, 0.70),
        (0.55, 0.18, 0.08, 0.18, art.LIME, 0.35),
        (0.18, 0.25, 0.18, 0.30, art.BLUE, 0.45),
    ],
    # January's record streak: cool and fresh (teal and blue with lime).
    "record-streak": [
        (0.70, 0.30, 0.16, 0.30, art.TEAL, 0.70),
        (0.86, 0.62, 0.14, 0.30, art.BLUE, 0.80),
        (0.56, 0.18, 0.08, 0.18, art.LIME, 0.45),
        (0.18, 0.25, 0.18, 0.30, art.RED, 0.40),
    ],
}


def mirrored(blobs):
    """The card's glows for the portrait page: x and y swap roles so the glow sits round Ten."""
    return [(cy * 0.9 + 0.05, cx * 0.8, ry, rx, colour, strength) for cx, cy, rx, ry, colour, strength in blobs]


def card(blobs):
    """Ten in the upper right two thirds: the App Store's text sits over the lower left."""
    w, h = CARD
    base = art.glow_field(CARD, blobs)
    ten, box = art.ten_picture(TEN, round(h * 0.56))
    tw, th = box[2] - box[0], box[3] - box[1]
    cx, cy = round(w * 0.66), round(h * 0.40)
    art.paste(base, ten, cx - tw // 2 - box[0], cy - th // 2 - box[1])
    return art.to_image(base)


def details(blobs):
    """Ten in the upper half: the event's name and description sit over the lower part."""
    w, h = DETAILS
    base = art.glow_field(DETAILS, mirrored(blobs))
    ten, box = art.ten_picture(TEN, round(w * 0.62))
    tw, th = box[2] - box[0], box[3] - box[1]
    cx, cy = w // 2, round(h * 0.34)
    art.paste(base, ten, cx - tw // 2 - box[0], cy - th // 2 - box[1])
    return art.to_image(base)


def main(names):
    for name in names or EVENTS:
        if name not in EVENTS:
            sys.exit(f"Unknown event {name!r}: {', '.join(EVENTS)}")
        folder = os.path.join(OUT, name)
        os.makedirs(folder, exist_ok=True)
        for kind, make in (("card", card), ("details", details)):
            path = os.path.join(folder, f"{kind}.png")
            make(EVENTS[name]).save(path, optimize=True)
            print(f"{os.path.relpath(path, art.ROOT)}  {os.path.getsize(path) // 1024} KB")


if __name__ == "__main__":
    main(sys.argv[1:])
