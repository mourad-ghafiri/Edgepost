#!/usr/bin/env python3
"""Composes the store screenshots from the raw captures.

`integration_test/store_screenshots_test.dart`, run through
`tool/store_screenshots.sh`, leaves raw captures in
`build/screenshots/raw/<device>/<NN-name>.png` (synthetic demo data from the
local fake API). This script turns them into the publishing sets under
`publish/screenshots/` (git-ignored, beside the publishing guides):

- App Store (`ios/`): every capture on the near-black of the app icon's
  tile, under a headline set like the app's large titles, each set composed
  at its own exact size. No alpha: App Store Connect rejects it.
  - `iphone-6.3`, 1206x2622: "iPhone with Dynamic Island (medium display)",
    the one iPhone size App Store Connect requires.
  - `iphone-6.9`, 1320x2868: "iPhone with Dynamic Island (large display)",
    optional, so the largest iPhones get their own set instead of a scaled
    one.
  - `ipad-13`, 2064x2752: "Required if app runs on iPad".
- Google Play phone (`android/phone/`): the same frame with the headline
  only (text stays far under a fifth of the image), at 1080x1920 (9:16, the
  size Play needs for promotion), eight shots (PLAY_SET).
- Google Play tablet (`android/tablet/`): the captures with no added text,
  as Play asks of large-screen screenshots, brought back to 9:16 where the
  capture left out the system bars.
- `android/feature-graphic.png` (1024x500, no alpha) and
  `android/icon-512.png` (32-bit PNG), from the app icon.

It checks every output against the store's rules and never deletes: a file
in a set's folder that is not part of the set stops it, naming the stray.

Sizes and rules:
- Apple: developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications
- Google Play: support.google.com/googleplay/android-developer/answer/9866151

Needs Pillow; the type is the app's own Inter (assets/fonts, SIL OFL 1.1).
"""

import pathlib
import sys

from PIL import Image, ImageDraw, ImageFont

ROOT = pathlib.Path(__file__).resolve().parent.parent
RAW = ROOT / 'build' / 'screenshots' / 'raw'
OUT = ROOT / 'publish' / 'screenshots'
FONTS = ROOT / 'assets' / 'fonts'
ICON = ROOT / 'tool' / 'icon' / 'edgepost_icon_1024.png'

# The app icon's tile, and type on it (DESIGN.md: ink, ink-muted-dark).
GROUND = (0x17, 0x18, 0x1C)
HEADLINE = (0xFF, 0xFF, 0xFF)
SUBLINE = (0xA2, 0xA6, 0xAE)

# Headline and subline per capture: what the screen shows, in the app's own
# words. No claims beyond what the app does, no calls to action.
CAPTIONS = {
    '01-today': ('What needs you, first', 'Every domain and account in one calm list'),
    '02-inbox': ('Mail on your own domains', 'One inbox for every address you route'),
    '03-thread': ('Read it where it lands', 'Threads, attachments and safe HTML'),
    '04-reply': ('Reply as you@yourdomain', 'Your signature and logo already in place'),
    '05-domains': ('Every domain at a glance', 'Status, plan and a week of requests'),
    '06-dns': ('DNS without the dashboard', 'Records, templates and a mail check'),
    '07-traffic': ('Know your traffic', 'Requests, bandwidth, cache and threats'),
    '08-controls': ('SSL, cache and security', 'Purge and Under Attack mode in reach'),
    '09-compute': ('Workers and Pages', 'Live logs, rollbacks and deployments'),
    '10-signature': ('A signature per domain', 'Set once, edit it on any message'),
}

# Apple accepts exact sizes only: (frame size, the raw capture folder).
APPLE = {
    # The required iPhone set ("At least one screenshot for iPhone with
    # Dynamic Island (medium display)"), composed from the 6.9" captures:
    # the two screens have the same shape.
    'iphone-6.3': ((1206, 2622), 'iphone-6.9'),
    'iphone-6.9': ((1320, 2868), 'iphone-6.9'),
    'ipad-13': ((2064, 2752), 'ipad-13'),
}

