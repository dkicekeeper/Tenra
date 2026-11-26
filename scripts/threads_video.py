#!/usr/bin/env python3
"""Short Threads videos recorded in the Simulator on the demo data (docs/plan-threads-videos.md).

    python3 scripts/threads_video.py record <id> [--no-build]  # build the UI tests, record the scene
    python3 scripts/threads_video.py edit <id> [--site]        # cut, caption, end card

A video is social/videos/<id>.json: the scene's test in TenraUITests/ThreadsVideoTests, its
segments in order (`from`/`to` are "<mark>@<seconds>", a THREADS-MARK step the test prints plus an
offset, or plain seconds into the recording; `speed`, optional; `caption`, or null to keep the one
before), and the end card's length. Marks keep a cut valid when the scene is recorded again.

`record` runs on the one booted iPhone Simulator (never a phone: the scene seeds the demo data),
in dark mode with the status bar at 9:41, and writes build/threads-videos/<id>/raw.mov and
marks.json. `edit` writes build/threads-videos/<id>/<id>.mp4, or with --site
docs/public/media/threads/<id>.mp4 (only after the founder said yes to the video): 9:16
1080x1920 H.264 30 fps with a silent AAC track, the screen large on Tenra's dark indigo and running
off the bottom edge (the tab bar and composer go, the content stays), Inter captions on top, the
first one there from the first frame, then Tenra's icon and "в App Store".
"""
import glob
import json
import os
import re
import signal
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SPECS = ROOT / "social" / "videos"
WORK = ROOT / "build" / "threads-videos"
SITE_DIR = ROOT / "docs" / "public" / "media" / "threads"
ICON = ROOT / "Tenra" / "Assets.xcassets" / "AppIcon.appiconset" / "App Icon3.png"
DERIVED = Path.home() / "Library" / "Developer" / "Xcode" / "DerivedData"
SITE_MAX_BYTES = 20 * 1024 * 1024   # scripts/threads.py VIDEO_MAX_BYTES

W, H = 1080, 1920
PW = 860                      # the screen's width on the canvas
PX, PY = (W - PW) // 2, 300   # its top-left corner; it runs off the bottom
RADIUS = 118                  # the screen's corner, scaled
FPS = 30
TOP, BOTTOM = (40, 34, 118), (7, 6, 20)   # deep indigo into black, for the app's dark theme
GLOW = (110, 100, 255, 255)                # indigo light behind the screen
EDGE = (255, 255, 255, 46)                 # a thin edge, so the black screen does not melt in

MARK = re.compile(r"THREADS-MARK (\S+) ([0-9.]+)")


# MARK: - Timeline (no Pillow, no ffmpeg: tested by scripts/test_threads_video.py)

def resolve(point, marks):
    """Seconds into the recording of "<mark>@<offset>" or a number."""
    if isinstance(point, (int, float)):
        return float(point)
    name, _, offset = point.partition("@")
    if name not in marks:
        raise ValueError(f"no mark {name!r} in the recording (has {', '.join(marks)})")
    return marks[name] + float(offset or 0)


def timeline(segments, marks):
    """[(from, to, speed)] in the recording and [(caption, start, end)] in the video."""
    cuts, captions, t = [], [], 0.0
    for s in segments:
        start, end, speed = resolve(s["from"], marks), resolve(s["to"], marks), s.get("speed", 1.0)
        if end <= start:
            raise ValueError(f"segment {s} ends before it starts")
        dur = (end - start) / speed
        if s.get("caption") is not None or not captions:
            captions.append((s.get("caption"), t, t + dur))
        else:
            text, begin, _ = captions[-1]
            captions[-1] = (text, begin, t + dur)
        cuts.append((start, end, speed))
        t += dur
    return cuts, captions


def marks_from_log(lines, started):
    """The test's THREADS-MARK steps as seconds after the recording started."""
    marks = {}
    for line in lines:
        m = MARK.search(line)
        if m:
            marks[m.group(1)] = round(float(m.group(2)) - started, 3)
    return marks


def load_spec(vid):
    path = SPECS / f"{vid}.json"
    if not path.is_file():
        sys.exit(f"no {path.relative_to(ROOT)}")
    return json.loads(path.read_text(encoding="utf-8"))


