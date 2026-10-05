// tynix brand tokens for the docs site.
//
// This file is the executable half of docs/brand.md: the palette, type
// stacks, code tokens, and the CSS layer on top of the Ox Content default
// theme. Keep the two in sync — if a value changes here, update the tables in
// brand.md in the same commit.

export const palette = {
  // From the mark: Nix blues and Haskell purples.
  nixBlue: "#5277C3",
  nixDeep: "#3F65B5",
  nixDeeper: "#2F4F96",
  snow: "#7EBAE4",
  haskellPurple: "#5E5086",
  haskellMagenta: "#8F4E8B",
  haskellInk: "#453A62",
  // Annotation Amber: everything that is erased at build time.
  amber: "#F2B441",
  amber700: "#8A5A00",
  // Neutrals. Ink 900 is the mark's tile and every code surface.
  ink950: "#0A0E1A",
  ink900: "#0E1424",
  ink850: "#131B2E",
  ink800: "#1A2338",
  ink700: "#27324B",
  slate400: "#7482A0",
  slate300: "#9AA6BF",
  slate600: "#505B74",
  paper: "#F7F8FB",
  mist: "#EDF0F6",
  line: "#DCE1EB",
  text: "#141A2B",
} as const;

export const fonts = {
  sans: '"IBM Plex Sans", ui-sans-serif, system-ui, -apple-system, "Segoe UI", sans-serif',
  mono: '"JetBrains Mono", ui-monospace, "SF Mono", Menlo, Consolas, monospace',
};
const displayFont = '"Bricolage Grotesque", "IBM Plex Sans", ui-sans-serif, system-ui, sans-serif';

export const googleFontsHref =
  "https://fonts.googleapis.com/css2?family=Bricolage+Grotesque:opsz,wght@12..96,600..800&family=IBM+Plex+Sans:ital,wght@0,400;0,500;0,600;1,400&family=JetBrains+Mono:wght@400;500;600&display=swap";

// Code tokens. Ox Content's native highlighter and the tynix pass in
// highlight.ts both paint with `var(--octc-syntax-*)`, so this one table is
// the whole code theme ("tynix ink"). Code surfaces stay ink in both colour
// schemes so the annotation amber always reads the same.
export const codeTokens = {
  "syntax-background": palette.ink900,
  "syntax-foreground": "#D6DDEC",
  "syntax-token-comment": palette.slate400,
  "syntax-token-keyword": "#C4ABF0",
  "syntax-token-string": "#93D6B5",
  "syntax-token-string-expression": "#A9D3F0",
  "syntax-token-constant": "#93B8F2",
  "syntax-token-function": "#A9D3F0",
  "syntax-token-parameter": "#E6B3DD",
  "syntax-token-punctuation": "#8C97B2",
  "syntax-token-annotation": palette.amber,
};

export const themeColors = {
  light: {
    primary: palette.nixDeep,
    primaryHover: palette.nixDeeper,
    background: palette.paper,
    backgroundAlt: palette.mist,
    text: palette.text,
    textMuted: palette.slate600,
    border: palette.line,
    codeBackground: palette.ink900,
    codeText: codeTokens["syntax-foreground"],
  },
  dark: {
    primary: "#93B4EE",
    primaryHover: "#B9CEF5",
    background: palette.ink950,
    backgroundAlt: palette.ink850,
    text: "#E4E9F4",
    textMuted: palette.slate300,
    border: palette.ink700,
    codeBackground: palette.ink900,
    codeText: codeTokens["syntax-foreground"],
  },
};

const tagline = "Gradual types for Nix";

export const headHtml = [
  '<link rel="icon" href="/favicon.svg" type="image/svg+xml">',
  '<link rel="apple-touch-icon" href="/apple-touch-icon.png">',
  `<meta name="theme-color" content="${palette.paper}" media="(prefers-color-scheme: light)">`,
  `<meta name="theme-color" content="${palette.ink950}" media="(prefers-color-scheme: dark)">`,
  '<meta property="og:site_name" content="tynix">',
  '<meta property="og:image:width" content="1200">',
  '<meta property="og:image:height" content="630">',
  `<meta property="og:image:alt" content="tynix: ${tagline}. Add types where they help and ship plain .nix with zero runtime.">`,
  '<link rel="preconnect" href="https://fonts.googleapis.com">',
  '<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>',
  `<link rel="stylesheet" href="${googleFontsHref}">`,
].join("\n");

