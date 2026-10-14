#!/usr/bin/env python3
"""Derives the website's assets (docs/, served by GitHub Pages) from the rest
of the repository, so the site always shows the app as it is:

- the screens (docs/images/screens/): the raw store captures, scaled down to
  WebP, plus the iPhone in the app's dark appearance for the tour in dark
  mode. Re-shoot with `sh tool/store_screenshots.sh`, then run this tool;
- the icons (favicon.ico, favicon-32.png, apple-touch-icon.png, icon-192.png,
  icon-512.png) from the app icon that tool/icon draws;
- the social card (images/social-card.png, 1200x630);
- the fonts (docs/fonts/): the app's Inter at 600 and 700, cut down to Latin,
  as WOFF2, with its licence.

  python3 tool/website.py           # writes what changed
  python3 tool/website.py --check   # writes nothing; fails if anything is out of date

It never deletes: a file in docs/images or docs/fonts that it does not
produce (store badges in docs/images/badges aside) stops it, naming the file. Needs Pillow, fontTools and brotli.
"""

import io
import json
import pathlib
import sys

from fontTools import subset
from fontTools.ttLib import TTFont
from PIL import Image, ImageDraw, ImageFont
from PIL.PngImagePlugin import PngInfo

ROOT = pathlib.Path(__file__).resolve().parent.parent
SITE = ROOT / 'docs'
RAW = ROOT / 'build' / 'screenshots' / 'raw'
ICON = ROOT / 'tool' / 'icon' / 'edgepost_icon_1024.png'
FONTS = ROOT / 'assets' / 'fonts'

SCREENS = [
    '01-today', '02-inbox', '03-thread', '04-reply', '05-domains',
    '06-dns', '07-traffic', '08-controls', '09-compute', '10-signature',
]

# Device class: (raw capture folder, width on the site in pixels; 2x the
# CSS width the page shows it at).
DEVICES = {
    'iphone': ('iphone-6.9', 660),
    'ipad': ('ipad-13', 1032),
    'android': ('android-phone', 540),
}

# Screens the tour shows in dark mode only (no strip of their own).
TOUR_DARK = {'iphone-dark': ('iphone-6.9-dark', 660)}

# What each screen shows, for its alt text and the viewer's caption.
ALTS = {
    '01-today': 'Today: the domains and the sending budget that need a look, each with its reason, above new mail',
    '02-inbox': 'The inbox: mail to several addresses on the user\'s domains',
    '03-thread': 'A message with a PDF invoice attached',
    '04-reply': 'A reply from contact@ on the user\'s domain, with the domain\'s signature and logo',
    '05-domains': 'The domains: status, plan and requests over seven days',
    '06-dns': 'A domain\'s DNS records, grouped by type',
    '07-traffic': 'Seven days of traffic for a domain',
    '08-controls': 'A domain\'s SSL, cache and security settings',
    '09-compute': 'Workers, Pages and registered domains',
    '10-signature': 'A domain\'s signature and logo, with a preview',
}
CAPTIONS = {
    '01-today': 'Today', '02-inbox': 'Inbox', '03-thread': 'A message', '04-reply': 'Replying',
    '05-domains': 'Domains', '06-dns': 'DNS records', '07-traffic': 'Traffic',
    '08-controls': 'SSL, cache and security', '09-compute': 'Compute', '10-signature': 'Signature and logo',
}
LABELS = {'iphone': 'iPhone', 'ipad': 'iPad', 'android': 'Android'}

GROUND = (0x17, 0x18, 0x1C)
LATIN = 'U+0000-00FF,U+0131,U+0152-0153,U+02BB-02BC,U+02C6,U+02DA,U+02DC,U+2000-206F,U+2074,U+20AC,U+2122,U+2190-2199,U+2212,U+2215'


def webp(image, quality=82):
    buf = io.BytesIO()
    image.save(buf, 'WEBP', quality=quality, method=6)
    return buf.getvalue()


# Every raster says where it came from (Impeccable's provenance): a PNG in
# its own text chunk, a WebP in a sidecar beside it. None is generated art.
ICON_ORIGIN = ('Origin: the Edgepost app icon, tool/icon/edgepost_icon_1024.png, drawn from '
               'lib/core/widgets/brand_mark.dart; scaled by tool/website.py.')


def png(image, origin):
    info = PngInfo()
    info.add_text('impeccable:prompt', origin)
    buf = io.BytesIO()
    image.save(buf, 'PNG', optimize=True, pnginfo=info)
    return buf.getvalue()


def sidecar(origin):
    return (json.dumps({'prompt': origin}, indent=2) + '\n').encode()


def screens():
    out = {}
    for device, (folder, width) in {**DEVICES, **TOUR_DARK}.items():
        for name in SCREENS:
            raw = RAW / folder / f'{name}.png'
            if not raw.exists():
                sys.exit(f'missing capture {raw.relative_to(ROOT)}: run sh tool/store_screenshots.sh first')
            image = Image.open(raw).convert('RGB')
            image = image.resize((width, round(image.height * width / image.width)), Image.LANCZOS)
            out[f'images/screens/{device}/{name}.webp'] = webp(image)
            out[f'images/screens/{device}/{name}.webp.json'] = sidecar(
                f'Origin: a capture of the Edgepost app ({folder}, {name}) by '
                'integration_test/store_screenshots_test.dart against the synthetic demo data of '
                'tool/fake_cf_api; scaled by tool/website.py.'
            )
    return out


