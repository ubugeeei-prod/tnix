// The tnix.dev documentation site, deployed with the Cloudflare CLI (`cf`):
// a Worker serving the Ox Content build (the repository's dist/docs, see
// wrangler.config.ts) as static assets. `_headers` and `_redirects` there
// apply as-is. From the repository root:
//
//   pnpm run docs:build    # build dist/docs
//   pnpm run docs:deploy   # cf deploy (needs `cf auth login` locally)
//
// CI holds no Cloudflare token: Workers Builds (Cloudflare's Git integration)
// builds and deploys on every push to main. See docs/docs-site.md.
import { defineConfig } from "cf/config";

export default defineConfig({
  worker: {
    name: "tnix",
    compatibilityDate: "2026-10-01",
    observability: {
      enabled: true,
    },
    assets: {
      htmlHandling: "auto-trailing-slash",
    },
    // `cf deploy` creates the DNS record and certificate for the custom
    // domain when the tnix.dev zone is in the same Cloudflare account.
    domains: ["tnix.dev"],
  },
});
