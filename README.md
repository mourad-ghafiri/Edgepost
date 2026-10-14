# Edgepost

Edgepost is a phone-first control room for your Cloudflare® domains, on iOS and Android, built with Flutter:

- every zone of a Cloudflare account, with its DNS (several accounts, one on screen at a time)
- SSL, cache and security controls
- traffic analytics
- Workers and Pages
- Registrar renewals
- **a real mailbox on each domain**: receive, read, reply, reply all, forward and send

There is no Edgepost server. The app talks only to `api.cloudflare.com` and to a small mail Worker it deploys into **your own** Cloudflare account. Your tokens stay in the device keychain/keystore.

> **Independent app.** Edgepost isn't made, endorsed, sponsored or supported by Cloudflare, Inc., and isn't affiliated with it. It works through the public Cloudflare API with a token you create in your own account. For help with Edgepost, [open an issue](https://github.com/mourad-ghafiri/Edgepost/issues) or email contact@edgepost.dev, not Cloudflare support.

## How mail works

Cloudflare has no mailbox, so Edgepost ships one as a Worker (`mail_worker/`, contract in `mail_worker/API.md`).

```
Sender ──▶ Email Routing (MX on your domain) ──▶ Worker email() ──▶ D1 (index, search) + R2 (raw .eml, attachments)
App ──HTTPS + bearer key──▶ Worker fetch() /v1/* ──▶ Email Sending (env.EMAIL.send) for send / reply / forward
```

**One-tap setup in the app** (Mail → Set up mailbox) does all of this in your account:

1. Creates the D1 database and R2 bucket.
2. Uploads the Worker.
3. Publishes it on workers.dev.
4. Schedules a daily trash clean-up.
5. Turns on Email Routing for the domains you pick (catch-all or chosen addresses).
6. Onboards those domains to Email Sending. Cloudflare publishes and locks the sending DNS records itself; the app never edits them.
7. Runs a Mail DNS check that flags duplicate DMARC/SPF records.

**Replies thread correctly.** The Worker sets `In-Reply-To` and `References`, both on Email Sending's header allowlist, and stores the `Message-ID` Cloudflare returns.

**Signature and logo per domain.** Mail → Mail service → a domain → *Signature & logo*. Every message from that domain ends with them; in compose, the signature can be edited for one message and the logo left out. The logo is a small PNG kept in your Worker (R2) and attached **inline** (Content-ID), so recipients see it without loading remote images.

**Recipient suggestions.** In To, Cc and Bcc, one tap each, nothing filled in on its own:
- an empty field offers the people you've sent to most (from your Worker's sent mail, so every device agrees), recent ones first
- typing matches names (accents or not) and addresses
- after `@`, the domain is completed: domains you write to first, then the big providers, then those common in your device's region (about 250 webmail and ISP domains)
- a mistyped provider (`gmial.com`, `hotmial.fr`) is offered fixed

**Requirements (one-time, in the Cloudflare dashboard):**
- The domain uses Cloudflare DNS. Email Service requires it: https://developers.cloudflare.com/email-service/get-started/send-emails/
- R2 is turned on: Storage & databases → R2 → Overview → complete the checkout. The free tier is included: https://developers.cloudflare.com/r2/get-started/
- The account has a workers.dev subdomain. If setup reports none, open Workers & Pages once.
- To send to *any* address: the Workers Paid plan. Email Sending is in public beta. Receiving works on every plan.

