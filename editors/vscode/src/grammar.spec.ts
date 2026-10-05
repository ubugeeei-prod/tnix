import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import {
  existsSync,
  mkdirSync,
  readFileSync,
  readdirSync,
  writeFileSync,
} from "node:fs";
import { dirname, join } from "node:path";
import test from "node:test";
import { fileURLToPath, pathToFileURL } from "node:url";

// Compiled to dist/grammar.spec.js, so the extension root is one level up.
const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const fixtures = join(root, "test", "grammar");
const snapshots = join(fixtures, "__snapshots__");
const update = process.env.UPDATE_SNAPSHOTS === "1";

type Token = { line: number; text: string; scopes: string[] };
type TokenizeModule = {
  tokenize(source: string): Promise<Token[]>;
  renderTokens(source: string): Promise<string>;
};
type CorpusModule = {
  checkCorpus(): Promise<{
    files: number;
    failures: { file: string; depth: number }[];
  }>;
};

const load = <T>(file: string): Promise<T> =>
  import(pathToFileURL(join(root, "scripts", file)).href) as Promise<T>;

async function scopesOf(source: string, text: string, nth = 0) {
  const { tokenize } = await load<TokenizeModule>("tokenize.mjs");
  const matches = (await tokenize(source)).filter((t) => t.text === text);
  assert.ok(matches[nth], `token ${JSON.stringify(text)} not found`);
  return matches[nth].scopes;
}

async function assertScope(source: string, text: string, scope: string) {
  const scopes = await scopesOf(source, text);
  assert.ok(
    scopes.some((s) => s === scope || s.startsWith(`${scope}.`)),
    `${JSON.stringify(text)} in ${JSON.stringify(source)} should carry ${scope}; got ${scopes.join(" ")}`,
  );
}

test("generated grammar JSON is in sync with scripts/build-grammar.mjs", () => {
  execFileSync(
    process.execPath,
    [join(root, "scripts", "build-grammar.mjs"), "--check"],
    {
      stdio: "pipe",
    },
  );
});

test("grammar snapshots match test/grammar/__snapshots__", async () => {
  const { renderTokens } = await load<TokenizeModule>("tokenize.mjs");
  const inputs = readdirSync(fixtures).filter((f) => /\.(tynix|nix)$/.test(f));
  assert.ok(inputs.length > 0, "grammar fixtures should exist");
  mkdirSync(snapshots, { recursive: true });
  for (const input of inputs) {
    const actual = await renderTokens(
      readFileSync(join(fixtures, input), "utf8"),
    );
    const snapshotFile = join(snapshots, `${input}.snap`);
    if (update || !existsSync(snapshotFile)) {
      writeFileSync(snapshotFile, actual);
      continue;
    }
    assert.equal(
      actual,
      readFileSync(snapshotFile, "utf8"),
      `${input} tokens changed; rerun with UPDATE_SNAPSHOTS=1 if intended`,
    );
  }
});

test("every repository .tynix/.d.tynix/.nix file tokenizes back to the top level", async () => {
  const { checkCorpus } = await load<CorpusModule>("check-corpus.mjs");
  const { files, failures } = await checkCorpus();
  assert.ok(files > 10, "corpus should contain the examples");
  assert.deepEqual(failures, []);
});

test("tynix declarations", async () => {
  const alias = "type Box a = { value :: a; };";
  await assertScope(alias, "type", "storage.type.type");
  await assertScope(alias, "Box", "entity.name.type.alias");
  await assertScope(alias, "a", "entity.name.type.parameter");
  await assertScope(alias, "value", "entity.other.attribute-name");

  const declare = 'declare "./lib.nix" { mk :: Int -> Int; };';
  await assertScope(declare, "declare", "storage.modifier.declare");
  await assertScope(declare, "mk", "entity.name.function");
  await assertScope(declare, "->", "storage.type.function.arrow");
});

