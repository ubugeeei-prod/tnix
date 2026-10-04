---
title: Brand
description: The tnix brand system, covering positioning, voice, name usage, logo, color, typography and code theme.
---

# Brand

This page is the source of truth for how tnix looks and sounds. The tokens on
this page are implemented in
[`docs/.vite/brand.ts`](https://github.com/ubugeeei-prod/tnix/blob/main/docs/.vite/brand.ts),
and the asset files live in
[`docs/public/brand/`](https://github.com/ubugeeei-prod/tnix/tree/main/docs/public/brand).
Change both together.

## Positioning

**TypeScript-grade types for Nix. Zero runtime.**

tnix is for people who already write Nix and are tired of finding attribute
typos at evaluation time. It gives them what TypeScript gave JavaScript: an
optional, gradual, structural type layer with first-class editor support, which
compiles away completely.

| | |
| --- | --- |
| **Category** | gradual type system and toolchain for Nix |
| **Audience** | Nix users maintaining flakes, packages, modules and shared libraries |
| **Promise** | catch shape errors before evaluation, without changing what Nix runs |
| **Proof points** | erasure-only compiler, structural records, `.d.tnix` declarations, LSP, stable diagnostic codes |
| **Not** | a new Nix, a runtime contract system, or a replacement for the module system's option types |

### Taglines

- Primary: **TypeScript-grade types for Nix. Zero runtime.**
- Short: **Type your Nix. Ship plain Nix.**
- Descriptive: *Write `.tnix`, check it, ship plain `.nix`.*

Use the primary tagline on the home page, the OG image and package
descriptions. The short one fits badges, social bios and slide footers.

## Voice and tone

tnix speaks like a careful senior engineer reviewing your pull request:
precise, calm, and on your side.

- **Concrete over clever.** Show the code and the exact diagnostic. "Selecting
  `pkg.pname` from an unannotated parameter fails with `TC0009`" beats "tnix
  catches tricky bugs".
- **Honest about limits.** Say what is not supported yet and what to do
  instead. Mark upcoming features as upcoming.
- **Respect Nix.** tnix adds to Nix; it does not fix it. Never frame Nix as
  broken or tnix as a replacement.
- **Short sentences, active voice, second person.** "Annotate the parameter",
  not "the parameter should be annotated by the user".
- **No hype words.** Avoid "blazing", "magical", "revolutionary",
  "seamless". Measurable claims only.
- **Diagnostics are part of the voice.** Error messages state what was found and
  what was expected, in that order, with the code first:
  `[TC0013] type mismatch: 42 vs String`.

## Name usage

- The name is always lowercase **`tnix`**, including at the start of a
  sentence and in titles: "tnix checks records structurally."
- Never `TNix`, `TNIX`, `T-Nix` or `Tnix`. Not abbreviated, not pluralized.
- Pronounce it "tee-nix".
- In running text, use plain `tnix`. Use code formatting (`` `tnix` ``) only
  when you mean the command or the binary.
- File types are written with their dot: `.tnix`, `.d.tnix`, `.nix`.
- Nix is capitalized when you mean the language or package manager, as the Nix
  project does.

## Logo

The mark is a rounded hexagon, a nod to the hexagonal Nix snowflake, holding a
lowercase **t** followed by a **colon**: `t:`, the start of a type annotation.
The colon is mint, the color the docs use for "checked".

<div class="tx-logos">
<figure class="on-light"><img src="/brand/tnix-logo.svg" alt="tnix logo, color, for light backgrounds"><figcaption>tnix-logo.svg</figcaption></figure>
<figure class="on-dark"><img src="/brand/tnix-logo-dark.svg" alt="tnix logo, color, for dark backgrounds"><figcaption>tnix-logo-dark.svg</figcaption></figure>
<figure class="on-light"><img src="/brand/tnix-logo-mono.svg" alt="tnix logo, single color ink"><figcaption>tnix-logo-mono.svg</figcaption></figure>
<figure class="on-dark"><img src="/brand/tnix-logo-white.svg" alt="tnix logo, single color white"><figcaption>tnix-logo-white.svg</figcaption></figure>
<figure class="on-light"><img src="/brand/tnix-mark.svg" alt="tnix mark, color"><figcaption>tnix-mark.svg</figcaption></figure>
<figure class="on-dark"><img src="/brand/tnix-mark-white.svg" alt="tnix mark, white"><figcaption>tnix-mark-white.svg</figcaption></figure>
</div>

| File | Use |
| --- | --- |
| `brand/tnix-logo.svg` | default lockup on light backgrounds |
| `brand/tnix-logo-dark.svg` | lockup on dark backgrounds |
| `brand/tnix-logo-mono.svg`, `brand/tnix-logo-white.svg` | one-color print, embossing, single-color UIs |
| `brand/tnix-mark.svg` | the mark alone: avatars, the docs header, app icons |
| `brand/tnix-mark-mono.svg`, `brand/tnix-mark-white.svg` | one-color mark; the `t:` is knocked out, not painted |
| `brand/tnix-wordmark.svg` | the wordmark alone, where the mark already appears nearby |
| `brand/tnix-mark-512.png` | raster mark for places that do not accept SVG |
| `favicon.svg`, `apple-touch-icon.png` | browser and home-screen icons |
| `og-image.png` (source `brand/og-image.svg`) | 1200 × 630 social preview |

Rules:

- Keep clear space around the logo of at least the width of the colon on all
  sides. Do not place it on busy imagery.
- Minimum size: 16 px tall for the mark, 20 px tall for the lockup.
- Do not recolor, rotate, outline, add shadows to, or re-typeset the wordmark.
  The wordmark is drawn, not set in a font; use the files.
- On photos or saturated backgrounds, use the white one-color version.

## Color

The palette starts from the two Nix logo blues (`#5277C3`, `#7EBAE4`) and moves
to a deeper, more saturated **Lambda Blue**, so tnix reads as related to Nix
without impersonating it. Two accents carry meaning in code and UI: **Annotation
Amber** marks type-only syntax (everything that is erased), and **Check Mint**
marks values and success.

### Core

<div class="tx-swatches">
<div class="tx-swatch"><i style="background:#2F5BD8"></i><b>Lambda Blue 600</b><code>#2F5BD8</code></div>
<div class="tx-swatch"><i style="background:#2449B8"></i><b>Lambda Blue 700</b><code>#2449B8</code></div>
<div class="tx-swatch"><i style="background:#3B63E0"></i><b>Lambda Blue 500</b><code>#3B63E0</code></div>
<div class="tx-swatch"><i style="background:#8DB4FF"></i><b>Lambda Blue 300</b><code>#8DB4FF</code></div>
<div class="tx-swatch"><i style="background:#7EBAE4"></i><b>Snow Blue</b><code>#7EBAE4</code></div>
<div class="tx-swatch"><i style="background:#F2B441"></i><b>Annotation Amber</b><code>#F2B441</code></div>
<div class="tx-swatch"><i style="background:#5FE0BC"></i><b>Check Mint</b><code>#5FE0BC</code></div>
<div class="tx-swatch"><i style="background:#087A5F"></i><b>Check Mint 700</b><code>#087A5F</code></div>
<div class="tx-swatch"><i style="background:#FF8A7A"></i><b>Coral</b><code>#FF8A7A</code></div>
</div>

### Neutrals

<div class="tx-swatches">
<div class="tx-swatch"><i style="background:#0A0F1C"></i><b>Ink 950</b><code>#0A0F1C</code></div>
<div class="tx-swatch"><i style="background:#0B1220"></i><b>Ink 900</b><code>#0B1220</code></div>
<div class="tx-swatch"><i style="background:#111A2E"></i><b>Ink 850</b><code>#111A2E</code></div>
<div class="tx-swatch"><i style="background:#22304D"></i><b>Ink 700</b><code>#22304D</code></div>
<div class="tx-swatch"><i style="background:#4A5871"></i><b>Slate 600</b><code>#4A5871</code></div>
<div class="tx-swatch"><i style="background:#A3B0C7"></i><b>Slate 300</b><code>#A3B0C7</code></div>
<div class="tx-swatch"><i style="background:#DCE3EE"></i><b>Line</b><code>#DCE3EE</code></div>
<div class="tx-swatch"><i style="background:#F1F5FB"></i><b>Mist</b><code>#F1F5FB</code></div>
<div class="tx-swatch"><i style="background:#FBFCFE"></i><b>Paper</b><code>#FBFCFE</code></div>
</div>

### Theme tokens

| Token | Light | Dark |
| --- | --- | --- |
| `primary` | Lambda Blue 600 `#2F5BD8` | Lambda Blue 300 `#8DB4FF` |
| `primaryHover` | Lambda Blue 700 `#2449B8` | `#B8D0FF` |
| `background` | Paper `#FBFCFE` | Ink 950 `#0A0F1C` |
| `backgroundAlt` | Mist `#F1F5FB` | Ink 850 `#111A2E` |
| `text` | `#0E1525` | `#E6ECF7` |
| `textMuted` | Slate 600 `#4A5871` | Slate 300 `#A3B0C7` |
| `border` | Line `#DCE3EE` | Ink 700 `#22304D` |
| `codeBackground` | Ink 900 `#0B1220` | Ink 900 `#0B1220` |

### Contrast

All text pairings meet WCAG 2.2 AA (4.5:1 for body text); most meet AAA.

| Pair | Ratio |
| --- | --- |
| text `#0E1525` on Paper | 17.75:1 |
| Slate 600 on Paper | 6.99:1 |
| Lambda Blue 600 on Paper (links) | 5.67:1 |
| white on Lambda Blue 600 (buttons) | 5.82:1 |
| `#E6ECF7` on Ink 950 | 16.13:1 |
| Slate 300 on Ink 950 | 8.74:1 |
| Lambda Blue 300 on Ink 950 (links) | 9.20:1 |
| Ink 950 on Lambda Blue 300 (dark-mode buttons) | 9.20:1 |
| Annotation Amber on Ink 900 (code) | 10.15:1 |
| Check Mint on Ink 900 (code) | 11.48:1 |
| comment `#7F8DAA` on Ink 900 (code) | 5.61:1 |

Check Mint `#5FE0BC` and Annotation Amber are for dark surfaces. On light
surfaces, use Check Mint 700 `#087A5F` and Amber 700 `#8A5A00` for text.

## Typography

| Role | Typeface | Fallback stack |
| --- | --- | --- |
| UI and prose | [Geist](https://fonts.google.com/specimen/Geist) 400, 500, 600, 700, 800 | Inter, `system-ui`, -apple-system, Segoe UI, sans-serif |
| Code | [Geist Mono](https://fonts.google.com/specimen/Geist+Mono) 400, 500, 600 | JetBrains Mono, `ui-monospace`, SF Mono, Menlo, Consolas, monospace |

Both are open source (SIL OFL) and served from Google Fonts on the docs site.
Headings use weight 700 to 800 with slightly negative tracking (`-0.025em`);
body text uses 400 at 16 px with a 1.7 line height. The wordmark is custom
drawn and is not set in Geist.

## Code theme: tnix ink

Code blocks are always dark (Ink 900) so the semantic colors work the same in
both site themes. The theme, `tnix-ink`, follows one idea: **amber is for
anything the compiler erases.**

| Token | Color |
| --- | --- |
| type-only syntax: `::`, `type`, `declare`, `forall`, `extends`, `infer`, `as`, type names | Annotation Amber `#F2B441` |
| gradual types: `dynamic`, `unknown`, `any` | Annotation Amber, italic |
| keywords: `let`, `in`, `if`, `with`, `rec`, `inherit`, `import` | Lambda Blue 300 `#8DB4FF` |
| strings and paths | Check Mint `#5FE0BC` |
| numbers, `true`, `false`, `null` | Coral `#FF8A7A` |
| attribute names | `#C9D7F2` |
| comments | `#7F8DAA`, italic |
| `# @tnix-ignore` / `# @tnix-expected` | Check Mint, bold |
| plain text | `#DCE6F8` |

```tnix
type Package = { pname :: String; version :: String; };

let
  # @tnix-ignore
  describe = (pkg :: Package): "${pkg.pname}-${pkg.version}";
  hello = { pname = "hello"; version = "2.12.1"; } as Package;
in describe hello
```

The TextMate grammar used for docs highlighting lives in
[`docs/.vite/tnix-grammar.ts`](https://github.com/ubugeeei-prod/tnix/blob/main/docs/.vite/tnix-grammar.ts).
Editors get semantic highlighting from the language server instead.

## Imagery and layout

- Hexagons, the colon and thin connector lines are the recurring motifs. Use
  them sparingly as structure (backgrounds, diagrams), never as decoration on
  top of content.
- Diagrams use the theme's surface colors with Lambda Blue for "process",
  Amber for "type-level" and Mint for "output".
- Prefer real code and real diagnostics over illustrations.
