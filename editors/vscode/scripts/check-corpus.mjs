#!/usr/bin/env node
// Tokenize every .tynix / .d.tynix / .nix file in the repository corpus and
// report files whose TextMate rule stack does not return to the top level at
// end of file (a strong signal that a begin/end region leaked).
//
//   node scripts/check-corpus.mjs            # scan the default corpus
//   node scripts/check-corpus.mjs a.tynix ... # scan specific files

import { readdirSync, readFileSync, statSync } from "node:fs";
import { dirname, join, relative } from "node:path";
import { fileURLToPath } from "node:url";
import { finalStackDepth } from "./tokenize.mjs";

const extensionRoot = join(dirname(fileURLToPath(import.meta.url)), "..");
const repoRoot = join(extensionRoot, "..", "..");

const SKIP = new Set([
  "node_modules",
  ".git",
  "dist",
  "out",
  "target",
  ".vscode-test",
  "dist-newstyle",
]);

function walk(dir, files = []) {
  for (const entry of readdirSync(dir)) {
    if (SKIP.has(entry) || entry.startsWith(".")) continue;
    const full = join(dir, entry);
    const stat = statSync(full);
    if (stat.isDirectory()) walk(full, files);
    else if (/\.(tynix|nix)$/.test(entry)) files.push(full);
  }
  return files;
}

export function defaultCorpus() {
  const roots = [
    "examples",
    "dogfood",
    "registry",
    "editors/vscode/test/grammar",
    "editors/tree-sitter-tynix/examples",
  ];
  const files = roots.flatMap((dir) => {
    try {
      return walk(join(repoRoot, dir));
    } catch {
      return [];
    }
  });
  for (const top of readdirSync(repoRoot)) {
    if (/\.(tynix|nix)$/.test(top)) files.push(join(repoRoot, top));
  }
  return files.sort();
}

export async function checkCorpus(files = defaultCorpus()) {
  const failures = [];
  for (const file of files) {
    const depth = await finalStackDepth(readFileSync(file, "utf8"));
    if (depth !== 1) failures.push({ file: relative(repoRoot, file), depth });
  }
  return { files: files.length, failures };
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  let args = process.argv.slice(2);
  // `--list files.txt` reads newline-separated paths (handy for big corpora
  // such as a nixpkgs checkout).
  if (args[0] === "--list") {
    args = readFileSync(args[1], "utf8").split("\n").filter(Boolean);
  }
  const { files, failures } = await checkCorpus(
    args.length > 0 ? args : undefined,
  );
  for (const failure of failures) {
    console.error(`unbalanced (stack depth ${failure.depth}): ${failure.file}`);
  }
  console.log(
    `${files - failures.length}/${files} files tokenized back to the top level`,
  );
  if (failures.length > 0) process.exit(1);
}
