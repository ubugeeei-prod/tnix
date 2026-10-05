---
title: "11. Projects"
description: Turn a directory into a tynix project with tynix init, configure it with tynix.config.tynix, and check, build and emit it as a whole.
---

# 11. Projects

So far you have checked files one at a time. A **project** tells tynix which
files belong together and where generated output goes, so one command can check
or build all of them.

## `tynix init`

Start a fresh project next to the tutorial directory:

```bash
tynix init hello-tynix
cd hello-tynix
```

```text
created:
- /home/you/hello-tynix/tynix.config.tynix
scaffolded hello-tynix
- created /home/you/hello-tynix/tynix.config.d.tynix
- created /home/you/hello-tynix/src/main.tynix
- created /home/you/hello-tynix/types/builtins.d.tynix
```

Without an argument, `tynix init` initializes the current directory. It refuses
to overwrite an existing `tynix.config.tynix`.

| File | Purpose |
| --- | --- |
| `tynix.config.tynix` | the project configuration |
| `tynix.config.d.tynix` | types for the configuration file itself |
| `src/main.tynix` | a starter source file |
| `types/builtins.d.tynix` | a starter `declare "builtins"` block |

> [!WARNING]
> A workspace `declare "builtins"` block *replaces* the built-in prelude that
> types every Nix builtin (step 6). The scaffolded starter only lists a few
> members, so delete `types/builtins.d.tynix` unless you deliberately want to
> restrict `builtins`. Set `builtins = false;` in the config to stop
> `tynix scaffold` from recreating it.

`tynix init` can also set up an editor in the same step:
`tynix init hello-tynix --editor vscode` runs `tynix ide install vscode` for the
new project (step 10).

## `tynix.config.tynix`

The configuration is itself a tynix attribute set:

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

The fields you will touch most:

- `sourceDir`: where `.tynix` sources are discovered (recursively).
- `entries`: explicit files or directories to use *instead of* walking
  `sourceDir`.
- `include` / `exclude`: path prefixes that filter the discovered files.
- `buildDir`: where `tynix build` writes compiled `.nix` files.
- `generatedDeclarationDir`: where generated `.d.tynix` files go.
- `declarationPacks`: extra `.d.tynix` files or directories to load, for example
  a vendored copy of the tynix registry.
- `builtins`: whether `tynix scaffold` creates `types/builtins.d.tynix`.

All paths are relative to the config file. The
[configuration reference](../reference/config.md) documents every field and
its default. `tynix.config.tynix` also marks the workspace root, so every
`.d.tynix` file under this directory is loaded automatically.

## `tynix check-project`

```bash
tynix check-project
```

```text
checked project hello-tynix
root: /home/you/hello-tynix
- ok src/main.tynix
  root: String
  greeting :: String
```

Add a broken file to see a failure:

```bash
printf 'let x :: Int; x = "a"; in x\n' > src/bad.tynix
tynix check-project
```

```text
checked project hello-tynix
root: /home/you/hello-tynix
- error src/bad.tynix
  [TC0013] type mismatch: "a" vs Int
- ok src/main.tynix
  root: String
  greeting :: String
```

Every file is checked even when an earlier one fails, and the command exits
with status `1`. Delete `src/bad.tynix` before continuing.

## `tynix build`

```bash
tynix build
```

```text
built project hello-tynix
root: /home/you/hello-tynix
- ok src/main.tynix
  nix -> /home/you/hello-tynix/dist/main.nix
  decl -> /home/you/hello-tynix/dist/types/main.d.tynix
```

For every source file, `build` writes the compiled `.nix` into `buildDir` and a
generated declaration into `generatedDeclarationDir`, mirroring the layout
under `sourceDir`. The generated declaration points back at the compiled file:

```tynix [dist/types/main.d.tynix]
declare "../main.nix" {
  default :: String;
};
```

`build` is all-or-nothing: if any file fails to check, nothing is written.
`tynix emit-project` writes only the declarations. `tynix scaffold` recreates any
starter file that is missing and never overwrites existing ones.

## Bring the tutorial files over

Move the files from `tynix-tour` into the project so they are checked together:

```bash
mkdir -p src types
cp ../tynix-tour/package.tynix ../tynix-tour/flake.tynix src/
cp ../tynix-tour/types/nixpkgs.d.tynix types/
tynix check-project
```

`types/nixpkgs.d.tynix` is picked up because it lives under the project root, as
is every other `.d.tynix` file there.

> [!TIP]
> Should `flake.tynix` compile to the repository root instead of `dist/`? Keep it
> out of the project build with `exclude = [ ./src/flake.tynix ];` and compile it
> explicitly with `tynix compile src/flake.tynix -o flake.nix`.

## Machine-readable output

`check`, `check-project`, `build`, `emit-project` and `version` accept
`--format json`:

```bash
tynix check-project --format json
```

```json
{"action":"check-project","files":[{"bindings":{"greeting":"String"},"error":null,"relative":"main.tynix","root":"String","source":"/home/you/hello-tynix/src/main.tynix","success":true}],"projectName":"hello-tynix","projectRoot":"/home/you/hello-tynix","schemaVersion":1,"summary":{"failed":0,"ok":1,"total":1}}
```

The shape is versioned by `schemaVersion` and documented in the
[CLI reference](../reference/cli.md#json-output). You will use it in the next
step.

<div class="tx-pager">

[← 10. Editor setup](./editor.md) [12. CI integration →](./ci.md)

</div>