def icons():
    icon = Image.open(ICON).convert('RGBA')
    out = {}
    for name, size in [('favicon-32.png', 32), ('apple-touch-icon.png', 180), ('icon-192.png', 192), ('icon-512.png', 512)]:
        image = icon.resize((size, size), Image.LANCZOS)
        if name == 'apple-touch-icon.png':
            image = image.convert('RGB')  # iOS rounds it; no alpha needed
        out[f'images/{name}'] = png(image, ICON_ORIGIN)
    buf = io.BytesIO()
    icon.save(buf, 'ICO', sizes=[(16, 16), (32, 32), (48, 48)])
    out['favicon.ico'] = buf.getvalue()
    return out


def social_card():
    w, h = 1200, 630
    card = Image.new('RGB', (w, h), GROUND)
    draw = ImageDraw.Draw(card)
    icon = Image.open(ICON).convert('RGB').resize((132, 132), Image.LANCZOS)
    mask = Image.new('L', icon.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, 131, 131), 30, fill=255)
    card.paste(icon, (88, 120), mask)
    bold = ImageFont.truetype(str(FONTS / 'Inter-Bold.ttf'), 76)
    medium = ImageFont.truetype(str(FONTS / 'Inter-Medium.ttf'), 34)
    draw.text((88, 300), 'Edgepost', font=bold, fill=(255, 255, 255))
    # Cloudflare's trademark guidelines: ® on the first use in text
    # (cloudflare.com/trademark), as on the website and the feature graphic.
    for i, line in enumerate(['Run your Cloudflare® domains,', 'and answer their mail.']):
        draw.text((88, 404 + i * 46), line, font=medium, fill=(0xA2, 0xA6, 0xAE))
    # The app beside it: the Today screen, cut by the card's bottom edge.
    screen = Image.open(RAW / 'iphone-6.9' / '01-today.png').convert('RGB')
    screen = screen.resize((380, round(screen.height * 380 / screen.width)), Image.LANCZOS)
    mask = Image.new('L', screen.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, screen.width - 1, screen.height + 60), 40, fill=255)
    card.paste(screen, (w - 380 - 96, 64), mask)
    return {
        'images/social-card.png': png(
            card,
            'Origin: composed by tool/website.py from the app icon, the Inter typeface and the '
            'iPhone Today capture (synthetic demo data).',
        )
    }


def fonts():
    out = {}
    for weight, name in [(600, 'SemiBold'), (700, 'Bold')]:
        # No save timestamp: the same input always makes the same file.
        font = TTFont(str(FONTS / f'Inter-{name}.ttf'), recalcTimestamp=False)
        options = subset.Options()
        options.flavor = 'woff2'
        options.layout_features = ['kern', 'liga', 'calt', 'tnum', 'case', 'ss01']
        sub = subset.Subsetter(options)
        sub.populate(unicodes=subset.parse_unicodes(LATIN))
        sub.subset(font)
        buf = io.BytesIO()
        font.flavor = 'woff2'
        font.save(buf)
        out[f'fonts/inter-{weight}.woff2'] = buf.getvalue()
    out['fonts/OFL.txt'] = (FONTS / 'Inter-OFL.txt').read_bytes()
    return out


def strips(sizes):
    """index.html with each device's strip of screens filled in, between its
    `<!-- screens:<device> -->` markers."""
    page = (SITE / 'index.html').read_text()
    for device in DEVICES:
        width, height = sizes[device]
        rows = []
        for name in SCREENS:
            src = f'images/screens/{device}/{name}.webp'
            rows.append(
                f'          <button class="shot" type="button" data-full="{src}" '
                f'data-caption="{LABELS[device]} · {CAPTIONS[name]}">\n'
                f'            <img src="{src}" width="{width}" height="{height}" loading="lazy" '
                f'alt="{LABELS[device]}: {ALTS[name]}." />\n'
                f'            <span>{CAPTIONS[name]}</span>\n'
                f'          </button>'
            )
        start, end = f'<!-- screens:{device} -->', f'<!-- /screens:{device} -->'
        a, b = page.index(start) + len(start), page.index(end)
        page = page[:a] + '\n' + '\n'.join(rows) + '\n          ' + page[b:]
    return {'index.html': page.encode()}


def main():
    check = '--check' in sys.argv
    shots = screens()
    sizes = {}
    for device in DEVICES:
        image = Image.open(io.BytesIO(shots[f'images/screens/{device}/01-today.webp']))
        sizes[device] = image.size
    wanted = {**shots, **icons(), **social_card(), **fonts(), **strips(sizes)}
    for folder in ('images', 'fonts'):
        base = SITE / folder
        if base.is_dir():
            for path in sorted(p for p in base.rglob('*') if p.is_file() and p.name != '.DS_Store'):
                rel = path.relative_to(SITE).as_posix()
                # Store badges are the stores' own files, placed by hand.
                if rel.startswith('images/badges/'):
                    continue
                if rel not in wanted:
                    sys.exit(f'docs/{rel}: not produced by this tool; remove it or add it here')
    stale = []
    for rel, data in wanted.items():
        path = SITE / rel
        if path.exists() and path.read_bytes() == data:
            continue
        stale.append(rel)
        if not check:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
            print(f'docs/{rel}  {len(data) // 1024} KB')
    if check and stale:
        sys.exit('out of date: ' + ', '.join(f'docs/{r}' for r in stale))
    print(f'{len(wanted)} files, {len(stale)} {"stale" if check else "written"}')


if __name__ == '__main__':
    main()
