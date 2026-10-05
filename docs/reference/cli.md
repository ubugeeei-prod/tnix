---
title: CLI Reference
description: Every tnix command and flag, exit codes, and the JSON report schema.
---

# CLI Reference

```text
tnix COMMAND [OPTIONS]
```

| Command | Purpose |
| --- | --- |
| [`check`](#tnix-check) | type-check one file and print its types |
| [`compile`](#tnix-compile) | check one file and emit `.nix` |
| [`emit`](#tnix-emit) | check one file and emit a `.d.tnix` declaration |
| [`init`](#tnix-init) | create `tnix.config.tnix` and starter files |
| [`scaffold`](#tnix-scaffold) | create missing starter files from an existing config |
| [`check-project`](#tnix-check-project) | type-check every project source |
| [`build`](#tnix-build) | compile every project source and emit declarations |
| [`emit-project`](#tnix-emit-project) | emit declarations for every project source |
| [`version`](#tnix-version) | print the version |
| [`lsp`](#tnix-lsp) | start the language server over stdio |
| [`ide`](#tnix-ide) | install editor integrations, list supported editors |
| [`doctor`](#tnix-doctor) | check the toolchain, project and editor setup |

Global options: `-h`, `--help` on any command, and `-v`, `--version` at the top
level.

## Conventions

- **Exit status** is `0` on success and `1` when any diagnostic is reported or
  any file fails. Commands never write partial output on failure.
- **Diagnostics** have the shape `line:col: [CODE] message`, where `line:col`
  is the start of the offending expression (1-based). The few diagnostics
  without a source position omit the prefix. Codes are listed in
  [diagnostics](../diagnostics.md).
- **Output.** Results go to standard output. Text-mode errors go to standard
  error. With `--format json`, the JSON report (success or failure) goes to
  standard output.
- **Paths** given on the command line are relative to the current directory.
  `DIRECTORY` arguments default to the current directory.
- **Declarations.** Every analysis loads the declaration world of the file's
  workspace; see [how declaration files are found](../tutorial/declarations.md#how-declaration-files-are-found).

## `tnix check`

```text
tnix check FILE [-f|--format text|json]
```

Analyzes `FILE` and prints the inferred root type and the type of every
`let`-bound name of the root `let`, sorted by name:

```text
root: String
greeting :: String
```

A declaration-only file (`.d.tnix`) prints nothing when it checks. A failing
check prints the diagnostic to standard error and exits `1`:

```text
3:14: [TC0013] type mismatch: 42 vs String
```

## `tnix compile`

```text
tnix compile FILE [-o|--output OUTPUT] [--no-check]
```

Checks `FILE`, erases all type syntax and prints the resulting Nix, or writes
it to `OUTPUT` (parent directories are created; the write is atomic). Fails
without output if the file does not check. `--no-check` skips type checking
and only erases, like TypeScript's transpile-only mode: parse errors still
fail, type errors do not. A declaration-only file cannot be compiled.

## `tnix emit`

```text
tnix emit FILE [-o|--output OUTPUT]
```

Checks `FILE` and prints a declaration file describing it, or writes it to
`OUTPUT`. The `declare` target is `FILE` with a `.nix` extension, relative to
the declaration's location. Fails with `TD0008` for a declaration-only file.
See [declaration emit](./type-system-internals.md#erasure-and-compilation) for
how members are chosen.

## `tnix init`

```text
tnix init [DIRECTORY] [--editor EDITOR]...
```

Creates `DIRECTORY` if needed and writes a default `tnix.config.tnix`, then
runs [`scaffold`](#tnix-scaffold). Fails if `tnix.config.tnix` already exists.
The project name defaults to the directory name. Each `--editor` (repeatable)
also runs [`tnix ide install EDITOR`](#tnix-ide) for the new project.

## `tnix scaffold`

```text
tnix scaffold [DIRECTORY]
```

Reads `DIRECTORY/tnix.config.tnix` and creates whichever of these files are
missing, never overwriting existing ones:

- `tnix.config.d.tnix`: types for the config file,
- the `entry` file (by default `src/main.tnix`),
- `declarationDir/builtins.d.tnix` when `builtins = true`.

`builtins` is already typed by the prelude built into the binary. A scaffolded
`builtins.d.tnix` replaces that prelude with its short starter list, so delete
it (and set `builtins = false`) unless you want to restrict the builtins.

## `tnix check-project`

```text
tnix check-project [DIRECTORY] [-f|--format text|json]
```

Loads `DIRECTORY/tnix.config.tnix`, discovers sources (see
[source discovery](./config.md#source-discovery)), and checks every one, sharing
one declaration cache. All files are checked even if some fail.

```text
checked project hello-tnix
root: /home/you/hello-tnix
- ok src/main.tnix
  root: String
  greeting :: String
```

Fails with `no project source files discovered` when discovery finds nothing,
and with `missing tnix.config.tnix in DIRECTORY` without a config.

## `tnix build`

```text
tnix build [DIRECTORY] [-f|--format text|json]
```

For every discovered source, compiles it to `buildDir/<relative>.nix` and
emits `generatedDeclarationDir/<relative>.d.tnix`, where `<relative>` is the
source's path relative to `sourceDir` (or to the project root for sources
outside `sourceDir`). If **any** source fails, nothing is written.

## `tnix emit-project`

```text
tnix emit-project [DIRECTORY] [-f|--format text|json]
```

Like `build`, but writes only the declaration files.

## `tnix version`

```text
tnix version [-f|--format text|json]
```

Prints `tnix <version>`. `tnix --version` prints the same text.

## `tnix lsp`

```text
tnix lsp [--log-file PATH]
```

Executes `tnix-lsp --stdio`, which must be on `PATH`. Editors usually start
`tnix-lsp` directly; this subcommand exists so a single binary name can be
configured everywhere. `--log-file` is forwarded to the server.

## `tnix ide`

```text
tnix ide install vscode|cursor|vscodium|zed|neovim|helix
                 [--project DIR | -g|--global] [-n|--dry-run]
                 [--no-extension] [--force] [--lsp-path PATH]
tnix ide list
```

`tnix ide install EDITOR` installs the tnix extension (where the editor has
one) and merges the editor configuration that starts `tnix-lsp`: project
settings under the current directory (or `--project DIR`) by default, user
settings with `--global`. Settings are merged, never clobbered, and re-running
the command is a no-op. `--dry-run` prints the planned commands and a diff
without changing anything, `--no-extension` only writes configuration,
`--force` rewrites files that cannot be merged safely after saving a `.bak`
copy, and `--lsp-path` pins a `tnix-lsp` path (`""` pins nothing).

`tnix ide list` prints the supported editors and whether each one is detected.

[Editor setup](../editors.md) documents what each editor gets.

## `tnix doctor`

```text
tnix doctor [-f|--format text|json]
```

Checks that `tnix` and `tnix-lsp` are on `PATH` and report the same version,
that the current project's `tnix.config.tnix` loads, that each detected editor
has the tnix integration, and that `nix` is available. Each check prints one
line, with a suggested fix for each problem. Exits `1` if any check fails;
warnings do not change the exit status. See
[editor setup](../editors.md#tnix-doctor) for the list of checks and the JSON
report.

## JSON output

`--format json` is accepted by `check`, `check-project`, `build`,
`emit-project`, `version` and `doctor`. Every report is one JSON object on one line with
`schemaVersion` (currently `1`), `action`, and `success` or a `summary`.
Rendered types are strings in tnix syntax and may contain newlines.

`check`:

```json
{
  "schemaVersion": 1,
  "action": "check",
  "file": "hello.tnix",
  "success": true,
  "root": "String",
  "bindings": { "greeting": "String" },
  "error": null
}
```

On failure, `success` is `false`, `root` is `null`, `bindings` is empty and
`error` holds the diagnostic, for example
`"3:14: [TC0013] type mismatch: 42 vs String"`.

`check-project`:

```json
{
  "schemaVersion": 1,
  "action": "check-project",
  "projectName": "hello-tnix",
  "projectRoot": "/home/you/hello-tnix",
  "summary": { "total": 1, "ok": 1, "failed": 0 },
  "files": [
    {
      "source": "/home/you/hello-tnix/src/main.tnix",
      "relative": "main.tnix",
      "success": true,
      "root": "String",
      "bindings": { "greeting": "String" },
      "error": null
    }
  ]
}
```

`build` and `emit-project` have the same envelope with `action` set to
`"build"` or `"emit-project"`. Their `files` entries carry `source`,
`relative`, `runtimeOutput`, `declarationOutput`, `success` and `error`.

`version`:

```json
{ "schemaVersion": 1, "action": "version", "success": true, "version": "0.5.0.0" }
```

When a project cannot be loaded at all (missing or invalid config, no sources),
the project commands print
`{ "schemaVersion": 1, "action": ..., "projectRoot": ..., "projectName": ..., "success": false, "error": ... }`.