// Copy buttons for code blocks (framed by highlight.ts) and the install box.
export const themeJs = String.raw`
document.addEventListener("click", async (event) => {
  const button = event.target instanceof Element ? event.target.closest(".tx-copy") : null;
  if (!button) return;
  const source = button.dataset.copy ?? button.closest(".tx-code")?.querySelector("pre code")?.textContent ?? "";
  try {
    await navigator.clipboard.writeText(source.replace(/\n$/, ""));
    button.classList.add("is-copied");
    const label = button.querySelector("span");
    if (label) label.textContent = "Copied";
    setTimeout(() => {
      button.classList.remove("is-copied");
      if (label) label.textContent = "Copy";
    }, 1600);
  } catch {
    // Clipboard access can be denied; the code stays selectable.
  }
});
`;

const darkVars = String.raw`
  --tx-card: ${palette.ink850};
  --tx-hairline: color-mix(in srgb, ${palette.ink700} 80%, transparent);
  --tx-amber-text: ${palette.amber};
  --tx-purple: #B3A2E6;
  --tx-tint: color-mix(in srgb, #93B4EE 12%, transparent);
  --octc-color-on-primary: ${palette.ink950};
  --tx-code-border: ${palette.ink700};
  --octc-color-tip: #7FD1B5;
  --octc-color-warning: ${palette.amber};
`;

