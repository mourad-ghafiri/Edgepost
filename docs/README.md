# The Edgepost website

Served by GitHub Pages from this folder at <https://edgepost.dev/>.
- `index.html` is the page about the app.
- `privacy.html` is the privacy policy. The app's Settings › About › Privacy policy and both store listings link to it.
- `legal.html` is the legal notice (*mentions légales*).
- `accessibility.html` is the accessibility statement.
- `404.html` is the not-found page.

It is a static site with no build step and no Jekyll (`.nojekyll`). Links
between pages are relative. Only `404.html` uses absolute paths from the
site root, because GitHub serves it at any depth. `CNAME` names the custom
domain.

## Publishing

In the repository's settings on GitHub: **Pages › Build and deployment ›
Source: Deploy from a branch**, branch `main`, folder `/docs`
([GitHub's guide](https://docs.github.com/en/pages/getting-started-with-github-pages/configuring-a-publishing-source-for-your-github-pages-site)).
Every push to `main` then republishes the site.

### The custom domain, edgepost.dev

The app (`lib/core/app_info.dart`), both store listings and every page here
use `https://edgepost.dev/`, so the domain must answer before a build or a
listing goes out. Set it up in this order
([GitHub, managing a custom domain](https://docs.github.com/en/pages/configuring-a-custom-domain-for-your-github-pages-site/managing-a-custom-domain-for-your-github-pages-site)):

1. **Verify the domain on your GitHub account.** "Verifying your domain
   stops other GitHub users from taking over your custom domain"
   ([GitHub](https://docs.github.com/en/pages/configuring-a-custom-domain-for-your-github-pages-site/verifying-your-custom-domain-for-github-pages)).
   Profile picture › **Settings** › **Pages** › **Add a domain**, enter
   `edgepost.dev`, then add the TXT record GitHub shows, named
   `_github-pages-challenge-mourad-ghafiri.edgepost.dev`, at your DNS host,
   and click **Verify**. Keep the record afterwards.
2. **Add it to the site.** Repository **Settings › Pages › Custom domain**:
   `edgepost.dev`, **Save**. When publishing from a branch, "this will create
   a commit that adds a `CNAME` file directly to the root of your source
   branch". This folder already has that `CNAME`; if GitHub adds a commit
   anyway, pull before your next push. GitHub warns to add the domain here
   before pointing DNS at it.
3. **DNS records** for `edgepost.dev`, at your DNS host:
   - `A`: `185.199.108.153`, `185.199.109.153`, `185.199.110.153`,
     `185.199.111.153`;
   - `AAAA`: `2606:50c0:8000::153`, `2606:50c0:8001::153`,
     `2606:50c0:8002::153`, `2606:50c0:8003::153`;
   - recommended: `www` as a `CNAME` to `mourad-ghafiri.github.io`, with no
     repository name. GitHub then redirects between the two;
   - no wildcard record: "We strongly recommend that you do not use wildcard
     DNS records".

   If the DNS is on Cloudflare, make these records **DNS only**: a proxied
   record "will be answered with Cloudflare anycast IP addresses"
   ([Cloudflare](https://developers.cloudflare.com/dns/proxy-status/)), not
   GitHub's, so the check below would not match. Check with
   `dig edgepost.dev +noall +answer -t A`; "DNS changes can take up to 24
   hours to propagate."
4. **Enforce HTTPS** in the same Pages settings, once GitHub offers it ("It
   can take up to 24 hours before this option is available"). On .dev, HTTPS
   is the only way in: the .dev domain "is included on the HSTS preload list,
   making HTTPS required on all connections to .dev websites and pages"
   ([Google Registry](https://www.registry.google/domains/dev/)). The site
   opens once GitHub has its certificate.
5. **Check** that `https://edgepost.dev/` and `https://edgepost.dev/privacy.html`
   open. GitHub's page does not say whether the old
   `mourad-ghafiri.github.io/Edgepost/` address redirects, so nothing should
   still point at it.

## What is generated, and why

`python3 tool/website.py` (from the repository root) derives everything that
comes from elsewhere in the repository:

- **The screens** (`images/screens/`), scaled to WebP from the raw store
  captures, and the three device strips in `index.html`, between the
  `<!-- screens:… -->` markers. The tour also has the iPhone in the app's
  dark appearance (`images/screens/iphone-dark/`), shown in dark mode. Re-shoot with `sh tool/store_screenshots.sh`,
  then run the tool, and the site shows the same screens as the stores.
- **The icons and the social card** from the app icon in `tool/icon/`.
- **The fonts**: the app's own Inter at 600 and 700, cut down to Latin, with
  its licence (`fonts/OFL.txt`).
- **Provenance**: every image says where it came from: a PNG in its
  `impeccable:prompt` text chunk, a WebP in the `.json` file beside it. None
  is generated art.

`python3 tool/website.py --check` writes nothing, and fails if anything is
out of date. Run it before every push that touches the site. The tool never
deletes: a file in `images/` or `fonts/` that it did not produce stops it, and
it names the file. It needs Pillow, fontTools and brotli.

## Rules the site keeps

- **Nothing loads from another site.** No web fonts from a CDN, no analytics,
  no embeds, no cookies, so there is no cookie banner. The one thing kept is
  the theme switch's pick, `theme` in the browser's localStorage, and only
  when a visitor picks Light or Dark. The privacy policy says all this ("This
  website"); keep the two true together.
- **Only true claims.** Every feature on the page is something the app does
  today, in the app's own words. The screens show synthetic demo data from the
  local fake API (`tool/fake_cf_api`), and the page says so. Never add
  ratings, user counts or testimonials that do not exist.
- **Independence from Cloudflare, said plainly.** Edgepost is not made,
  endorsed, sponsored or supported by Cloudflare, Inc. The site says so in
  the hero facts, the first FAQ item (`#independent`), the legal notice
  (`legal.html#independence`) and every footer, with Cloudflare's
  attribution statement. The app says it on its welcome screen and in
  Settings › About. Follow
  [Cloudflare's trademark guidelines](https://www.cloudflare.com/trademark/):
  - the name in words only: never its logo, or an orange that imitates it;
  - only referential phrases such as "for Cloudflare";
  - ® on the first use in each page's text (`<sup class="tm">®</sup>`), but
    never on the company, "Cloudflare, Inc.";
  - no possessive ("the Cloudflare API", not "Cloudflare's API");
  - no "Cloudflare" in `<title>`, meta tags or the JSON-LD: "Nor may third
    parties use Cloudflare marks in domain names, any search engine
    optimization, meta tags, search terms, code, or other misrepresentation."
- **The privacy policy describes the app as it is.** If the app starts
  sending anything anywhere new, change `privacy.html`, the App Store privacy
  answers and the Google Play Data safety form in the same change.
- **Store badges.** Until a listing is live, the page shows a plain "Coming
  soon" box for it. When it goes live, replace the box with the store's
  official badge, unmodified: Apple's from its
  [App Store marketing guidelines](https://developer.apple.com/app-store/marketing/guidelines/),
  Google's from the
  [Google Play badge guidelines](https://partnermarketinghub.withgoogle.com/brands/google-play/visual-identity/badge-guidelines/).
  Save it into `images/badges/` (add the path to `tool/website.py`'s
  allowed files) and link it to the listing.
- **Every page carries the same header and footer**, with
  `aria-current="page"` on its own footer link. A new page goes into
  `sitemap.xml`.
- **The accessibility statement only claims what was checked.** Re-check it,
  and its date, when a page, a colour or a script changes: contrast in both
  palettes, keyboard use, and every page at 320 px wide with no sideways
  scroll.

## Preview locally

```sh
python3 -m http.server 8000 --bind 127.0.0.1 --directory docs
# then open http://127.0.0.1:8000/
```