# MARK: - Record

def booted_iphone():
    out = subprocess.run(["xcrun", "simctl", "list", "devices", "booted", "-j"],
                         capture_output=True, text=True, check=True).stdout
    devices = [d for runtime in json.loads(out)["devices"].values() for d in runtime
               if d.get("state") == "Booted" and d["name"].startswith("iPhone")]
    if len(devices) != 1:
        sys.exit("boot exactly one iPhone Simulator (iPhone 18 Pro, iOS 27.0) and close other apps on it")
    return devices[0]["udid"]


def record(vid, build=True):
    spec = load_spec(vid)
    udid = booted_iphone()
    out = WORK / vid
    out.mkdir(parents=True, exist_ok=True)
    subprocess.run(["xcrun", "simctl", "ui", udid, "appearance", "dark"], check=True)
    subprocess.run(["xcrun", "simctl", "status_bar", udid, "override", "--time", "9:41",
                    "--dataNetwork", "wifi", "--wifiBars", "3", "--cellularBars", "4",
                    "--batteryState", "charged", "--batteryLevel", "100"], check=True)
    destination = f"platform=iOS Simulator,id={udid}"
    if build:
        with open(out / "build.log", "w") as log:
            built = subprocess.run(["xcodebuild", "build-for-testing", "-scheme", "Tenra",
                                    "-destination", destination], cwd=ROOT, stdout=log, stderr=subprocess.STDOUT)
        if built.returncode:
            sys.exit(f"build failed: {out / 'build.log'}")
    runs = sorted(glob.glob(str(DERIVED / "Tenra-*" / "Build" / "Products" / "Tenra_Tenra_iphonesimulator*.xctestrun")),
                  key=os.path.getmtime)
    if not runs:
        sys.exit("no built UI tests: run without --no-build")

    raw = out / "raw.mov"
    recorder = subprocess.Popen(["xcrun", "simctl", "io", udid, "recordVideo", "--codec", "h264", "--force", str(raw)],
                                stderr=subprocess.PIPE, text=True)
    started = None
    for line in recorder.stderr:
        if "Recording started" in line:
            started = time.time()
            break
    if started is None:
        sys.exit("the Simulator did not start recording")
    with open(out / "test.log", "w") as log:
        tested = subprocess.run(["xcodebuild", "test-without-building", "-xctestrun", runs[-1],
                                 "-destination", destination, "-parallel-testing-enabled", "NO",
                                 f"-only-testing:TenraUITests/ThreadsVideoTests/{spec['test']}"],
                                cwd=ROOT, stdout=log, stderr=subprocess.STDOUT)
    time.sleep(1)
    recorder.send_signal(signal.SIGINT)
    recorder.wait(timeout=60)

    with open(out / "test.log") as log:
        marks = marks_from_log(log, started)
    (out / "marks.json").write_text(json.dumps(marks, indent=1))
    print(json.dumps(marks, indent=1))
    if tested.returncode:
        sys.exit(f"the scene failed: {out / 'test.log'}")
    print(f"{raw.relative_to(ROOT)}: look at it, then edit {vid}")


# MARK: - Edit

def inter():
    found = glob.glob(str(DERIVED / "Tenra-*" / "SourcePackages" / "checkouts" / "DesignKit" / "Sources" /
                          "DesignTokens" / "Resources" / "Fonts" / "Inter-VariableFont_opsz,wght.ttf"))
    if not found:
        sys.exit("Inter not found: build Tenra once so DesignKit is checked out")
    return found[0]


def font(size, weight):
    from PIL import ImageFont
    f = ImageFont.truetype(inter(), size)
    f.set_variation_by_axes([32, weight])
    return f


def gradient():
    from PIL import Image
    column = Image.new("RGB", (1, H))
    for y in range(H):
        k = y / (H - 1)
        column.putpixel((0, y), tuple(round(TOP[i] + (BOTTOM[i] - TOP[i]) * k) for i in range(3)))
    return column.resize((W, H))


