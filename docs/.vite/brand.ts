// tnix brand tokens for the docs site.
//
// This file is the executable half of docs/brand.md: the palette, type
// stacks, code theme, and the CSS layer on top of the Ox Content default
// theme. Keep the two in sync — if a value changes here, update the tables in
// brand.md in the same commit.

export const palette = {
  // Lambda Blue: the primary accent. A deeper, more saturated descendant of
  // the Nix snowflake blues (#5277C3 / #7EBAE4).
  lambda700: "#2449B8",
  lambda600: "#2F5BD8",
  lambda500: "#3B63E0",
  lambda300: "#8DB4FF",
  lambda200: "#B8D0FF",
  // Snow Blue: heritage tint borrowed from the Nix logo, used in gradients.
  snow: "#7EBAE4",
  // Check Mint: "the checker is happy". Used for the colon in the mark,
  // success states, and string literals in code.
  mint400: "#5FE0BC",
  mint700: "#087A5F",
  // Annotation Amber: everything that is erased at build time.
  amber: "#F2B441",
  amber700: "#8A5A00",
  coral: "#FF8A7A",
  // Neutrals.
  ink950: "#0A0F1C",
  ink900: "#0B1220",
  ink850: "#111A2E",
  ink700: "#22304D",
  slate400: "#7F8DAA",
  slate300: "#A3B0C7",
  slate100: "#DCE6F8",
  paper: "#FBFCFE",
  mist: "#F1F5FB",
  line: "#DCE3EE",
  text: "#0E1525",
  muted: "#4A5871",
} as const;

export const fonts = {
  sans: '"Geist", "Inter", ui-sans-serif, system-ui, -apple-system, "Segoe UI", sans-serif',
  mono: '"Geist Mono", "JetBrains Mono", ui-monospace, "SF Mono", Menlo, Consolas, monospace',
};

export const googleFontsHref =
  "https://fonts.googleapis.com/css2?family=Geist:wght@400;500;600;700;800&family=Geist+Mono:wght@400;500;600&display=swap";

// Shiki theme used for every code block. Code blocks stay dark in both colour
// schemes so the "annotation amber" for type-only syntax always reads clearly.
export const codeTheme = {
  name: "tnix-ink",
  type: "dark",
  colors: {
    "editor.background": palette.ink900,
    "editor.foreground": palette.slate100,
  },
  settings: [
    { settings: { background: palette.ink900, foreground: palette.slate100 } },
    { scope: ["comment", "punctuation.definition.comment"], settings: { foreground: palette.slate400, fontStyle: "italic" } },
    { scope: ["keyword.control.directive.tnix"], settings: { foreground: palette.mint400, fontStyle: "bold" } },
    {
      scope: ["keyword", "storage", "keyword.control", "support.function.import", "keyword.control.flow"],
      settings: { foreground: palette.lambda300 },
    },
    {
      scope: [
        "keyword.other.type.tnix",
        "keyword.operator.annotation.tnix",
        "keyword.operator.type.tnix",
        "entity.name.type",
        "entity.name.type.alias.tnix",
        "support.type",
        "variable.parameter.type.tnix",
        "punctuation.definition.type.record.tnix",
        "punctuation.terminator.type.tnix",
        "storage.type",
      ],
      settings: { foreground: palette.amber },
    },
    { scope: ["support.type.gradual.tnix"], settings: { foreground: palette.amber, fontStyle: "italic" } },
    { scope: ["string", "string.quoted", "string.unquoted.path"], settings: { foreground: palette.mint400 } },
    { scope: ["constant.character.escape", "punctuation.section.embedded"], settings: { foreground: palette.lambda200 } },
    { scope: ["constant.numeric", "constant.language"], settings: { foreground: palette.coral } },
    { scope: ["variable.other.property", "meta.attribute", "entity.other.attribute-name"], settings: { foreground: "#C9D7F2" } },
    { scope: ["variable.parameter"], settings: { foreground: "#E8EEFA", fontStyle: "italic" } },
    { scope: ["support.variable", "support.function", "entity.name.function"], settings: { foreground: palette.lambda200 } },
    { scope: ["keyword.operator", "punctuation"], settings: { foreground: "#8FA0BF" } },
    { scope: ["markup.inserted"], settings: { foreground: palette.mint400 } },
    { scope: ["markup.deleted"], settings: { foreground: palette.coral } },
    { scope: ["variable.other.env", "variable.other.normal.shell"], settings: { foreground: palette.lambda200 } },
    { scope: ["entity.name.command", "support.function.builtin.shell"], settings: { foreground: palette.lambda300 } },
  ],
};

