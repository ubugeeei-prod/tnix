import { defineConfig } from "vite";
import { defineTheme, oxContent } from "@ox-content/vite-plugin";

const navigation = [
  {
    title: "Start",
    items: [
      { title: "Overview", path: "/" },
      { title: "Getting Started", path: "/getting-started" },
      { title: "Migration", path: "/migration" },
      { title: "Troubleshooting", path: "/troubleshooting" },
    ],
  },
  {
    title: "Language",
    items: [
      { title: "Language Reference", path: "/language-reference" },
      { title: "Grammar", path: "/grammar" },
      { title: "Type System", path: "/type-system" },
      { title: "Language Design", path: "/language-design" },
    ],
  },
  {
    title: "Project",
    items: [
      { title: "Architecture", path: "/architecture" },
      { title: "Diagnostics", path: "/diagnostics" },
      { title: "Support Matrix", path: "/support-matrix" },
      { title: "CI/CD", path: "/ci-cd" },
      { title: "Docs Site", path: "/docs-site" },
      { title: "Roadmap", path: "/roadmap" },
    ],
  },
];

const theme = defineTheme({
  colors: {
    primary: "#0f766e",
    primaryHover: "#0e7490",
    background: "#fbfcfd",
    backgroundAlt: "#eef6f7",
    text: "#111827",
    textMuted: "#52616b",
    border: "#d7e1e7",
    codeBackground: "#102033",
    codeText: "#e5eef7",
  },
  darkColors: {
    primary: "#5eead4",
    primaryHover: "#7dd3fc",
    background: "#0c1118",
    backgroundAlt: "#131c27",
    text: "#ecf4f7",
    textMuted: "#a8b5bd",
    border: "#293747",
    codeBackground: "#0a0f16",
    codeText: "#dbeafe",
  },
  header: {
    logo: "/tnix-logo.svg",
    logoWidth: 28,
    logoHeight: 28,
    showSiteNameText: true,
  },
  footer: {
    message: "Typed tooling for Nix.",
    copyright: "Released under the MIT license.",
  },
  socialLinks: {
    github: "https://github.com/ubugeeei-prod/tnix",
  },
});

export default defineConfig({
  publicDir: "docs/public",
  build: {
    outDir: "dist/docs",
    emptyOutDir: false,
    rollupOptions: {
      input: "docs/.vite/entry.html",
    },
  },
  plugins: [
    oxContent({
      srcDir: "docs",
      outDir: "dist/docs",
      base: "/",
      docs: false,
      embeds: false,
      highlight: true,
      search: true,
      ssg: {
        clean: true,
        siteName: "tnix",
        siteUrl: process.env.TNIX_DOCS_SITE_URL,
        theme,
        navigation,
      },
    }),
  ],
});