**Token permissions.** Names are from https://developers.cloudflare.com/fundamentals/api/reference/permissions/. Set the token's resources to *All accounts* and *All zones*:
- Account: Workers Scripts Edit, D1 Edit, Workers R2 Storage Edit, Email Routing Addresses Edit, Cloudflare Pages Edit, Workers Tail Read, Account Settings Read, Billing Read (for the Budget card's usage cost; without it the card shows emails sent only).
- Zone: Zone Read, Zone Settings Edit, DNS Edit, Cache Purge, Analytics Read, Email Routing Rules Edit, Workers Routes Edit, DMARC Management Read.
- If the token editor offers **Email Sending**, add Edit. The permissions page doesn't list it, so this is unverified.

### Accounts and tokens

- An **account** is a Cloudflare account. An **API token** is a key that reaches one or more accounts; the app picks, per feature, the token whose permissions allow it.
- With one account the app stays focused on it. A second one is added from the avatar at the top right (**+**), or Settings → Add account: accounts your stored tokens already reach are one tap; a new token is verified, then you choose which of its accounts to add.
- Switching: tap the avatar and pick an account, or long-press it to go back to the previous one. Tab badges are for the account on screen; a dot on the avatar and the switcher's counts show what the others have waiting.
- Settings → an account shows its tokens (expiry, permissions, check again, remove) and its mail service. **Remove from Edgepost** changes nothing in Cloudflare; a token is deleted from the device once no added account needs it.

### Costs and the sending budget

Edgepost is built to stay inside the $5 Workers Paid plan. Figures are from https://developers.cloudflare.com/workers/platform/pricing/ and https://developers.cloudflare.com/email-service/platform/pricing/.

| What | Included | Edgepost's typical use |
|---|---|---|
| Cloudflare API calls from the app | free (rate-limited only) | live refresh while on screen: lists every 60 s, analytics and billing every 5 min, ×4 slower when a token's request budget runs low |
| Worker requests | 10 M / month | about 720 per hour per account with a mailbox while the app is open (mail and sending budget every 5 s), plus background checks every ≥15 min |
| D1 | 25 B rows read, 50 M written, 5 GB | tiny |
| R2 | 10 GB, 1 M Class A, 10 M Class B / month | a few objects per received mail |
| Email Routing (receiving) | unlimited | n/a |
| **Email Sending** | **3,000 / month, then $0.35 per 1,000, no spending cap** | **capped by the mail service** |

The mail service refuses to send past its **monthly sending limit**:
- The default is 3,000, the included amount. You can lower it, or set Off, in Mail → Mail service.
- It counts every recipient over a rolling 31-day window.
- Failed sends Cloudflare may still have billed are counted too.
- Refused sends never reach Cloudflare, so they cost nothing.

## Project layout

| Path | What |
|---|---|
| `lib/core/` | `CfClient` (v4 envelope, pagination, rate limiter, GraphQL), secure storage, offline cache, adaptive widget kit, strip components, theme tokens |
| `lib/features/<feature>/` | `data/` (API, models, Riverpod providers) and `presentation/` (screens); each feature exposes its routes file |
| `lib/app/` | router (go_router, tab shell), app root |
| `l10n/fragments/*_en.arb` | strings per feature, merged by `tool/merge_arb.dart` into `lib/l10n/app_en.arb` |
| `mail_worker/` | TypeScript mail Worker and its vitest suite (local Miniflare only) |
| `assets/worker/` | bundled Worker plus `manifest.json` (built by `tool/build_worker.sh`) |
| `tool/fake_cf_api/server.dart` | local fake Cloudflare API and mail Worker with synthetic demo data |
| `tool/icon/` | the Signpost mark (`lib/core/widgets/brand_mark.dart`) rendered to every iOS/Android icon, launch and notification size: `bash tool/icon/make_icons.sh` |
| `assets/fonts/` | Inter (SIL OFL 1.1) for titles and numbers; body text stays on the system face |
| `docs/` | the website, served by GitHub Pages (see `docs/README.md`) |


## Develop

```sh
flutter pub get
dart run tool/merge_arb.dart && flutter gen-l10n     # after editing any l10n fragment
flutter analyze
flutter test                                         # unit + widget tests (iOS and Android idioms)
bash tool/build_worker.sh                            # test, typecheck and bundle the mail Worker → assets/worker/
```

Run against the **local fake API** (no Cloudflare account touched):

```sh
dart run tool/fake_cf_api/server.dart &
flutter run --dart-define=CF_API_BASE=http://127.0.0.1:8789/client/v4 \
            --dart-define=MAIL_WORKER_URL=http://127.0.0.1:8789
# Android emulator: use 10.0.2.2 instead of 127.0.0.1
```

Any token works with the fake API; its text picks the accounts it reaches: one containing `ember` reaches *Studio Ember*, `agency` or `both` reaches both demo accounts, anything else *Atelier Nord*. `curl -X POST 'http://127.0.0.1:8789/_demo/arrive?account=ember'` delivers a message (drop the query for Atelier Nord).

End-to-end flow with screenshots (written to `.impeccable/review/`):

```sh
flutter drive --driver=test_driver/integration_test.dart --target=integration_test/app_flow_test.dart -d <device> \
  --dart-define=CF_API_BASE=http://127.0.0.1:8789/client/v4 --dart-define=MAIL_WORKER_URL=http://127.0.0.1:8789
```

## First test on your real account

All automated tests run against fakes. The first real run is yours:

1. Do the one-time dashboard steps above (R2, token permissions).
2. Run the app normally (`flutter run`, no dart-defines). Add the token and check the permission checklist:
   - ✓ available
   - ✗ missing, with the exact permission to add
   - ⚠ turn on in the dashboard
   - ⓘ not confirmed yet; it's re-checked when used
3. Toggle Development mode on the test domain and back.
4. Mail → Set up mailbox. Pick the test domain. Then send a message from another mailbox to `anything@yourdomain`. It should appear within seconds.
5. Reply to it from the app and check that the reply lands **threaded** in the other mailbox.
6. Send a message with a photo or PDF attachment (up to about 3.6 MB raw; the app shows the size as sent).
7. Add **Billing Read** to the token, then Settings → your account → Check again: the Budget card on Today shows this period's usage cost.
8. With the app open on another tab, send yourself a message: within about 5 s the Mail tab badge and an in-app banner appear. Turn on alerts (the offer above the inbox, or Settings → Notifications) to get them when the app is closed too.
9. If you have a second Cloudflare account: add it from the avatar (**+**), switch with a tap, and switch back with a long-press. Mail arriving in the account not on screen shows "New mail in …"; Open switches there.
10. Mail service → the test domain → Signature & logo: add both, then send yourself a message. The logo shows inline in the other mailbox (and in Sent).
11. Start a new message: the address you just wrote to is offered under To.

**Docs gaps to watch.** These points aren't spelled out in the Cloudflare docs. The code handles each defensively; please report what you see:
- the Email Routing `worker` action value: the script name is assumed
- whether onboarding through the API publishes the sending records right away. Cloudflare manages and locks these records ([docs](https://developers.cloudflare.com/email-service/configuration/domains/)), so the app only reports any that are still missing and never writes them. Missing records can be finished under Compute → Email Service → Email Sending.

## Before store submission

- [ ] `flutter doctor --android-licenses` (one time, interactive)
- [ ] Android release signing config in `android/app/build.gradle.kts` (currently debug keys)
- [ ] Archive iOS with `flutter build ipa`, not straight from Xcode after an e2e run: `ios/Flutter/Generated.xcconfig` then still carries the fake API's dart-defines
- [ ] App Store Connect / Play Console listings:
  - "for Cloudflare" wording, no Cloudflare logo
  - privacy: *Data not collected*
  - App Review demo: a test token with read access to a demo account
- [ ] Store screenshots re-shot after any UI change (below), and the website regenerated from them

## Store screenshots

```sh
sh tool/store_screenshots.sh [ios|android|all]
```

The script runs `integration_test/store_screenshots_test.dart` against the local fake API (synthetic demo data only) and captures ten screens on each device:
- iOS: the iPhone 16 Pro Max and iPad Pro 13-inch (M4) simulators;
- Android: the first running emulator, resized to a phone, then a tablet, and always reset afterwards.

`tool/store_screenshots.py` then composes the publishing sets into `publish/screenshots/` (git-ignored) and checks each against the store's rules:
- App Store: iPhone 6.3" (1206 × 2622, the required "Dynamic Island (medium display)" size), iPhone 6.9" and iPad 13", captioned;
- Google Play: phone (captioned) and tablet (plain), plus the feature graphic and the 512 px icon.

## Website

`docs/` is the website, published by GitHub Pages at <https://edgepost.dev/>. It holds the product page, the privacy policy the app and the stores link to, the legal notice and the accessibility statement. `python3 tool/website.py` regenerates its screens, icons and fonts from the repository; `--check` fails when they are out of date. See `docs/README.md`.

## License

Edgepost is open source under the [MIT License](LICENSE): the app, the mail Worker and the website. The Inter typeface is used under the SIL Open Font License 1.1 (`assets/fonts/Inter-OFL.txt`). Edgepost isn't made, endorsed, sponsored or supported by Cloudflare, Inc., and isn't affiliated with it. Cloudflare, Cloudflare Workers and Cloudflare Pages are trademarks and/or registered trademarks of Cloudflare, Inc. in the United States and other jurisdictions.
