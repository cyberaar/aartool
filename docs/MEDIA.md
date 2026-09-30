# Media

How to regenerate the terminal graphic used in release posts and announcements.

```bash
python3 scripts/make-help-image.py --out aartool-help.png
```

Needs Pillow and DejaVu Sans Mono:

```bash
pip install Pillow
sudo apt install fonts-dejavu-core      # or: sudo dnf install dejavu-sans-mono-fonts
```

`--scale 2` is the default and gives a crisp 2200px image; `--scale 1` halves it.

## Why it pipes from the tool

The text comes from a real `aartool --help` run and is never retyped. An
announcement image is the one artefact nobody re-checks after a release: it is
posted once, then lives on other people's timelines. A version number typed by
hand into a picture is wrong at the next release and nothing anywhere will fail.

The same reasoning produced the guard on the aartool figures on cyberaar.io.
That page had claimed 51 Ansible roles against a real 52, and 96 CIS controls
against a real 109, for an unknown period.

**Regenerate after every release**, before posting anything. The image carries
the version and the command list, and both move.

## Why PIL and not SVG

An SVG would be the obvious choice for something this geometric, and it does
not work here. Every SVG renderer tried substitutes a non-monospace font for the
box-drawing glyphs in the banner, so the characters stop tiling and the
letterforms turn to mush. Per-character grid placement and `textLength` with
`lengthAdjust="spacingAndGlyphs"` were both tried; both still broke, because
positioning cannot fix a glyph that is drawn wider than its cell.

PIL renders the glyphs with the font's own metrics, so the banner tiles the way
it does in a terminal.

If you change this, check the banner at full size before believing it. The
failure is obvious in the art and invisible in the code.

## The README recording

```bash
bash docs/media/record-paths.sh                       # writes docs/media/aartool-paths.cast
agg --font-size 14 --idle-time-limit 10 \
    --last-frame-duration 8 \
    docs/media/aartool-paths.cast docs/media/aartool-paths.gif
```

Needs `asciinema` and `agg`. `agg` is not packaged for Ubuntu or Fedora; take
the static binary from the asciinema/agg releases page.

`record-paths.sh` drives a 100x34 pty through two commands, `aartool paths` on
the bundled sample and then `aartool explain` on the link that view names, with
an eight second hold on each. It runs in a scratch directory holding only a copy
of `dashboard/demo-audit.json`, and puts `scripts/` first on PATH, so two things
are true at once: the text typed on screen is exactly the command that runs, and
no user name, host name or home directory reaches a frame. The provenance line
`paths` prints reads `demo-audit.json` and nothing more.

The colours live in the cast header, not in the `agg` command line, so the
palette travels with the recording. They are the dashboard's, from
`dashboard/index.html` `:root`.

**Regenerate it after any change to the `paths` or `explain` output.** It is the
first thing on the README, it is the only artefact here that shows the tool's
actual output rather than its help text, and nobody re-reads it after a release.
The same reasoning as the help image above, with a shorter fuse: `paths` is the
command most likely to change.

Two details that are easy to get wrong:

- **A cast records events, not silence.** A `sleep` after the last byte of
  output produces no event, so a trailing hold written into the driver is simply
  lost. The closing hold is `--last-frame-duration`.
- **`--idle-time-limit` must exceed the longest hold.** `agg` defaults to five
  seconds, which silently clips an eight second pause down to five and makes the
  recording unreadable at exactly the moment it matters.

## Stills

```bash
python3 scripts/make-social-image.py --out aartool-social.png    # 1280x640, repo social preview
python3 scripts/make-social-image.py --post --out aartool-post.png  # 1200x675, for a post
```

Same rule as everything else here: the terminal text is captured from a real run
through a pty and never retyped, so the picture cannot show output the tool does
not produce. The social preview is uploaded by hand in the repository settings;
nothing in CI can do it.