def frame_layer(path):
    """The background over everything but the screen: a hole with rounded top corners, a glow, an edge."""
    from PIL import Image, ImageDraw, ImageFilter
    bg = gradient().convert("RGBA")
    glow = Image.new("L", (W, H), 0)
    ImageDraw.Draw(glow).rounded_rectangle([PX, PY, PX + PW, H + 400], RADIUS, fill=120)
    bg = Image.composite(Image.new("RGBA", (W, H), GLOW), bg, glow.filter(ImageFilter.GaussianBlur(70)))
    s = 4
    edge = Image.new("RGBA", (W * s, H * s), (0, 0, 0, 0))
    ImageDraw.Draw(edge).rounded_rectangle([(PX - 3) * s, (PY - 3) * s, (PX + PW + 3) * s, (H + 400) * s],
                                           (RADIUS + 3) * s, fill=EDGE)
    bg.alpha_composite(edge.resize((W, H), Image.LANCZOS))
    hole = Image.new("L", (W * s, H * s), 255)
    ImageDraw.Draw(hole).rounded_rectangle([PX * s, PY * s, (PX + PW) * s, (H + 400) * s], RADIUS * s, fill=0)
    bg.putalpha(hole.resize((W, H), Image.LANCZOS))
    bg.save(path)


def wrap(measure, text, width):
    """One line when it fits, else two lines of about the same width (no lone word below)."""
    if measure(text) <= width:
        return [text]
    words = text.split()
    splits = []
    for k in range(1, len(words)):
        a, b = " ".join(words[:k]), " ".join(words[k:])
        widest = max(measure(a), measure(b))
        if widest <= width:
            splits.append((widest, [a, b]))
    if not splits:
        raise ValueError(f"caption too long for two lines: {text!r}")
    return min(splits)[1]


def caption_layer(text, path):
    from PIL import Image, ImageDraw
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    f = font(74, 800)
    lines = wrap(lambda s: d.textlength(s, font=f), text, W - 120)
    step = 88
    y = (PY - step * len(lines)) // 2 + 4
    for line in lines:
        d.text((W / 2, y), line, font=f, fill="white", anchor="mt")
        y += step
    img.save(path)