export const themeColors = {
  light: {
    primary: palette.lambda600,
    primaryHover: palette.lambda700,
    background: palette.paper,
    backgroundAlt: palette.mist,
    text: palette.text,
    textMuted: palette.muted,
    border: palette.line,
    codeBackground: palette.ink900,
    codeText: palette.slate100,
  },
  dark: {
    primary: palette.lambda300,
    primaryHover: palette.lambda200,
    background: palette.ink950,
    backgroundAlt: palette.ink850,
    text: "#E6ECF7",
    textMuted: palette.slate300,
    border: palette.ink700,
    codeBackground: palette.ink900,
    codeText: palette.slate100,
  },
};

export const headHtml = [
  '<link rel="icon" href="/favicon.svg" type="image/svg+xml">',
  '<link rel="apple-touch-icon" href="/apple-touch-icon.png">',
  '<meta name="theme-color" content="#FBFCFE" media="(prefers-color-scheme: light)">',
  '<meta name="theme-color" content="#0A0F1C" media="(prefers-color-scheme: dark)">',
  '<meta property="og:site_name" content="tnix">',
  '<meta property="og:image:width" content="1200">',
  '<meta property="og:image:height" content="630">',
  '<meta property="og:image:alt" content="tnix: TypeScript-grade types for Nix, zero runtime">',
  '<link rel="preconnect" href="https://fonts.googleapis.com">',
  '<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>',
  `<link rel="stylesheet" href="${googleFontsHref}">`,
].join("\n");