// CSS layered on top of the Ox Content default theme.
export const themeCss = String.raw`
:root {
  --tx-display: ${displayFont};
  --tx-ink: ${palette.ink900};
  --tx-ink-deep: ${palette.ink950};
  --tx-amber: ${palette.amber};
  --tx-amber-text: ${palette.amber700};
  --tx-purple: ${palette.haskellPurple};
  --tx-card: #FFFFFF;
  --tx-hairline: ${palette.line};
  --tx-tint: color-mix(in srgb, ${palette.nixDeep} 8%, transparent);
  --tx-code-border: color-mix(in srgb, ${palette.ink900} 60%, ${palette.ink700});
  --tx-radius: 12px;
  --tx-measure: 46rem;
  --octc-color-on-primary: #FFFFFF;
  --octc-surface-noise-image: none;
  --octc-color-tip: #2E7D6B;
  --octc-color-warning: ${palette.amber700};
}
[data-theme="dark"] {${darkVars}}
@media (prefers-color-scheme: dark) {
  :root:not([data-theme="light"]) {${darkVars}}
}

html { scroll-padding-top: calc(var(--octc-header-height) + 1rem); }
body {
  font-size: 16px;
  line-height: 1.7;
  -webkit-font-smoothing: antialiased;
  text-rendering: optimizeLegibility;
}
::selection { background: color-mix(in srgb, ${palette.snow} 40%, transparent); }
:focus-visible { outline: 2px solid var(--octc-color-primary); outline-offset: 2px; }

/* ---------- Header ---------- */
.header {
  background: color-mix(in srgb, var(--octc-color-bg) 86%, transparent);
  -webkit-backdrop-filter: saturate(1.4) blur(12px);
  backdrop-filter: saturate(1.4) blur(12px);
  border-bottom: 1px solid var(--tx-hairline);
}
.header-title {
  font-family: var(--tx-display);
  font-size: 1.3rem;
  font-weight: 700;
  letter-spacing: -0.03em;
  gap: 0.15rem;
}
.header-logo { width: 30px; height: 30px; }
.search-button {
  border-radius: 999px !important;
  border: 1px solid var(--tx-hairline) !important;
  background: var(--tx-card) !important;
}

/* ---------- Sidebar ---------- */
.sidebar {
  background: var(--octc-color-bg);
  border-right: 1px solid var(--tx-hairline);
  padding: 1.5rem 1rem 2rem;
}
.sidebar nav { gap: 1.5rem; }
.nav-title {
  font-family: var(--tx-display);
  font-size: 0.82rem;
  font-weight: 700;
  letter-spacing: -0.005em;
  text-transform: none;
  color: var(--octc-color-text);
  margin-bottom: 0.35rem;
}
.nav-list { gap: 1px; }
.nav-link {
  padding: 0.3rem 0.625rem;
  border-radius: 6px;
  font-size: 0.875rem;
  line-height: 1.45;
  color: var(--octc-color-text-muted);
  position: relative;
}
.nav-link.active, .nav-link.active:hover {
  background: var(--tx-tint) !important;
  color: var(--octc-color-primary) !important;
  font-weight: 600;
}
@media (any-hover: hover) and (any-pointer: fine) {
  .nav-link:hover { background: color-mix(in srgb, var(--octc-color-bg-alt) 80%, transparent); color: var(--octc-color-text); }
}

/* ---------- Content typography ---------- */
.main { padding: 3rem 2.5rem 2rem; }
.content { max-width: var(--tx-measure); }
.content h1, .content h2, .content h3, .content h4 {
  font-family: var(--tx-display);
  font-weight: 700;
  color: var(--octc-color-text);
  text-wrap: balance;
}
.content h1 { font-size: clamp(2.1rem, 4.2vw, 2.85rem); line-height: 1.08; letter-spacing: -0.035em; margin-bottom: 1.25rem; font-weight: 800; }
.content h1 + p { font-size: 1.125rem; color: var(--octc-color-text-muted); line-height: 1.65; }
.content h2 { font-size: 1.6rem; line-height: 1.2; letter-spacing: -0.025em; margin-top: 3.25rem; padding-bottom: 0; border-bottom: 0; }
.content h3 { font-size: 1.2rem; letter-spacing: -0.015em; margin-top: 2.25rem; }
.content h4 { font-size: 1rem; }
.content p, .content li { text-wrap: pretty; }
.content a { color: var(--octc-color-primary); text-decoration: underline; text-decoration-thickness: 1px; text-underline-offset: 0.2em; text-decoration-color: color-mix(in srgb, var(--octc-color-primary) 35%, transparent); }
.content a:hover { text-decoration-color: currentColor; }
.content strong { font-weight: 600; color: var(--octc-color-text); }
.content hr { border: 0; border-top: 1px solid var(--tx-hairline); margin: 2.5rem 0; }

/* Inline code: quiet chip, no colour shift. */
.content :not(pre) > code {
  font-family: var(--octc-font-mono);
  font-size: 0.86em;
  padding: 0.12em 0.36em;
  border-radius: 5px;
  border: 1px solid var(--tx-hairline);
  background: var(--tx-card);
  color: var(--octc-color-text);
}
.content a > code { color: inherit; }

/* ---------- Code blocks (framed by highlight.ts) ---------- */
.content pre, .tx-code pre {
  background: var(--octc-syntax-background) !important;
  border: 0;
  border-radius: 0;
  margin: 0;
  font-family: var(--octc-font-mono);
  padding: 1rem 1.15rem;
  scrollbar-width: thin;
  scrollbar-color: ${palette.ink700} transparent;
}
.content pre code, .tx-code pre code {
  font-family: var(--octc-font-mono);
  font-size: 0.8125rem;
  line-height: 1.7;
  font-variant-ligatures: none;
}
.tx-code {
  position: relative;
  margin: 1.4rem 0;
  border-radius: var(--tx-radius);
  border: 1px solid var(--tx-code-border);
  background: var(--octc-syntax-background);
  overflow: hidden;
  box-shadow: 0 1px 0 color-mix(in srgb, #FFFFFF 4%, transparent) inset;
}
.tx-code__bar {
  display: flex;
  align-items: center;
  gap: 0.6rem;
  min-height: 2.5rem;
  padding: 0 0.5rem 0 1rem;
  border-bottom: 1px solid ${palette.ink700};
  background: ${palette.ink850};
  font-family: var(--octc-font-mono);
  font-size: 0.75rem;
}
.tx-code__title { color: #E4E9F4; font-weight: 500; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.tx-code__title::before {
  content: "";
  display: inline-block;
  width: 0.5rem; height: 0.5rem;
  margin-right: 0.55rem;
  border-radius: 2px;
  background: ${palette.nixBlue};
  transform: skewX(-18deg);
}
.tx-code[data-lang="tynix"] .tx-code__title::before, .tx-code[data-lang="d.tynix"] .tx-code__title::before { background: var(--tx-amber); }
.tx-code__lang { color: ${palette.slate400}; margin-left: auto; }
.tx-code__float {
  position: absolute;
  top: 0.45rem;
  right: 0.45rem;
  display: flex;
  align-items: center;
  gap: 0.5rem;
  font-family: var(--octc-font-mono);
  font-size: 0.72rem;
  z-index: 1;
}
.tx-code__float .tx-code__lang { opacity: 0; transition: opacity 120ms ease; }
.tx-code:hover .tx-code__float .tx-code__lang { opacity: 1; }
.tx-copy {
  display: inline-flex;
  align-items: center;
  gap: 0.35rem;
  height: 1.8rem;
  padding: 0 0.6rem;
  border-radius: 6px;
  border: 1px solid ${palette.ink700};
  background: ${palette.ink800};
  color: #C9D2E4;
  font: 500 0.72rem/1 var(--octc-font-mono);
  cursor: pointer;
  transition: border-color 120ms ease, color 120ms ease, opacity 120ms ease;
}
.tx-copy::before {
  content: "";
  width: 0.8rem; height: 0.8rem;
  background: currentColor;
  -webkit-mask: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='black' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'%3E%3Crect x='9' y='9' width='12' height='12' rx='2'/%3E%3Cpath d='M5 15V5a2 2 0 0 1 2-2h10'/%3E%3C/svg%3E") center / contain no-repeat;
  mask: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24' fill='none' stroke='black' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'%3E%3Crect x='9' y='9' width='12' height='12' rx='2'/%3E%3Cpath d='M5 15V5a2 2 0 0 1 2-2h10'/%3E%3C/svg%3E") center / contain no-repeat;
}
.tx-copy:hover { border-color: ${palette.slate400}; color: #FFFFFF; }
.tx-copy.is-copied { color: #93D6B5; border-color: #93D6B5; }
.tx-code__float .tx-copy { opacity: 0; }
.tx-code:hover .tx-code__float .tx-copy, .tx-code__float .tx-copy:focus-visible { opacity: 1; }
@media (hover: none) { .tx-code__float .tx-copy { opacity: 1; } }
/* Single-line blocks are short: keep the copy button from covering text. */
.tx-code:not(.tx-code--titled) pre { padding-right: 5.5rem; }
.content pre.ox-code-block .line { display: block; width: auto; }
/* Blank lines are empty block spans; give them a line box. */
.content pre.ox-code-block code:has(> .line) > .line:empty::before { content: "\200b"; }

/* ---------- Callouts ---------- */
.content blockquote {
  border: 1px solid var(--tx-hairline);
  border-left: 3px solid var(--octc-color-primary);
  border-radius: 10px;
  background: var(--tx-card);
  padding: 1rem 1.15rem;
}
.content blockquote.ox-callout {
  border: 1px solid color-mix(in srgb, var(--octc-callout-accent) 28%, var(--tx-hairline));
  border-left: 3px solid var(--octc-callout-accent);
  background: color-mix(in srgb, var(--octc-callout-accent) 6%, var(--tx-card));
  border-radius: 10px;
  padding: 1rem 1.15rem;
}
.content blockquote.ox-callout.ox-callout--important { --octc-callout-accent: var(--tx-purple); }
.content blockquote.ox-callout.ox-callout--warning { --octc-callout-accent: var(--tx-amber-text); }
.content .ox-callout-title {
  font-family: var(--tx-display);
  font-size: 0.9rem;
  letter-spacing: 0;
  text-transform: none;
  margin-bottom: 0.35rem;
}

/* ---------- Tables ---------- */
.content table {
  width: fit-content;
  border: 1px solid var(--tx-hairline);
  border-radius: 10px;
  background: var(--tx-card);
  font-size: 0.875rem;
  line-height: 1.55;
}
.content th, .content td { border-color: var(--tx-hairline); padding: 0.6rem 0.9rem; vertical-align: top; }
.content th {
  background: color-mix(in srgb, var(--octc-color-bg-alt) 70%, var(--tx-card));
  font-size: 0.8rem;
  font-weight: 600;
  color: var(--octc-color-text);
  white-space: nowrap;
}
.content td > code:first-child:last-child, .content td > a:first-child:last-child > code { white-space: nowrap; }

/* ---------- TOC and footer ---------- */
.toc { border-left: 1px solid var(--tx-hairline); }
.toc-title { font-family: var(--tx-display); text-transform: none; letter-spacing: 0; font-size: 0.82rem; color: var(--octc-color-text); }
.toc-link { border-left: 2px solid transparent; }
.toc-link:hover { color: var(--octc-color-primary); border-left-color: var(--octc-color-primary); }
.site-footer { border-top: 1px solid var(--tx-hairline); }
.footer-message { font-family: var(--tx-display); font-weight: 600; color: var(--octc-color-text); }

@media (max-width: 768px) {
  .main { padding: 1.75rem 1rem 2rem; }
  .content h1 { font-size: 2rem; }
  .content h2 { font-size: 1.4rem; margin-top: 2.5rem; }
  .tx-code { margin-left: 0; margin-right: 0; }
  .content td { white-space: normal; min-width: 7.5rem; }
  .content td:first-child { min-width: 0; }
}

/* ---------- Docs content helpers ---------- */
.tx-steps > ol { counter-reset: tx-step; list-style: none; padding-left: 0; }
.tx-steps > ol > li { counter-increment: tx-step; position: relative; padding-left: 2.6rem; margin: 0.75rem 0; }
.tx-steps > ol > li > p { margin: 0; }
.tx-steps > ol > li::before {
  content: counter(tx-step); position: absolute; left: 0; top: 0.1rem;
  width: 1.7rem; height: 1.7rem; border-radius: 6px;
  display: grid; place-items: center; font: 700 0.8rem/1 var(--tx-display);
  color: var(--octc-color-on-primary); background: var(--octc-color-primary);
}

.tx-pager { margin-top: 3.5rem; padding-top: 1.5rem; border-top: 1px solid var(--tx-hairline); }
.tx-pager > p { display: flex; justify-content: space-between; gap: 1rem; margin: 0; }
.tx-pager a {
  display: block; text-decoration: none !important; padding: 0.85rem 1.1rem;
  border: 1px solid var(--tx-hairline); border-radius: 10px; background: var(--tx-card);
  min-width: 0; max-width: 48%; font-family: var(--tx-display); font-weight: 700;
}
.tx-pager a:hover { border-color: var(--octc-color-primary); }
.tx-pager a:last-child { margin-left: auto; text-align: right; }

figure.tx-diagram { margin: 1.75rem 0; padding: 1.25rem; border: 1px solid var(--tx-hairline); border-radius: var(--tx-radius); background: var(--tx-card); overflow-x: auto; }
figure.tx-diagram svg { display: block; width: 100%; height: auto; min-width: 560px; color: var(--octc-color-text); font-family: var(--octc-font-sans); }
figure.tx-diagram figcaption { margin-top: 0.75rem; font-size: 0.88rem; color: var(--octc-color-text-muted); }
figure.tx-diagram .d-box { fill: var(--octc-color-bg-alt); stroke: var(--octc-color-border); }
figure.tx-diagram .d-accent { fill: color-mix(in srgb, var(--octc-color-primary) 14%, var(--tx-card)); stroke: var(--octc-color-primary); }
figure.tx-diagram .d-amber { fill: color-mix(in srgb, ${palette.amber} 16%, var(--tx-card)); stroke: ${palette.amber}; }
figure.tx-diagram .d-mint { fill: color-mix(in srgb, var(--tx-purple) 14%, var(--tx-card)); stroke: var(--tx-purple); }
figure.tx-diagram .d-line { stroke: var(--octc-color-text-muted); fill: none; }
figure.tx-diagram .d-arrowhead { fill: var(--octc-color-text-muted); }
figure.tx-diagram .d-text { fill: var(--octc-color-text); font-size: 13px; }
figure.tx-diagram .d-mono { fill: var(--octc-color-text); font-size: 12px; font-family: var(--octc-font-mono); }
figure.tx-diagram .d-muted { fill: var(--octc-color-text-muted); font-size: 11px; }
figure.tx-diagram .d-head { fill: var(--octc-color-text); font-size: 13px; font-weight: 700; }

.tx-swatches { display: grid; grid-template-columns: repeat(auto-fill, minmax(150px, 1fr)); gap: 0.75rem; margin: 1rem 0 1.5rem; }
.tx-swatch { border: 1px solid var(--tx-hairline); border-radius: 10px; overflow: hidden; font-size: 0.8rem; background: var(--tx-card); }
.tx-swatch i { display: block; height: 64px; }
.tx-swatch b, .tx-swatch code { display: block; padding: 0.15rem 0.7rem; }
.tx-swatch b { padding-top: 0.55rem; font-weight: 600; }
.tx-swatch code { border: 0 !important; background: none !important; padding-bottom: 0.6rem !important; color: var(--octc-color-text-muted) !important; }

.tx-logos { display: grid; grid-template-columns: repeat(auto-fill, minmax(200px, 1fr)); gap: 0.75rem; margin: 1rem 0 1.5rem; }
.tx-logos figure { margin: 0; border: 1px solid var(--tx-hairline); border-radius: 10px; padding: 1.25rem; display: grid; place-items: center; min-height: 120px; }
.tx-logos figure.on-dark { background: ${palette.ink900}; }
.tx-logos figure.on-light { background: #FFFFFF; }
.tx-logos img { max-height: 64px; max-width: 100%; border-radius: 0; }
.tx-logos figcaption { font-size: 0.78rem; font-family: var(--octc-font-mono); color: var(--octc-color-text-muted); margin-top: 0.6rem; }
.tx-logos figure.on-dark figcaption { color: ${palette.slate300}; }
.tx-logos figure.on-light figcaption { color: ${palette.slate600}; }

/* ---------- Landing page ---------- */
.entry-page .main { padding: 0; margin-left: 0; }
.entry-page .main.main--with-toc { padding-right: 0; }
.entry-page .toc { display: none !important; }
.entry-page .entry-content { max-width: none; width: 100%; padding: 0; margin: 0; }
.entry-page .entry-content .content { max-width: none; margin: 0; padding: 0; }
.entry-page .content > :first-child { margin-top: 0; }
.entry-page .site-footer { margin: 0; }

.tx-wrap { width: min(1180px, 100% - 3rem); margin-inline: auto; }

/* Hero: an ink band in both schemes, the mark's own tile colour. */
.tx-hero {
  position: relative;
  isolation: isolate;
  overflow: hidden;
  background: ${palette.ink900};
  color: #E4E9F4;
  padding: 5.5rem 0 4.5rem;
  border-bottom: 1px solid ${palette.ink700};
}
.tx-hero::before {
  /* hexagonal lattice, the mark's geometry as quiet structure */
  content: "";
  position: absolute; inset: 0; z-index: -1;
  background-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='56' height='97' viewBox='0 0 56 97'%3E%3Cpath d='M28 0l28 16.2v32.3L28 64.7 0 48.5V16.2zM28 64.7V97' fill='none' stroke='%237EBAE4' stroke-opacity='.07'/%3E%3C/svg%3E");
  -webkit-mask-image: radial-gradient(70% 90% at 80% 20%, #000 10%, transparent 75%);
  mask-image: radial-gradient(70% 90% at 80% 20%, #000 10%, transparent 75%);
}
.tx-hero::after {
  content: "";
  position: absolute; z-index: -1;
  width: 900px; height: 900px; right: -260px; top: -380px;
  background:
    radial-gradient(closest-side, color-mix(in srgb, ${palette.nixBlue} 30%, transparent), transparent 70%),
    radial-gradient(closest-side at 30% 70%, color-mix(in srgb, ${palette.haskellPurple} 35%, transparent), transparent 70%);
  filter: blur(10px);
}
.tx-hero__grid {
  display: grid;
  grid-template-columns: minmax(0, 1.25fr) minmax(0, 0.75fr);
  gap: 3rem;
  align-items: center;
}
.content .tx-hero__title {
  font-family: var(--tx-display);
  font-size: clamp(2.9rem, 7.4vw, 5.6rem);
  font-weight: 800;
  line-height: 0.95;
  letter-spacing: -0.05em;
  color: #FFFFFF;
  margin: 0 0 1.5rem;
  max-width: 11ch;
}
.content .tx-hero__lede {
  font-size: clamp(1.08rem, 1.6vw, 1.3rem);
  line-height: 1.55;
  color: #B9C3D9;
  max-width: 34rem;
  margin: 0 0 2.25rem !important;
}
.tx-hero__lede code { color: #E4E9F4 !important; background: ${palette.ink800} !important; border-color: ${palette.ink700} !important; }
.tx-hero__grid > div { min-width: 0; }
.tx-hero__mark { position: relative; display: grid; place-items: center; }
.tx-hero__mark img { width: min(100%, 360px); height: auto; border-radius: 0; filter: drop-shadow(0 30px 60px rgb(0 0 0 / 0.45)); }

.tx-install {
  max-width: 40rem;
  border: 1px solid ${palette.ink700};
  border-radius: var(--tx-radius);
  background: color-mix(in srgb, ${palette.ink950} 70%, transparent);
  overflow: hidden;
}
.tx-install__row { display: flex; align-items: center; gap: 0.75rem; padding: 0.55rem 0.55rem 0.55rem 1rem; min-width: 0; }
.tx-install__row + .tx-install__row { border-top: 1px solid ${palette.ink700}; }
.tx-install__label { flex: none; width: 4.6rem; font-size: 0.75rem; font-weight: 500; color: ${palette.slate400}; }
.content .tx-install__row code {
  flex: 1; min-width: 0;
  overflow-x: auto; white-space: nowrap; scrollbar-width: none;
  font-size: 0.85rem; color: #E4E9F4; background: none; border: 0; padding: 0;
}
.tx-install__row code::before { content: "$ "; color: ${palette.slate400}; }
.tx-actions { display: flex; flex-wrap: wrap; gap: 0.75rem; margin-top: 1.75rem; }
.content a.tx-btn {
  display: inline-flex; align-items: center; justify-content: center;
  height: 2.9rem; padding: 0 1.35rem; border-radius: 10px;
  font-weight: 600; font-size: 0.95rem; text-decoration: none;
  border: 1px solid ${palette.ink700}; color: #E4E9F4; background: ${palette.ink850};
  transition: background 120ms ease, border-color 120ms ease;
}
.content a.tx-btn:hover { border-color: ${palette.slate400}; }
.content a.tx-btn--primary { background: ${palette.amber}; border-color: ${palette.amber}; color: ${palette.ink950}; }
.content a.tx-btn--primary:hover { background: #F6C566; border-color: #F6C566; }

/* The erasure demo: what you write and what Nix evaluates. */
.tx-demo { margin-top: 4.5rem; }
.tx-demo__panes { display: grid; grid-template-columns: minmax(0, 1fr) 3.5rem minmax(0, 1fr); align-items: stretch; }
.tx-demo__panes > div { min-width: 0; display: flex; }
.tx-demo .tx-code { flex: 1; margin: 0; display: flex; flex-direction: column; border-color: ${palette.ink700}; background: ${palette.ink950}; box-shadow: 0 30px 80px -30px rgb(0 0 0 / 0.6); }
.tx-demo .tx-code pre { flex: 1; background: ${palette.ink950} !important; }
.tx-demo .tx-code__bar { background: ${palette.ink850}; }
.tx-demo__panes > .tx-demo__arrow { display: grid; place-items: center; color: ${palette.slate400}; }
.tx-demo__arrow svg { width: 28px; height: 28px; }
.tx-demo__caption { margin: 1.25rem 0 0 !important; color: #9AA6BF; font-size: 0.95rem; max-width: 60rem; }
.tx-demo__caption b { color: ${palette.amber}; font-weight: 600; }
.tx-demo__caption code { color: #E4E9F4 !important; background: ${palette.ink850} !important; border-color: ${palette.ink700} !important; }

/* Paper sections */
.tx-section { padding: 5.5rem 0; }
.tx-section + .tx-section { border-top: 1px solid var(--tx-hairline); }
.content .tx-section__title {
  font-family: var(--tx-display);
  font-size: clamp(1.9rem, 3.4vw, 2.6rem);
  font-weight: 800;
  line-height: 1.05;
  letter-spacing: -0.035em;
  margin: 0 0 0.75rem;
  max-width: 20ch;
}
.tx-section__lede { color: var(--octc-color-text-muted); font-size: 1.08rem; max-width: 38rem; margin: 0 0 3rem !important; }

.tx-features {
  display: grid;
  grid-template-columns: repeat(3, minmax(0, 1fr));
  border-top: 1px solid var(--tx-hairline);
  border-left: 1px solid var(--tx-hairline);
}
.content a.tx-feature {
  display: block;
  padding: 1.75rem 1.75rem 2rem;
  border-right: 1px solid var(--tx-hairline);
  border-bottom: 1px solid var(--tx-hairline);
  color: inherit;
  text-decoration: none;
  transition: background 150ms ease;
}
.content a.tx-feature:hover { background: var(--tx-card); }
.tx-feature svg { width: 30px; height: 30px; color: var(--octc-color-primary); margin-bottom: 1.1rem; }
.tx-feature svg .a { stroke: ${palette.amber}; }
.tx-feature h3 { font-family: var(--tx-display); font-size: 1.12rem !important; margin: 0 0 0.45rem !important; letter-spacing: -0.015em; }
.tx-feature p { margin: 0 !important; color: var(--octc-color-text-muted); font-size: 0.94rem; line-height: 1.6; }

.tx-flow { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 1.25rem; counter-reset: tx-flow; }
.tx-flow__step { counter-increment: tx-flow; display: flex; flex-direction: column; min-width: 0; }
.tx-flow__step h3 { font-family: var(--tx-display); font-size: 1.12rem !important; margin: 0 0 0.4rem !important; display: flex; align-items: baseline; gap: 0.6rem; }
.tx-flow__step h3::before {
  content: counter(tx-flow);
  display: inline-grid; place-items: center; flex: none;
  width: 1.6rem; height: 1.6rem; border-radius: 6px;
  font-size: 0.8rem; color: var(--octc-color-on-primary); background: var(--octc-color-primary);
  transform: translateY(-0.12rem);
}
.tx-flow__step p { margin: 0 0 1rem !important; color: var(--octc-color-text-muted); font-size: 0.94rem; }
.tx-flow__step .tx-code { margin: auto 0 0; }

.content .tx-editors { display: flex; flex-wrap: wrap; gap: 0.5rem; margin: 2rem 0 0; padding: 0; list-style: none; }
.tx-editors li {
  margin: 0; padding: 0.45rem 0.9rem; border-radius: 999px;
  border: 1px solid var(--tx-hairline); background: var(--tx-card);
  font-size: 0.9rem; font-weight: 500;
}

.tx-cta {
  display: grid; grid-template-columns: minmax(0, 1fr) auto; align-items: center; gap: 2rem;
  padding: 2.5rem 2.75rem; border-radius: 18px;
  background: ${palette.ink900}; color: #E4E9F4;
  position: relative; overflow: hidden; isolation: isolate;
}
.tx-cta::after {
  content: ""; position: absolute; z-index: -1; right: -120px; top: -160px; width: 460px; height: 460px;
  background: radial-gradient(closest-side, color-mix(in srgb, ${palette.haskellPurple} 45%, transparent), transparent);
}
.content .tx-cta h2 { color: #FFFFFF; margin: 0 0 0.4rem; font-size: clamp(1.5rem, 2.6vw, 2rem); font-weight: 800; letter-spacing: -0.03em; }
.tx-cta p { margin: 0 !important; color: #B9C3D9; }

@media (max-width: 960px) {
  .tx-hero { padding: 3.5rem 0 3rem; }
  .tx-hero__grid { grid-template-columns: 1fr; gap: 0; }
  .tx-hero__mark { order: -1; justify-items: start; margin-bottom: 1.75rem; }
  .tx-hero__mark img { width: 112px; }
  .tx-demo { margin-top: 3rem; }
  .tx-demo__panes { grid-template-columns: minmax(0, 1fr); }
  .tx-demo__arrow { height: 3rem; }
  .tx-demo__arrow svg { transform: rotate(90deg); }
  .tx-features { grid-template-columns: repeat(2, minmax(0, 1fr)); }
  .tx-flow { grid-template-columns: 1fr; }
  .tx-section { padding: 4rem 0; }
}
@media (max-width: 640px) {
  .tx-wrap { width: calc(100% - 2rem); }
  .tx-features { grid-template-columns: 1fr; }
  .content a.tx-feature { padding: 1.4rem 1.25rem 1.5rem; }
  .tx-install__label { display: none; }
  .content .tx-install__row code { font-size: 0.78rem; }
  .tx-cta { grid-template-columns: 1fr; padding: 2rem 1.5rem; }
  .content .tx-hero__title { font-size: 3rem; }
}
@media (prefers-reduced-motion: reduce) {
  * { transition: none !important; }
}
`;
