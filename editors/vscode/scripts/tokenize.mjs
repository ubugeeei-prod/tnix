#!/usr/bin/env node
// Tokenize tynix sources with the shipped TextMate grammar, exactly the way VS
// Code does (vscode-textmate + the Oniguruma WASM build).
//
//   node scripts/tokenize.mjs file.tynix   # print a token dump
//
// The module also exports `loadTynixGrammar` / `renderTokens` for the grammar
// snapshot tests in src/grammar.spec.ts.

import { readFileSync } from "node:fs";
import { createRequire } from "node:module";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const require = createRequire(import.meta.url);
const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const textmate = require("vscode-textmate");
const oniguruma = require("vscode-oniguruma");

let registryPromise;

function registry() {
  registryPromise ??= (async () => {
    const wasm = readFileSync(
      join(dirname(require.resolve("vscode-oniguruma")), "onig.wasm"),
    );
    await oniguruma.loadWASM(
      wasm.buffer.slice(wasm.byteOffset, wasm.byteOffset + wasm.byteLength),
    );
    const files = {
      "source.tynix": "syntaxes/tynix.tmLanguage.json",
      "markdown.tynix.codeblock":
        "syntaxes/tynix-markdown-injection.tmLanguage.json",
    };
    return new textmate.Registry({
      onigLib: Promise.resolve({
        createOnigScanner: (patterns) => new oniguruma.OnigScanner(patterns),
        createOnigString: (text) => new oniguruma.OnigString(text),
      }),
      loadGrammar: async (scopeName) => {
        const file = files[scopeName];
        if (!file) return null;
        return textmate.parseRawGrammar(
          readFileSync(join(root, file), "utf8"),
          join(root, file),
        );
      },
    });
  })();
  return registryPromise;
}

/** Load the `source.tynix` grammar. */
export async function loadTynixGrammar() {
  const grammar = await (await registry()).loadGrammar("source.tynix");
  if (!grammar) throw new Error("source.tynix grammar failed to load");
  return grammar;
}

/**
 * Tokenize `source` line by line.
 * @returns {{ line: number, text: string, scopes: string[] }[]}
 */
export async function tokenize(source) {
  const grammar = await loadTynixGrammar();
  let state = textmate.INITIAL;
  const tokens = [];
  source.split(/\r?\n/).forEach((lineText, index) => {
    const result = grammar.tokenizeLine(lineText, state);
    for (const token of result.tokens) {
      tokens.push({
        line: index + 1,
        text: lineText.slice(token.startIndex, token.endIndex),
        scopes: token.scopes,
      });
    }
    state = result.ruleStack;
  });
  return tokens;
}

/**
 * Depth of the TextMate rule stack after the last line. `1` means every
 * begin/end region opened in the file was closed again.
 */
export async function finalStackDepth(source) {
  const grammar = await loadTynixGrammar();
  let state = textmate.INITIAL;
  for (const lineText of source.split(/\r?\n/)) {
    state = grammar.tokenizeLine(lineText, state).ruleStack;
  }
  return state.depth;
}

/**
 * Render a stable, human-reviewable snapshot: one token per row, whitespace
 * tokens dropped, the root `source.tynix` scope elided.
 */
export async function renderTokens(source) {
  const rows = [];
  for (const token of await tokenize(source)) {
    if (token.text.trim() === "") continue;
    const scopes = token.scopes.filter((s) => s !== "source.tynix");
    rows.push(
      `${String(token.line).padStart(3)} ${JSON.stringify(token.text)} ${scopes.join(" ")}`.trimEnd(),
    );
  }
  return `${rows.join("\n")}\n`;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  for (const file of process.argv.slice(2)) {
    process.stdout.write(`== ${file}\n`);
    process.stdout.write(await renderTokens(readFileSync(file, "utf8")));
  }
}