// CSS layered on top of the Ox Content default theme.
export const themeCss = String.raw`
:root {
  --tx-amber: ${palette.amber};
  --tx-mint: ${palette.mint700};
  --tx-hero-glow: color-mix(in srgb, ${palette.lambda500} 14%, transparent);
  --tx-card: #ffffff;
  --tx-on-primary: #ffffff;
  --octc-color-code-bg-top: ${palette.ink900};
}
[data-theme="dark"] {
  --tx-mint: ${palette.mint400};
  --tx-hero-glow: color-mix(in srgb, ${palette.lambda500} 30%, transparent);
  --tx-card: ${palette.ink850};
  --tx-on-primary: ${palette.ink950};
}
@media (prefers-color-scheme: dark) {
  :root:not([data-theme="light"]) {
    --tx-mint: ${palette.mint400};
    --tx-hero-glow: color-mix(in srgb, ${palette.lambda500} 30%, transparent);
    --tx-card: ${palette.ink850};
    --tx-on-primary: ${palette.ink950};
  }
}

body { font-feature-settings: "ss01", "cv11"; -webkit-font-smoothing: antialiased; }
.header-title { font-weight: 700; letter-spacing: -0.02em; }

/* Headings: tighter, more confident. */
.content h1, .content h2, .content h3 { letter-spacing: -0.025em; }
.content h1 { font-weight: 750; }
.content a { text-underline-offset: 0.18em; }

/* Inline code keeps a hint of the annotation colour family. */
.content :not(pre) > code { color: color-mix(in srgb, var(--octc-color-text) 88%, var(--octc-color-primary)); }

/* Code blocks: ink surface, generous radius, mono stack. */
.content pre, .content pre.shiki {
  border-radius: 10px;
  border: 1px solid ${palette.ink700};
  font-family: var(--octc-font-mono);
}
.content pre code { font-size: 0.84rem; line-height: 1.65; }
/* Titled / annotated blocks render each line as a block *and* keep the
   newline characters, which doubles the spacing. Inline-block lines that span
   the full row keep highlight backgrounds without the extra blank line. */
.content pre.ox-code-block .line {
  display: inline-block;
  width: calc(100% + 2.5rem);
  box-sizing: border-box;
  vertical-align: top;
}

/* ---------- Landing page ---------- */
.entry-page .main { display: flex; flex-direction: column; }
.entry-page .main.main--with-toc { padding-right: 0; }
.entry-page .toc { display: none !important; }
.entry-page .hero { order: 0; }
.entry-page .entry-content { order: 1; }
.entry-page .features { order: 2; }
.entry-page .site-footer { order: 3; }

.entry-page .hero {
  min-height: auto;
  padding: 5.5rem max(2rem, calc((100% - 1160px) / 2)) 4rem;
  display: grid;
  grid-template-columns: minmax(0, 1.25fr) minmax(0, 0.75fr);
  align-items: center;
  gap: 3rem;
  width: 100%;
  text-align: left;
  border-bottom: 0;
  background: radial-gradient(60% 70% at 85% 30%, var(--tx-hero-glow), transparent 70%);
}
.entry-page .hero-content { order: 1; padding-bottom: 0; margin: 0; max-width: 680px; }
.entry-page .hero-image { order: 2; margin: 0 auto; width: 100%; max-width: 280px; }
.entry-page .hero-image img { width: 100%; height: auto; }
.entry-page .hero-image img { filter: drop-shadow(0 24px 48px color-mix(in srgb, ${palette.lambda600} 35%, transparent)); }
.entry-page .hero-name {
  font-size: clamp(1rem, 1.6vw, 1.1rem);
  font-family: var(--octc-font-mono);
  font-weight: 600;
  letter-spacing: 0;
  color: var(--octc-color-primary);
  margin-bottom: 1.25rem;
}
.entry-page .hero-name::before { content: "$ "; color: var(--octc-color-text-muted); }
.entry-page .hero-text {
  font-size: clamp(2.4rem, 5.4vw, 4rem);
  font-weight: 800;
  line-height: 1.04;
  letter-spacing: -0.045em;
  color: var(--octc-color-text);
  margin-bottom: 1.25rem;
}
.entry-page .hero-tagline { margin: 0; max-width: 600px; font-size: 1.125rem; }
.entry-page .hero-actions { justify-content: flex-start; margin-top: 2rem; }
.hero-action { border-radius: 8px; }
.hero-action-brand, .hero-action-brand:hover { color: var(--tx-on-primary); }

@media (max-width: 860px) {
  .entry-page .hero { grid-template-columns: 1fr; padding: 3rem 1rem 2rem; gap: 1.5rem; }
  .entry-page .hero-image { order: 0; max-width: 132px; margin: 0; }
}

.entry-page .entry-content { max-width: none; width: 100%; padding: 0 max(2rem, calc((100% - 1160px) / 2)) 1rem; }
.entry-page .entry-content .content { max-width: none; }
@media (max-width: 860px) { .entry-page .entry-content { padding: 0 1rem 1rem; } }

.tx-section-label {
  font-family: var(--octc-font-mono);
  font-size: 0.78rem;
  font-weight: 600;
  letter-spacing: 0.08em;
  text-transform: uppercase;
  color: var(--octc-color-primary);
  margin: 0 0 0.5rem;
}

.tx-install { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 1rem; margin: 0 0 3.5rem; }
.tx-install > div { min-width: 0; }
.tx-install p { margin: 0 0 0.4rem; font-size: 0.85rem; color: var(--octc-color-text-muted); }
.tx-install pre { margin: 0; }

.tx-compare {
  display: grid;
  grid-template-columns: minmax(0, 1fr) auto minmax(0, 1fr);
  gap: 1rem;
  align-items: stretch;
  margin: 0.75rem 0 1rem;
}
.tx-compare > div { min-width: 0; display: flex; flex-direction: column; }
.tx-compare pre { flex: 1; margin: 0; }
.tx-compare .tx-file {
  font-family: var(--octc-font-mono);
  font-size: 0.8rem;
  color: var(--octc-color-text-muted);
  margin: 0 0 0.4rem;
}
.tx-compare .tx-arrow {
  align-self: center;
  font-family: var(--octc-font-mono);
  font-size: 0.8rem;
  color: var(--octc-color-text-muted);
  text-align: center;
  line-height: 1.4;
}
.tx-compare .tx-arrow strong { display: block; font-size: 1.6rem; color: var(--octc-color-primary); }
.tx-caption { font-size: 0.92rem; color: var(--octc-color-text-muted); margin: 0 0 3.5rem; }
.tx-amber { color: ${palette.amber700}; font-weight: 600; }
[data-theme="dark"] .tx-amber { color: var(--tx-amber); }

@media (max-width: 860px) {
  .tx-install, .tx-compare { grid-template-columns: 1fr; }
  .tx-compare .tx-arrow strong { transform: rotate(90deg); }
}

.tx-cta {
  display: flex; flex-wrap: wrap; align-items: center; justify-content: space-between; gap: 1.25rem;
  margin: 3.5rem 0 0; padding: 1.75rem 2rem;
  border-radius: 14px;
  border: 1px solid color-mix(in srgb, var(--octc-color-primary) 30%, var(--octc-color-border));
  background: linear-gradient(120deg, color-mix(in srgb, var(--octc-color-primary) 10%, var(--tx-card)), var(--tx-card));
}
.tx-cta h2 { margin: 0 0 0.35rem !important; border: 0 !important; padding: 0 !important; font-size: 1.4rem; }
.tx-cta p { margin: 0; color: var(--octc-color-text-muted); }
.tx-cta > p { flex: none; }
.tx-cta a.tx-button, .tx-cta > p > a {
  display: inline-flex; padding: 0.85rem 1.4rem; border-radius: 8px; font-weight: 700; text-decoration: none;
  background: var(--octc-color-primary); color: var(--tx-on-primary);
}
.tx-cta a.tx-button:hover, .tx-cta > p > a:hover { background: var(--octc-color-primary-hover); text-decoration: none; }

/* Feature grid: 3 columns of cards instead of a stacked list. */
.entry-page .features { max-width: none; width: 100%; padding: 1rem max(2rem, calc((100% - 1160px) / 2)) 6rem; }
.entry-page .features-grid { grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 1rem; border-top: 0; }
.entry-page .feature-card {
  grid-template-columns: 1fr; align-items: start; gap: 0.85rem;
  padding: 1.4rem; border: 1px solid var(--octc-color-border); border-radius: 12px;
  background: var(--tx-card);
  transition: border-color 0.15s ease, transform 0.15s ease;
}
.entry-page .feature-card:hover { border-color: var(--octc-color-primary); transform: translateY(-2px); }
.entry-page .feature-icon {
  width: 2.5rem; height: 2.5rem; border-radius: 8px;
  background: color-mix(in srgb, var(--octc-color-primary) 14%, transparent);
}
.entry-page .feature-icon img { width: 1.4rem; height: 1.4rem; }
@media (max-width: 960px) { .entry-page .features-grid { grid-template-columns: repeat(2, minmax(0, 1fr)); } }
@media (max-width: 640px) { .entry-page .features-grid { grid-template-columns: 1fr; } .entry-page .features { padding: 1rem 1rem 4rem; } }

/* ---------- Docs content helpers ---------- */
.tx-steps > ol { counter-reset: tx-step; list-style: none; padding-left: 0; }
.tx-steps > ol > li { counter-increment: tx-step; position: relative; padding-left: 2.6rem; margin: 0.6rem 0; }
.tx-steps > ol > li > p { margin: 0; }
.tx-steps > ol > li::before {
  content: counter(tx-step); position: absolute; left: 0; top: 0.05rem;
  width: 1.75rem; height: 1.75rem; border-radius: 50%;
  display: grid; place-items: center; font-size: 0.8rem; font-weight: 700;
  color: var(--tx-on-primary); background: var(--octc-color-primary);
}

.tx-pager { margin-top: 3rem; padding-top: 1.25rem; border-top: 1px solid var(--octc-color-border); }
.tx-pager > p { display: flex; justify-content: space-between; gap: 1rem; margin: 0; }
.tx-pager a { display: block; text-decoration: none; padding: 0.75rem 1rem; border: 1px solid var(--octc-color-border); border-radius: 10px; min-width: 0; max-width: 48%; font-weight: 600; }
.tx-pager a:hover { border-color: var(--octc-color-primary); text-decoration: none; }
.tx-pager a:last-child { margin-left: auto; text-align: right; }

figure.tx-diagram { margin: 1.75rem 0; padding: 1.25rem; border: 1px solid var(--octc-color-border); border-radius: 12px; background: var(--tx-card); overflow-x: auto; }
figure.tx-diagram svg { display: block; width: 100%; height: auto; min-width: 560px; color: var(--octc-color-text); font-family: var(--octc-font-sans); }
figure.tx-diagram figcaption { margin-top: 0.75rem; font-size: 0.88rem; color: var(--octc-color-text-muted); }
figure.tx-diagram .d-box { fill: var(--octc-color-bg-alt); stroke: var(--octc-color-border); }
figure.tx-diagram .d-accent { fill: color-mix(in srgb, var(--octc-color-primary) 14%, var(--tx-card)); stroke: var(--octc-color-primary); }
figure.tx-diagram .d-amber { fill: color-mix(in srgb, ${palette.amber} 16%, var(--tx-card)); stroke: ${palette.amber}; }
figure.tx-diagram .d-mint { fill: color-mix(in srgb, ${palette.mint400} 16%, var(--tx-card)); stroke: ${palette.mint700}; }
figure.tx-diagram .d-line { stroke: var(--octc-color-text-muted); fill: none; }
figure.tx-diagram .d-arrowhead { fill: var(--octc-color-text-muted); }
figure.tx-diagram .d-text { fill: var(--octc-color-text); font-size: 13px; }
figure.tx-diagram .d-mono { fill: var(--octc-color-text); font-size: 12px; font-family: var(--octc-font-mono); }
figure.tx-diagram .d-muted { fill: var(--octc-color-text-muted); font-size: 11px; }
figure.tx-diagram .d-head { fill: var(--octc-color-text); font-size: 13px; font-weight: 700; }

.tx-swatches { display: grid; grid-template-columns: repeat(auto-fill, minmax(150px, 1fr)); gap: 0.75rem; margin: 1rem 0 1.5rem; }
.tx-swatch { border: 1px solid var(--octc-color-border); border-radius: 10px; overflow: hidden; font-size: 0.8rem; background: var(--tx-card); }
.tx-swatch i { display: block; height: 64px; }
.tx-swatch b, .tx-swatch code { display: block; padding: 0.15rem 0.7rem; }
.tx-swatch b { padding-top: 0.55rem; }
.tx-swatch code { border: 0 !important; background: none !important; padding-bottom: 0.6rem; color: var(--octc-color-text-muted) !important; }

.tx-logos { display: grid; grid-template-columns: repeat(auto-fill, minmax(220px, 1fr)); gap: 0.75rem; margin: 1rem 0 1.5rem; }
.tx-logos figure { margin: 0; border: 1px solid var(--octc-color-border); border-radius: 10px; padding: 1.25rem; display: grid; place-items: center; min-height: 120px; }
.tx-logos figure.on-dark { background: ${palette.ink950}; }
.tx-logos figure.on-light { background: ${palette.paper}; }
.tx-logos img { max-height: 64px; max-width: 100%; }
.tx-logos figcaption { font-size: 0.78rem; color: var(--octc-color-text-muted); margin-top: 0.6rem; }
.tx-logos figure.on-dark figcaption { color: ${palette.slate300}; }
.tx-logos figure.on-light figcaption { color: ${palette.muted}; }
`;