# Google Play's eight, in upload order: the controls list and the thread
# give way to the screens that show more at a glance.
PLAY_SET = [
    '01-today',
    '02-inbox',
    '04-reply',
    '05-domains',
    '06-dns',
    '07-traffic',
    '09-compute',
    '10-signature',
]
PLAY_PHONE = (1080, 1920)


def font(weight, size):
    return ImageFont.truetype(str(FONTS / f'Inter-{weight}.ttf'), size)


def rounded(image, radius):
    """[image] with its corners rounded, as an RGBA copy."""
    mask = Image.new('L', image.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, image.width - 1, image.height - 1), radius, fill=255)
    out = image.convert('RGBA')
    out.putalpha(mask)
    return out


def trim_top(image):
    """The capture without most of the empty band under the status bar (the
    captures hold the app's window, not the status bar). Only rows of one
    colour are removed, never content."""
    px = image.load()
    ref = px[image.width // 2, 0]
    rows = 0
    for y in range(image.height // 6):
        if any(max(abs(a - b) for a, b in zip(px[x, y], ref)) > 2 for x in range(0, image.width, 4)):
            break
        rows = y + 1
    keep = round(image.width * 0.045)  # a little air above the first line
    return image.crop((0, max(0, rows - keep), image.width, image.height))


def wrap(draw, text, face, width):
    """[text] in lines no wider than [width], broken between words."""
    lines = ['']
    for word in text.split():
        trial = f'{lines[-1]} {word}'.strip()
        if lines[-1] and draw.textlength(trial, font=face) > width:
            lines.append(word)
        else:
            lines[-1] = trial
    for line in lines:
        if draw.textlength(line, font=face) > width:
            sys.exit(f'"{line}" is wider than {width:.0f} px even on a line of its own')
    return lines


def frame(capture, size, headline, subline=None):
    """One store image: the capture under its caption on the tile's ground.
    Every frame of a set keeps the same caption area (two headline lines and
    a subline), its text set to the bottom of it, so the screens of a set
    all sit at the same size and height."""
    w, h = size
    out = Image.new('RGB', size, GROUND)
    draw = ImageDraw.Draw(out)
    margin = round(w * 0.075)
    width = w - 2 * margin
    head = font('Bold', round(w * 0.066))
    sub = font('Medium', round(w * 0.036))
    head_lh = round(head.size * 1.18)
    sub_gap, sub_lh = round(sub.size * 0.25), round(sub.size * 1.35)
    heads = wrap(draw, headline, head, width)
    subs = wrap(draw, subline, sub, width) if subline else []
    area = 2 * head_lh + (sub_gap + sub_lh if subline else 0)
    block = len(heads) * head_lh + (sub_gap + len(subs) * sub_lh if subs else 0)
    if block > area:
        sys.exit(f'caption "{headline}" / "{subline}" needs more than two lines and a subline')
    top = round(h * 0.05)
    y = top + area - block
    for line in heads:
        draw.text((margin, y), line, font=head, fill=HEADLINE)
        y += head_lh
    if subs:
        y += sub_gap
        for line in subs:
            draw.text((margin, y), line, font=sub, fill=SUBLINE)
            y += sub_lh
    y = top + area + round(h * 0.028)

    screen = trim_top(capture.convert('RGB'))
    bottom = round(h * 0.035)
    scale = min(width / screen.width, (h - y - bottom) / screen.height)
    screen = screen.resize((round(screen.width * scale), round(screen.height * scale)), Image.LANCZOS)
    screen = rounded(screen, round(screen.width * 0.07))
    out.paste(screen, ((w - screen.width) // 2, y), screen)
    return out


def fill_to_ratio(image):
    """A tablet capture at exactly 9:16: Flutter's capture leaves out the
    system bars, so the band they took is added back above the app, each
    column in its own top colour (no text, nothing the app does not show)."""
    w, h = image.size
    want = round(w * 16 / 9)
    if h >= want:
        return image
    out = Image.new('RGB', (w, want))
    # Each column's own top colour, carried up (the rail stays the rail).
    out.paste(image.crop((0, 0, w, 1)).resize((w, want - h)), (0, 0))
    out.paste(image, (0, want - h))
    return out


def check_play(size, minimum):
    w, h = size
    short, long_ = min(w, h), max(w, h)
    if not (320 <= short and long_ <= 3840):
        return f'{w}x{h}: each side must be 320-3840 px'
    if long_ > 2 * short:
        return f'{w}x{h}: the long side is more than twice the short side'
    if short < minimum:
        return f'{w}x{h}: under {minimum} px on the short side'
    if long_ * 9 != short * 16:
        return f'{w}x{h}: not 9:16 or 16:9'
    return None


def strays(folder, wanted):
    if folder.is_dir():
        extra = sorted(p.name for p in folder.iterdir() if p.name not in wanted)
        if extra:
            sys.exit(f'{folder.relative_to(ROOT)}: not in the set, remove first: {", ".join(extra)}')


def raws(device):
    folder = RAW / device
    shots = {p.stem: p for p in sorted(folder.glob('*.png'))} if folder.is_dir() else {}
    missing = [n for n in CAPTIONS if n not in shots]
    if missing:
        sys.exit(f'{device}: missing {", ".join(missing)} in {folder.relative_to(ROOT)}')
    return shots


def save(image, path):
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, optimize=True)
    print(f'{path.relative_to(ROOT)}  {image.size[0]}x{image.size[1]}')


def apple():
    for device, (size, source) in APPLE.items():
        shots = raws(source)
        target = OUT / 'ios' / device
        strays(target, {f'{n}.png' for n in CAPTIONS})
        for name, (headline, subline) in CAPTIONS.items():
            image = frame(Image.open(shots[name]), size, headline, subline)
            assert image.mode == 'RGB' and image.size == size
            save(image, target / f'{name}.png')


def play():
    phone = raws('android-phone')
    tablet = raws('android-tablet')
    picks = [(phone[n], tablet[n], f'{i:02d}-{n.split("-", 1)[1]}.png') for i, n in enumerate(PLAY_SET, 1)]
    strays(OUT / 'android' / 'phone', {p for _, _, p in picks})
    strays(OUT / 'android' / 'tablet', {p for _, _, p in picks})
    for name, (p, t, filed) in zip(PLAY_SET, picks):
        image = frame(Image.open(p), PLAY_PHONE, CAPTIONS[name][0])
        if problem := check_play(image.size, 1080):
            sys.exit(f'android/phone/{filed}: {problem}')
        save(image, OUT / 'android' / 'phone' / filed)
        raw = fill_to_ratio(Image.open(t).convert('RGB'))
        if problem := check_play(raw.size, 1080):
            sys.exit(f'android/tablet/{filed}: {problem}')
        save(raw, OUT / 'android' / 'tablet' / filed)


def play_graphics():
    icon = Image.open(ICON).convert('RGBA')
    save(icon.resize((512, 512), Image.LANCZOS), OUT / 'android' / 'icon-512.png')

    # Feature graphic: the icon and the name on the tile's ground, with the
    # store listing's line under it. No alpha, no device, no call to action.
    w, h = 1024, 500
    out = Image.new('RGB', (w, h), GROUND)
    draw = ImageDraw.Draw(out)
    mark = rounded(icon.resize((168, 168), Image.LANCZOS).convert('RGB'), 38)
    out.paste(mark, (96, (h - 168) // 2), mark)
    name = font('Bold', 88)
    line = font('Medium', 38)
    x = 96 + 168 + 56
    draw.text((x, h // 2 - 74), 'Edgepost', font=name, fill=HEADLINE)
    # Cloudflare's trademark guidelines: the referential "for Cloudflare",
    # with ® on its first use (cloudflare.com/trademark).
    draw.text((x, h // 2 + 34), 'Mail & DNS for Cloudflare®', font=line, fill=SUBLINE)
    save(out, OUT / 'android' / 'feature-graphic.png')


def main():
    if not RAW.is_dir():
        sys.exit(f'nothing to compose: {RAW.relative_to(ROOT)} does not exist')
    only = sys.argv[1] if len(sys.argv) > 1 else 'all'
    if only in ('ios', 'all'):
        apple()
    if only in ('android', 'all'):
        play()
        play_graphics()


if __name__ == '__main__':
    main()
