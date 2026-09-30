#!/usr/bin/env python3
"""Render `aartool paths` on the bundled sample as a still, for the repository
social preview and for a post.

The terminal text is captured from a real run through a pty and never retyped,
the same rule as make-help-image.py and for the same reason: a picture is the
one artefact nobody re-checks after a release, and a hand-typed one is a public
untruth the moment the output moves. A pty is required rather than a pipe,
because the tool renders in colour and sizes its layout only when stdout is a
terminal.

No version number appears here on purpose. Nothing in this image is generated
per release, so a version in it could only be typed by hand, and that is the
failure docs/MEDIA.md exists to prevent.

Usage:
  python3 scripts/make-social-image.py [--out FILE] [--post]

Needs Pillow and DejaVu Sans Mono:
  pip install Pillow
  apt install fonts-dejavu-core     # or dnf install dejavu-sans-mono-fonts
"""
import argparse
import os
import pty
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import termios
import fcntl

try:
    from PIL import Image, ImageDraw, ImageFont
except ImportError:
    sys.exit("Pillow is required: pip install Pillow")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FONT_DIRS = [
    "/usr/share/fonts/truetype/dejavu",          # Debian, Ubuntu
    "/usr/share/fonts/dejavu-sans-mono-fonts",   # Fedora, RHEL
    "/usr/share/fonts/dejavu",
]

# dashboard/index.html :root. One palette, everywhere.
BG, FG, MUTED = "#080d1a", "#e2e8f0", "#94a3b8"
ACCENT, WARN, DANGER = "#00e5b0", "#f59e0b", "#ef4444"
CYAN, BAR, RULE = "#7dd3fc", "#0d1526", "#1e293b"
SGR = {"31": DANGER, "32": ACCENT, "33": WARN, "36": CYAN, "34": "#3b82f6", "35": "#a78bfa"}

COLS = 100
TAGLINE = "Audit a Linux host. See how the findings chain into an attack. Cut one link."


def find_font(name):
    for d in FONT_DIRS:
        p = os.path.join(d, name)
        if os.path.exists(p):
            return p
    sys.exit(f"{name} not found. Install DejaVu Sans Mono.")


def capture():
    """`aartool paths` on the bundled sample, run in a pty COLS wide so the tool
    picks its wide layout and emits colour. Run from a scratch directory holding
    only the sample, so the provenance line the view prints carries no home
    directory, user name or host name, exactly as in record-paths.sh."""
    stage = tempfile.mkdtemp()
    try:
        shutil.copy(os.path.join(ROOT, "dashboard", "demo-audit.json"),
                    os.path.join(stage, "demo-audit.json"))
        pid, fd = pty.fork()
        if pid == 0:
            os.chdir(stage)
            os.environ["PATH"] = os.path.join(ROOT, "scripts") + os.pathsep + os.environ["PATH"]
            os.environ["TERM"] = "xterm-256color"
            os.execvp("aartool", ["aartool", "paths", "demo-audit.json"])
        fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 40, COLS, 0, 0))
        out = b""
        while True:
            try:
                chunk = os.read(fd, 65536)
            except OSError:
                break
            if not chunk:
                break
            out += chunk
        os.waitpid(pid, 0)
    finally:
        shutil.rmtree(stage, ignore_errors=True)
    text = out.decode("utf-8", "replace").replace("\r\n", "\n")
    if "COMPLETE" not in text:
        sys.exit("aartool paths produced no complete chain; refusing to render a still of nothing.")
    return text


def runs(line):
    """Split one line into (text, colour, bold) runs, from its SGR codes."""
    out, colour, bold, pos = [], FG, False, 0
    for m in re.finditer(r"\x1b\[([0-9;]*)m", line):
        if m.start() > pos:
            out.append((line[pos:m.start()], colour, bold))
        for code in (m.group(1) or "0").split(";"):
            if code in ("", "0"):
                colour, bold = FG, False
            elif code == "1":
                bold = True
            elif code in SGR:
                colour = SGR[code]
        pos = m.end()
    if pos < len(line):
        out.append((line[pos:], colour, bold))
    return out


def render(text, w, h):
    lines = [l.rstrip() for l in text.split("\n")]
    while lines and not lines[0].strip():
        lines.pop(0)
    while lines and not lines[-1].strip():
        lines.pop()
    plain = [re.sub(r"\x1b\[[0-9;]*m", "", l) for l in lines]
    widest = max(len(l) for l in plain)

    chrome, foot, pad = 46, 76, 30
    # The largest size that fits both ways. Derived, not chosen: a hand-picked
    # size is wrong the first time a chain name grows.
    fs = 8
    while fs < 40:
        probe = ImageFont.truetype(find_font("DejaVuSansMono.ttf"), fs + 1)
        adv, lh = probe.getlength("M"), int((fs + 1) * 1.42)
        if widest * adv + 2 * pad > w or chrome + foot + len(lines) * lh + 2 * pad > h:
            break
        fs += 1
    reg = ImageFont.truetype(find_font("DejaVuSansMono.ttf"), fs)
    bold = ImageFont.truetype(find_font("DejaVuSansMono-Bold.ttf"), fs)
    adv, lh = reg.getlength("M"), int(fs * 1.42)

    img = Image.new("RGB", (w, h), BG)
    d = ImageDraw.Draw(img)

    d.rectangle([0, 0, w, chrome], fill=BAR)
    for i, c in enumerate(("#ff5f57", "#febc2e", "#28c840")):
        x = 22 + i * 22
        d.ellipse([x, chrome // 2 - 6, x + 12, chrome // 2 + 6], fill=c)
    small = ImageFont.truetype(find_font("DejaVuSansMono.ttf"), 15)
    title = "aartool paths"
    d.text(((w - small.getlength(title)) / 2, chrome // 2 - 9), title, font=small, fill=MUTED)

    # Centre the block rather than pinning it left: the widest line is about
    # ninety columns and the canvas is wider than that, so left-pinned output
    # leaves a third of a social card empty on one side.
    left = max(pad, int((w - widest * adv) / 2))
    top = chrome + max(pad, int((h - chrome - foot - len(lines) * lh) / 2))
    for n, line in enumerate(lines):
        x, y = left, top + n * lh
        for txt, colour, is_bold in runs(line):
            d.text((x, y), txt, font=(bold if is_bold else reg), fill=colour)
            x += adv * len(txt)

    fy = h - foot
    d.line([pad, fy, w - pad, fy], fill=RULE, width=1)
    name = ImageFont.truetype(find_font("DejaVuSansMono-Bold.ttf"), 30)
    tag = ImageFont.truetype(find_font("DejaVuSansMono.ttf"), 14)
    d.text((pad, fy + 18), "aartool", font=name, fill=ACCENT)
    d.text((pad + name.getlength("aartool") + 18, fy + 28), TAGLINE, font=tag, fill=MUTED)
    home = "pkgs.cyberaar.io"
    d.text((w - pad - tag.getlength(home), fy + 28), home, font=tag, fill=MUTED)
    return img, fs


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", default="aartool-social.png", help="output PNG (default: %(default)s)")
    ap.add_argument("--post", action="store_true",
                    help="1200x675 for a post, instead of 1280x640 for the repository social preview")
    a = ap.parse_args()
    w, h = (1200, 675) if a.post else (1280, 640)
    img, fs = render(capture(), w, h)
    img.save(a.out)
    print(f"{a.out}  {img.width}x{img.height}  (font {fs}px)")


if __name__ == "__main__":
    main()
