import { rm } from "node:fs/promises";
import { resolve } from "node:path";
import { defineConfig, type Plugin } from "vite";
import { defineTheme, oxContent } from "@ox-content/vite-plugin";
import { codeTheme, fonts, headHtml, themeColors, themeCss } from "./docs/.vite/brand.ts";
import { tnixGrammar } from "./docs/.vite/tnix-grammar.ts";

// Canonical public origin. Override with TNIX_DOCS_SITE_URL for preview
// deployments that should advertise their own URL in OG tags.
const siteUrl = process.env.TNIX_DOCS_SITE_URL ?? "https://tnix.dev";
const outDir = "dist/docs";

const navigation = [
  {
    title: "Start",
    items: [
      { title: "Overview", path: "/" },
      { title: "Getting Started", path: "/getting-started" },
      { title: "Support Matrix", path: "/support-matrix" },
    ],
  },
  {
    title: "Tutorial",
    items: [
      { title: "Tutorial Overview", path: "/tutorial" },
      { title: "1. Install", path: "/tutorial/install" },
      { title: "2. Your First File", path: "/tutorial/first-file" },
      { title: "3. Annotations & Inference", path: "/tutorial/annotations" },
      { title: "4. Attrsets & Structure", path: "/tutorial/attrsets" },
      { title: "5. Gradual Typing", path: "/tutorial/gradual" },
      { title: "6. Typing Existing .nix", path: "/tutorial/declarations" },
      { title: "7. Generics & HKT", path: "/tutorial/generics" },
      { title: "8. Conditional Types", path: "/tutorial/conditional-types" },
      { title: "9. Flakes & Packages", path: "/tutorial/flakes-and-packages" },
      { title: "10. Editor Setup", path: "/tutorial/editor" },
      { title: "11. Projects", path: "/tutorial/projects" },
      { title: "12. CI", path: "/tutorial/ci" },
    ],
  },
  {
    title: "Guides",
    items: [
      { title: "Adopting tnix", path: "/migration" },
      { title: "Editors", path: "/editors" },
      { title: "Troubleshooting", path: "/troubleshooting" },
    ],
  },
  {
    title: "Reference",
    items: [
      { title: "Language Reference", path: "/language-reference" },
      { title: "Grammar", path: "/grammar" },
      { title: "Type System", path: "/type-system" },
      { title: "How Checking Works", path: "/reference/type-system-internals" },
      { title: "CLI", path: "/reference/cli" },
      { title: "Configuration", path: "/reference/config" },
      { title: "Builtins & Registry", path: "/reference/builtins" },
      { title: "Diagnostics", path: "/diagnostics" },
    ],
  },
  {
    title: "Project",
    items: [
      { title: "Language Design", path: "/language-design" },
      { title: "Architecture", path: "/architecture" },
      { title: "Roadmap", path: "/roadmap" },
      { title: "CI/CD", path: "/ci-cd" },
      { title: "Docs Site", path: "/docs-site" },
      { title: "Brand", path: "/brand" },
    ],
  },
];

const theme = defineTheme({
  colors: themeColors.light,
  darkColors: themeColors.dark,
  fonts,
  layout: {
    sidebarWidth: "272px",
    maxContentWidth: "880px",
  },
  header: {
    logo: "/brand/tnix-mark.svg",
    logoWidth: 28,
    logoHeight: 28,
    showSiteNameText: true,
  },
  footer: {
    message: "TypeScript-grade types for Nix. Zero runtime.",
    copyright: 'Released under the MIT license · <a href="https://github.com/ubugeeei-prod/tnix">GitHub</a>',
  },
  socialLinks: {
    github: "https://github.com/ubugeeei-prod/tnix",
  },
  embed: {
    head: headHtml,
  },
  css: themeCss,
});

// Vite copies `docs/public` into the output directory while bundling the
// placeholder entry; the SSG step then writes pages next to those files.
// The placeholder entry itself is not part of the site, so drop it.
function dropBuildEntry(): Plugin {
  return {
    name: "tnix-docs:drop-build-entry",
    apply: "build",
    closeBundle: {
      order: "post",
      sequential: true,
      async handler() {
        await rm(resolve(outDir, "docs"), { recursive: true, force: true });
      },
    },
  };
}

export default defineConfig({
  publicDir: "docs/public",
  build: {
    outDir,
    // Start from an empty directory so stale pages never ship, then let the
    // public assets (_headers, _redirects, install.sh, brand files) and the
    // SSG pages land side by side. Do not enable `ssg.clean`: it runs after
    // Vite has copied the public directory and would delete it again.
    emptyOutDir: true,
    rollupOptions: {
      input: "docs/.vite/entry.html",
    },
  },
  plugins: [
    oxContent({
      srcDir: "docs",
      outDir,
      base: "/",
      docs: false,
      embeds: false,
      highlight: true,
      highlightTheme: codeTheme as never,
      highlightLangs: ["nix", tnixGrammar] as never,
      codeAnnotations: { notation: "both" },
      search: true,
      ssg: {
        clean: false,
        siteName: "tnix",
        siteUrl,
        ogImage: `${siteUrl}/og-image.png`,
        theme,
        navigation,
      },
    }),
    dropBuildEntry(),
  ],
});