test("type syntax", async () => {
  const src =
    "f :: forall a. Show a => (a %1 -> String) | unknown | Vec 3 Int | t extends List (infer e) ? e : dynamic;";
  await assertScope(src, "forall", "keyword.other.forall");
  await assertScope(src, "=>", "keyword.operator.type.constraint");
  await assertScope(src, "%1", "storage.modifier.linear");
  await assertScope(src, "|", "keyword.operator.type.union");
  await assertScope(src, "unknown", "support.type.primitive.gradual");
  await assertScope(src, "dynamic", "support.type.primitive.gradual");
  await assertScope(src, "Vec", "support.type.builtin");
  await assertScope(src, "3", "constant.numeric.integer");
  await assertScope(src, "extends", "storage.modifier.extends");
  await assertScope(src, "infer", "keyword.operator.expression.infer");
  await assertScope(src, "Show", "entity.name.type");
});

test("casts and typed binders", async () => {
  await assertScope("x as { a :: Int; }", "as", "keyword.control.as");
  await assertScope("x as { a :: Int; }", "Int", "support.type.primitive");
  await assertScope("(x :: Int): x", "x", "variable.parameter");
  // `as` must not leak past the end of the cast.
  const after = await scopesOf("f (x as Int) == y", "y");
  assert.ok(!after.some((s) => s.startsWith("meta.cast")), after.join(" "));
  // Identifiers merely containing `as` are not casts.
  await assertScope("has-as = 1;", "has-as", "entity.other.attribute-name");
});

test("diagnostic directives", async () => {
  await assertScope(
    "# @tynix-ignore\nx",
    "@tynix-ignore",
    "keyword.control.directive",
  );
  await assertScope(
    "  # @tynix-expected",
    "@tynix-expected",
    "keyword.control.directive",
  );
  // Only whole-line comments are directives.
  const trailing = await scopesOf("x # @tynix-ignore", " @tynix-ignore");
  assert.ok(!trailing.some((s) => s.includes("directive")), trailing.join(" "));
});

test("Nix strings, paths and URIs", async () => {
  await assertScope('"a ${b} c"', "b", "meta.embedded.interpolation");
  await assertScope(
    "'' ''${x} ''' ''\\n ''",
    "''$",
    "constant.character.escape",
  );
  await assertScope(
    "'' ''${x} ''' ''\\n ''",
    "'''",
    "constant.character.escape",
  );
  await assertScope(
    "'' ''${x} ''' ''\\n ''",
    "''\\n",
    "constant.character.escape",
  );
  await assertScope("./a/b.nix", "./a/b.nix", "string.unquoted.path");
  await assertScope("~/x", "~/x", "string.unquoted.path");
  await assertScope("<nixpkgs>", "<nixpkgs>", "string.unquoted.spath");
  await assertScope("./p/${x}", "./p/", "string.unquoted.path");
  await assertScope(
    "https://x.org/y",
    "https://x.org/y",
    "string.unquoted.uri",
  );
  await assertScope("a // b", "//", "keyword.operator.update");
  await assertScope("a ++ b", "++", "keyword.operator.concat");
  await assertScope("a |> f", "|>", "keyword.operator.pipe");
});

test("Nix bindings and lambdas", async () => {
  const src =
    "{ a, b ? 1, ... }@args: { f = x: x; inherit (args) c; d.e = 1; }";
  await assertScope(src, "a", "variable.parameter");
  await assertScope(src, "?", "keyword.operator.default");
  await assertScope(src, "...", "keyword.operator.ellipsis");
  await assertScope(src, "args", "variable.parameter");
  await assertScope(src, "f", "entity.name.function");
  await assertScope(src, "inherit", "keyword.other.inherit");
  await assertScope(src, "c", "entity.other.attribute-name");
  await assertScope(
    "builtins.map f xs",
    "builtins",
    "variable.language.builtins",
  );
  await assertScope("builtins.map f xs", "map", "support.function.builtin");
  await assertScope("x.y or z", "or", "keyword.operator.or");
  // `with e;` must not terminate the enclosing binding.
  const withSrc = "{ meta = with lib; { a = 1; }; b = 2; }";
  await assertScope(withSrc, "b", "entity.other.attribute-name");
});
