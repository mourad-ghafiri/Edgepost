#!/usr/bin/env bash
# Builds the edgepost-mail Worker bundle that ships inside the app:
#   assets/worker/edgepost-mail.js  (one self-contained ES module, postal-mime inlined)
#   assets/worker/manifest.json       (version, compatibility date/flags)
#
# Local only. Nothing here logs in to Cloudflare or uploads anything: tests run in local
# Miniflare/workerd, and `wrangler deploy --dry-run` only bundles. Telemetry is disabled.
# Run from anywhere: bash tool/build_worker.sh
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

# No account credentials reach wrangler, and no usage metrics leave the machine.
unset CLOUDFLARE_API_TOKEN CLOUDFLARE_API_KEY CLOUDFLARE_EMAIL CLOUDFLARE_ACCOUNT_ID
export WRANGLER_SEND_METRICS=false
export DO_NOT_TRACK=1

echo "==> Installing mail_worker dependencies (if missing)"
if [ ! -d mail_worker/node_modules ]; then
  if [ -f mail_worker/package-lock.json ]; then
    (cd mail_worker && npm ci)
  else
    (cd mail_worker && npm install)
  fi
fi

echo "==> Typecheck"
(cd mail_worker && npm run --silent typecheck)

echo "==> Tests (local workerd)"
(cd mail_worker && npm test --silent)

echo "==> Bundling (wrangler deploy --dry-run, no upload)"
(cd mail_worker && npx wrangler deploy --dry-run --outdir dist)

if [ ! -f mail_worker/dist/index.js ]; then
  echo "error: mail_worker/dist/index.js was not produced" >&2
  exit 1
fi
if [ -n "$(find mail_worker/dist -name '*.js' ! -name 'index.js' -print -quit)" ]; then
  echo "error: the bundle is not a single module:" >&2
  find mail_worker/dist -name '*.js' >&2
  exit 1
fi
if grep -Eq '^[[:space:]]*import[[:space:]].*from[[:space:]]' mail_worker/dist/index.js; then
  echo "error: the bundle still imports other modules" >&2
  exit 1
fi

echo "==> Writing assets/worker/"
mkdir -p assets/worker
# Drop any source map comment: the map file is never uploaded.
grep -v '^//# sourceMappingURL=' mail_worker/dist/index.js > assets/worker/edgepost-mail.js

node --input-type=module - <<'NODE'
import { readFileSync, writeFileSync } from "node:fs";

const pick = (file, re, label) => {
  const m = readFileSync(file, "utf8").match(re);
  if (!m) throw new Error(`could not read ${label} from ${file}`);
  return m[1];
};
const version = pick("mail_worker/src/version.ts", /WORKER_VERSION\s*=\s*"([^"]+)"/, "WORKER_VERSION");
const compatibilityDate = pick("mail_worker/wrangler.jsonc", /"compatibility_date"\s*:\s*"(\d{4}-\d{2}-\d{2})"/, "compatibility_date");
const flagsMatch = readFileSync("mail_worker/wrangler.jsonc", "utf8").match(/"compatibility_flags"\s*:\s*(\[[^\]]*\])/);
const compatibilityFlags = flagsMatch ? JSON.parse(flagsMatch[1]) : [];

const manifest = { version, mainModule: "edgepost-mail.js", compatibilityDate, compatibilityFlags };
writeFileSync("assets/worker/manifest.json", JSON.stringify(manifest) + "\n");
console.log(JSON.stringify(manifest));
NODE

echo "==> Smoke test of the shipped bundle (local workerd)"
(cd mail_worker && npm run --silent test:bundle)

bytes=$(wc -c < assets/worker/edgepost-mail.js | tr -d ' ')
echo "==> Done: assets/worker/edgepost-mail.js (${bytes} bytes), assets/worker/manifest.json"
