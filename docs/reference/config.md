---
title: Configuration Reference
description: Every field of tnix.config.tnix, its default, and how project sources are discovered.
---

# Configuration Reference

A tnix project is a directory with a `tnix.config.tnix` file. The file is
parsed with the ordinary tnix parser and must be a single attribute set of
literal values: no `let`, no `inherit`, no computed values. Unknown fields are
ignored.

```tnix [tnix.config.tnix]
{
  name = "hello-tnix";
  sourceDir = ./src;
  entry = ./src/main.tnix;
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

`tnix init` writes exactly this file, with `name` set to the directory name.
The presence of `tnix.config.tnix` also marks the
[workspace root](./type-system-internals.md#declarations-and-the-ambient-world).

## Fields

Path values may be Nix path literals (`./src`) or strings (`"src"`). Relative
paths are resolved against the directory that contains `tnix.config.tnix`.

| Field | Type | Default | Used by |
| --- | --- | --- | --- |
| `name` | `String` | directory name | report headers |
| `sourceDir` | path | `./src` | source discovery, output layout |
| `entry` | path | `<sourceDir>/main.tnix` | `scaffold` (creates it if missing) |
| `declarationDir` | path | `./types` | `scaffold` (location of `builtins.d.tnix`) |
| `declarationPacks` | list of paths | `[]` | every analysis in the workspace |
| `buildDir` | path | `./dist` | `build` (compiled `.nix`) |
| `generatedDeclarationDir` | path | `<buildDir>/types` | `build`, `emit-project` |
| `entries` | list of paths | `[]` | source discovery |
| `include` | list of paths | `[]` | source discovery |
| `exclude` | list of paths | `[]` | source discovery |
| `builtins` | `Bool` | `true` | `scaffold` (whether to create `builtins.d.tnix`) |

`builtins` only controls scaffolding. Every analysis already types
`builtins` with the prelude built into tnix, and a scaffolded
`builtins.d.tnix` *replaces* that prelude with its short starter list. Set
`builtins = false;` and delete the file to keep the full prelude.

A field with the wrong kind of value fails the command, for example
`expected list of path-like values for include`. Errors from decoding
`declarationPacks` use the `TD0004` to `TD0006` codes, because that field is
read during every analysis, not just by project commands.

### `declarationPacks`

Each entry is a `.d.tnix` file or a directory, which is searched recursively
for `.d.tnix` files. Packs are loaded in addition to the declaration files that
already live under the workspace root, so you only need this field for
declarations stored *outside* the project, such as a vendored copy of the tnix
registry:

```tnix
{
  declarationPacks = [
    ./vendor/tnix/registry/ecosystem
    ./vendor/tnix/registry/workspace
  ];
}
```

Files under a `registry/workspace/` directory are rebased onto your project
root, so their `declare "../../flake.nix"` style targets describe *your*
`flake.nix` and `tnix.config.tnix`. An entry that does not exist, or a file that
is not `.d.tnix`, is `TD0006`.

## Source discovery

`check-project`, `build` and `emit-project` decide which files to process as
follows:

1. If `entries` is non-empty, use those paths. Directories are walked
   recursively; files are used as given.
2. Otherwise, walk `sourceDir` recursively.
3. Keep only files ending in `.tnix` and not in `.d.tnix`.
4. If `include` is non-empty, keep only files equal to or under one of its
   paths.
5. Drop files equal to or under any `exclude` path.

The walk follows symlinks but detects cycles and stops at a depth of 64.
Results are de-duplicated and sorted.

## Output layout

For a source file `S`, let `R` be its path relative to `sourceDir`, or relative
to the project root when `S` is outside `sourceDir` (possible with `entries`).

- `tnix build` writes `buildDir/R` with the extension `.nix`.
- `tnix build` and `tnix emit-project` write `generatedDeclarationDir/R` with
  the extension `.d.tnix`. Its `declare` target points at the compiled file.

Because generated declarations usually live under the project root, they are
also discovered as workspace declarations on the next run. That is intended:
it lets other files import the compiled output with types.

## `tnix.config.d.tnix`

`tnix scaffold` writes a declaration for the config file itself so that typed
code can `import ./tnix.config.tnix` and get a `TnixProjectConfig`:

```tnix [tnix.config.d.tnix]
type TnixProjectPath = Path | String;

type TnixProjectConfig = {
  name :: String;
  sourceDir :: TnixProjectPath;
  entry :: TnixProjectPath;
  declarationDir :: TnixProjectPath;
  declarationPacks :: List TnixProjectPath;
  buildDir :: TnixProjectPath;
  generatedDeclarationDir :: TnixProjectPath;
  entries :: List TnixProjectPath;
  include :: List TnixProjectPath;
  exclude :: List TnixProjectPath;
  builtins :: Bool;
};

declare "./tnix.config.tnix" {
  default :: TnixProjectConfig;
};
```
