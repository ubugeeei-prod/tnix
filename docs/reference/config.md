---
title: Configuration Reference
description: Every field of tynix.config.tynix, its default, and how project sources are discovered.
---

# Configuration Reference

A tynix project is a directory with a `tynix.config.tynix` file. The file is
parsed with the ordinary tynix parser and must be a single attribute set of
literal values: no `let`, no `inherit`, no computed values. Unknown fields are
ignored.

```tynix [tynix.config.tynix]
{
  name = "hello-tynix";
  sourceDir = ./src;
  entry = ./src/main.tynix;
  declarationDir = ./types;
  declarationPacks = [];
  buildDir = ./dist;
  generatedDeclarationDir = ./dist/types;
  entries = [];
  include = [];
  exclude = [];
  builtins = true;
}
```

`tynix init` writes exactly this file, with `name` set to the directory name.
The presence of `tynix.config.tynix` also marks the
[workspace root](./type-system-internals.md#declarations-and-the-ambient-world).

## Fields

Path values may be Nix path literals (`./src`) or strings (`"src"`). Relative
paths are resolved against the directory that contains `tynix.config.tynix`.

| Field | Type | Default | Used by |
| --- | --- | --- | --- |
| `name` | `String` | directory name | report headers |
| `sourceDir` | path | `./src` | source discovery, output layout |
| `entry` | path | `<sourceDir>/main.tynix` | `scaffold` (creates it if missing) |
| `declarationDir` | path | `./types` | `scaffold` (location of `builtins.d.tynix`) |
| `declarationPacks` | list of paths | `[]` | every analysis in the workspace |
| `buildDir` | path | `./dist` | `build` (compiled `.nix`) |
| `generatedDeclarationDir` | path | `<buildDir>/types` | `build`, `emit-project` |
| `entries` | list of paths | `[]` | source discovery |
| `include` | list of paths | `[]` | source discovery |
| `exclude` | list of paths | `[]` | source discovery |
| `builtins` | `Bool` | `true` | `scaffold` (whether to create `builtins.d.tynix`) |

`builtins` only controls scaffolding. Every analysis already types
`builtins` with the prelude built into tynix, and a scaffolded
`builtins.d.tynix` *replaces* that prelude with its short starter list. Set
`builtins = false;` and delete the file to keep the full prelude.

A field with the wrong kind of value fails the command, for example
`expected list of path-like values for include`. Errors from decoding
`declarationPacks` use the `TD0004` to `TD0006` codes, because that field is
read during every analysis, not just by project commands.

### `declarationPacks`

Each entry is a `.d.tynix` file or a directory, which is searched recursively
for `.d.tynix` files. Packs are loaded in addition to the declaration files that
already live under the workspace root, so you only need this field for
declarations stored *outside* the project, such as a vendored copy of the tynix
registry:

```tynix
{
  declarationPacks = [
    ./vendor/tynix/registry/ecosystem
    ./vendor/tynix/registry/workspace
  ];
}
```

Files under a `registry/workspace/` directory are rebased onto your project
root, so their `declare "../../flake.nix"` style targets describe *your*
`flake.nix` and `tynix.config.tynix`. An entry that does not exist, or a file that
is not `.d.tynix`, is `TD0006`.

## Source discovery

`check-project`, `build` and `emit-project` decide which files to process as
follows:

1. If `entries` is non-empty, use those paths. Directories are walked
   recursively; files are used as given.
2. Otherwise, walk `sourceDir` recursively.
3. Keep only files ending in `.tynix` and not in `.d.tynix`.
4. If `include` is non-empty, keep only files equal to or under one of its
   paths.
5. Drop files equal to or under any `exclude` path.

The walk follows symlinks but detects cycles and stops at a depth of 64.
Results are de-duplicated and sorted.

## Output layout

For a source file `S`, let `R` be its path relative to `sourceDir`, or relative
to the project root when `S` is outside `sourceDir` (possible with `entries`).

- `tynix build` writes `buildDir/R` with the extension `.nix`.
- `tynix build` and `tynix emit-project` write `generatedDeclarationDir/R` with
  the extension `.d.tynix`. Its `declare` target points at the compiled file.

Because generated declarations usually live under the project root, they are
also discovered as workspace declarations on the next run. That is intended:
it lets other files import the compiled output with types.

## `tynix.config.d.tynix`

`tynix scaffold` writes a declaration for the config file itself so that typed
code can `import ./tynix.config.tynix` and get a `TynixProjectConfig`:

```tynix [tynix.config.d.tynix]
type TynixProjectPath = Path | String;

type TynixProjectConfig = {
  name :: String;
  sourceDir :: TynixProjectPath;
  entry :: TynixProjectPath;
  declarationDir :: TynixProjectPath;
  declarationPacks :: List TynixProjectPath;
  buildDir :: TynixProjectPath;
  generatedDeclarationDir :: TynixProjectPath;
  entries :: List TynixProjectPath;
  include :: List TynixProjectPath;
  exclude :: List TynixProjectPath;
  builtins :: Bool;
};

declare "./tynix.config.tynix" {
  default :: TynixProjectConfig;
};
```
