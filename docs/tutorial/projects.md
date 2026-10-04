---
title: "11. Projects"
description: Turn a directory into a tnix project with tnix init, configure it with tnix.config.tnix, and check, build and emit it as a whole.
---

# 11. Projects

So far you have checked files one at a time. A **project** tells tnix which
files belong together and where generated output goes, so one command can check
or build all of them.

## `tnix init`

Start a fresh project next to the tutorial directory:

```bash
tnix init hello-tnix
cd hello-tnix
```

```text
created:
- /home/you/hello-tnix/tnix.config.tnix
scaffolded hello-tnix
- created /home/you/hello-tnix/tnix.config.d.tnix
- created /home/you/hello-tnix/src/main.tnix
- created /home/you/hello-tnix/types/builtins.d.tnix
```

Without an argument, `tnix init` initializes the current directory. It refuses
to overwrite an existing `tnix.config.tnix`.

| File | Purpose |
| --- | --- |
| `tnix.config.tnix` | the project configuration |
| `tnix.config.d.tnix` | types for the configuration file itself |
| `src/main.tnix` | a starter source file |
| `types/builtins.d.tnix` | a starter `declare "builtins"` block |

> [!WARNING]
> A workspace `declare "builtins"` block *replaces* the built-in prelude that
> types every Nix builtin (step 6). The scaffolded starter only lists a few
> members, so delete `types/builtins.d.tnix` unless you deliberately want to
> restrict `builtins`. Set `builtins = false;` in the config to stop
> `tnix scaffold` from recreating it.

`tnix init` can also set up an editor in the same step:
`tnix init hello-tnix --editor vscode` runs `tnix ide install vscode` for the
new project (step 10).

## `tnix.config.tnix`

The configuration is itself a tnix attribute set:

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

The fields you will touch most:

- `sourceDir`: where `.tnix` sources are discovered (recursively).
- `entries`: explicit files or directories to use *instead of* walking
  `sourceDir`.
- `include` / `exclude`: path prefixes that filter the discovered files.
- `buildDir`: where `tnix build` writes compiled `.nix` files.
- `generatedDeclarationDir`: where generated `.d.tnix` files go.
- `declarationPacks`: extra `.d.tnix` files or directories to load, for example
  a vendored copy of the tnix registry.
- `builtins`: whether `tnix scaffold` creates `types/builtins.d.tnix`.

All paths are relative to the config file. The
[configuration reference](../reference/config.md) documents every field and
its default. `tnix.config.tnix` also marks the workspace root, so every
`.d.tnix` file under this directory is loaded automatically.

## `tnix check-project`

```bash
tnix check-project
```

```text
checked project hello-tnix
root: /home/you/hello-tnix
- ok src/main.tnix
  root: String
  greeting :: String
```

Add a broken file to see a failure:

```bash
printf 'let x :: Int; x = "a"; in x\n' > src/bad.tnix
tnix check-project
```

```text
checked project hello-tnix
root: /home/you/hello-tnix
- error src/bad.tnix
  [TC0013] type mismatch: "a" vs Int
- ok src/main.tnix
  root: String
  greeting :: String
```

Every file is checked even when an earlier one fails, and the command exits
with status `1`. Delete `src/bad.tnix` before continuing.

## `tnix build`

```bash
tnix build
```

```text
built project hello-tnix
root: /home/you/hello-tnix
- ok src/main.tnix
  nix -> /home/you/hello-tnix/dist/main.nix
  decl -> /home/you/hello-tnix/dist/types/main.d.tnix
```

For every source file, `build` writes the compiled `.nix` into `buildDir` and a
generated declaration into `generatedDeclarationDir`, mirroring the layout
under `sourceDir`. The generated declaration points back at the compiled file:

```tnix [dist/types/main.d.tnix]
declare "../main.nix" {
  default :: String;
};
```

`build` is all-or-nothing: if any file fails to check, nothing is written.
`tnix emit-project` writes only the declarations. `tnix scaffold` recreates any
starter file that is missing and never overwrites existing ones.

## Bring the tutorial files over

Move the files from `tnix-tour` into the project so they are checked together:

```bash
mkdir -p src types
cp ../tnix-tour/package.tnix ../tnix-tour/flake.tnix src/
cp ../tnix-tour/types/nixpkgs.d.tnix types/
tnix check-project
```

`types/nixpkgs.d.tnix` is picked up because it lives under the project root, as
is every other `.d.tnix` file there.

> [!TIP]
> Should `flake.tnix` compile to the repository root instead of `dist/`? Keep it
> out of the project build with `exclude = [ ./src/flake.tnix ];` and compile it
> explicitly with `tnix compile src/flake.tnix -o flake.nix`.

## Machine-readable output

`check`, `check-project`, `build`, `emit-project` and `version` accept
`--format json`:

```bash
tnix check-project --format json
```

```json
{"action":"check-project","files":[{"bindings":{"greeting":"String"},"error":null,"relative":"main.tnix","root":"String","source":"/home/you/hello-tnix/src/main.tnix","success":true}],"projectName":"hello-tnix","projectRoot":"/home/you/hello-tnix","schemaVersion":1,"summary":{"failed":0,"ok":1,"total":1}}
```

The shape is versioned by `schemaVersion` and documented in the
[CLI reference](../reference/cli.md#json-output). You will use it in the next
step.

<div class="tx-pager">

[← 10. Editor setup](./editor.md) [12. CI integration →](./ci.md)

</div>
