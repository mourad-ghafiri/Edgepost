import { cloudflareTest } from "@cloudflare/vitest-pool-workers";
import { defineConfig } from "vitest/config";

// Local only: Miniflare/workerd with local D1 + R2 simulators. No remote bindings.
// https://developers.cloudflare.com/workers/testing/vitest-integration/
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
    include: ["test/**/*.test.ts"],
  },
});
