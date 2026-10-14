import { cloudflareTest } from "@cloudflare/vitest-pool-workers";
import { defineConfig } from "vitest/config";

// Smoke test of the shipped artifact (assets/worker/edgepost-mail.js), run by
// tool/build_worker.sh after bundling. Local only, same bindings as vitest.config.ts.
export default defineConfig({
  plugins: [
    cloudflareTest({
      remoteBindings: false,
      wrangler: { configPath: "./wrangler.jsonc" },
      miniflare: {
        bindings: { MAIL_API_KEY: "test-key-7f3a9c1e5b2d8f4a6c0e9b7d" },
      },
    }),
  ],
  test: {
    include: ["test/bundle/**/*.smoke.ts"],
  },
});