def endcard(path):
    from PIL import Image, ImageDraw, ImageFilter
    img = gradient().convert("RGBA")
    size, top = 360, 640
    icon = Image.open(ICON).convert("RGBA").resize((size, size), Image.LANCZOS)
    mask = Image.new("L", (size * 4, size * 4), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, size * 4 - 1, size * 4 - 1], int(size * 4 * 0.2237), fill=255)
    icon.putalpha(mask.resize((size, size), Image.LANCZOS))
    glow = Image.new("L", (W, H), 0)
    ImageDraw.Draw(glow).rounded_rectangle([(W - size) // 2, top + 18, (W + size) // 2, top + size + 18], 80, fill=120)
    img = Image.composite(Image.new("RGBA", (W, H), GLOW), img, glow.filter(ImageFilter.GaussianBlur(30)))
    img.alpha_composite(icon, ((W - size) // 2, top))
    d = ImageDraw.Draw(img)
    d.text((W / 2, top + size + 90), "Tenra", font=font(96, 800), fill="white", anchor="mt")
    d.text((W / 2, top + size + 210), "в App Store", font=font(64, 600), fill=(225, 223, 255), anchor="mt")
    img.save(path)


def ffmpeg(*args):
    subprocess.run(["ffmpeg", "-v", "error", "-y", *args], check=True)


def edit(vid, site=False):
    spec = load_spec(vid)
    work = WORK / vid
    raw, marks_file = work / "raw.mov", work / "marks.json"
    if not raw.is_file() or not marks_file.is_file():
        sys.exit(f"no recording: record {vid} first")
    cuts, captions = timeline(spec["segments"], json.loads(marks_file.read_text()))

    # The recording is variable frame rate (a frame on each change) and its first timestamps are
    # odd: converted whole it came out ~4 s off the marks. Each segment is cut with an input seek,
    # which matches them, into constant 30 fps at the screen's width.
    parts = work / "parts"
    parts.mkdir(exist_ok=True)
    inputs = []
    for i, (start, end, _) in enumerate(cuts):
        p = parts / f"seg{i}.mp4"
        ffmpeg("-ss", f"{start:.3f}", "-i", str(raw), "-vf",
               f"fps={FPS}:start_time=0,scale={PW}:-2:flags=lanczos,tpad=stop_mode=clone:stop_duration=5",
               "-t", f"{end - start:.3f}", "-c:v", "libx264", "-crf", "12", "-preset", "fast",
               "-pix_fmt", "yuv420p", str(p))
        inputs += ["-i", str(p)]
    n = len(cuts)
    frame_layer(parts / "frame.png")
    inputs += ["-loop", "1", "-framerate", str(FPS), "-i", str(parts / "frame.png")]
    for i, (text, _, _) in enumerate(captions):
        caption_layer(text, parts / f"caption{i}.png")
        inputs += ["-loop", "1", "-framerate", str(FPS), "-i", str(parts / f"caption{i}.png")]
    endcard(parts / "end.png")
    end_input = n + 1 + len(captions)
    inputs += ["-loop", "1", "-framerate", str(FPS), "-i", str(parts / "end.png"),
               "-f", "lavfi", "-i", "anullsrc=channel_layout=stereo:sample_rate=48000"]

    body = captions[-1][2]
    total = body + spec["endcard"]
    g = [f"[{i}:v]setpts=(PTS-STARTPTS)/{speed},fps={FPS},setsar=1[s{i}]" for i, (_, _, speed) in enumerate(cuts)]
    g.append("".join(f"[s{i}]" for i in range(n)) + f"concat=n={n}:v=1:a=0,"
             f"tpad=stop_mode=clone:stop_duration={spec['endcard'] + 1},"
             f"crop={PW}:{H - PY}:0:0,pad={W}:{H}:{PX}:{PY}:color=black,setsar=1[ph]")
    g.append(f"[ph][{n}:v]overlay=0:0[l0]")
    last = "l0"
    for i, (_, start, end) in enumerate(captions):
        # The first caption is there from the first frame (Threads' preview); the others fade in.
        fade = f",fade=t=in:st={start:.3f}:d=0.3:alpha=1" if start > 0 else ""
        g.append(f"[{n + 1 + i}:v]format=rgba{fade}[c{i}]")
        g.append(f"[{last}][c{i}]overlay=0:0:enable='between(t,{start:.3f},{end:.3f})'[l{i + 1}]")
        last = f"l{i + 1}"
    g.append(f"[{end_input}:v]format=rgba,fade=t=in:st={body:.3f}:d=0.4:alpha=1[e]")
    g.append(f"[{last}][e]overlay=0:0:enable='gte(t,{body:.3f})',format=yuv420p[v]")

    out = (SITE_DIR if site else work) / f"{vid}.mp4"
    out.parent.mkdir(parents=True, exist_ok=True)
    ffmpeg(*inputs, "-filter_complex", ";".join(g), "-map", "[v]", "-map", f"{end_input + 1}:a",
           "-t", f"{total:.3f}", "-c:v", "libx264", "-preset", "slow", "-crf", "20", "-profile:v", "high",
           "-r", str(FPS), "-g", str(FPS * 2), "-c:a", "aac", "-b:a", "64k",
           "-movflags", "+faststart", "-use_editlist", "0", str(out))
    size = out.stat().st_size
    print(f"{out.relative_to(ROOT)}: {total:.1f} s, {size / 1024 / 1024:.1f} MB")
    for text, start, end in captions:
        print(f"  {start:5.2f}-{end:5.2f}  {text}")
    if not 15 <= total <= 25:
        print(f"  ! {total:.1f} s, the plan asks for 15-25")
    if size > SITE_MAX_BYTES:
        sys.exit(f"  ! over {SITE_MAX_BYTES // 1024 // 1024} MB, Threads will not take it")


def main(argv):
    if len(argv) < 2 or argv[0] not in ("record", "edit"):
        sys.exit(__doc__)
    if argv[0] == "record":
        record(argv[1], build="--no-build" not in argv)
    else:
        edit(argv[1], site="--site" in argv)


if __name__ == "__main__":
    main(sys.argv[1:])
