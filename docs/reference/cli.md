---
title: CLI Reference
description: Every tynix command and flag, exit codes, and the JSON report schema.
---

# CLI Reference

```text
tynix COMMAND [OPTIONS]
```

| Command | Purpose |
| --- | --- |
| [`check`](#tynix-check) | type-check one file and print its types |
| [`compile`](#tynix-compile) | check one file and emit `.nix` |
| [`emit`](#tynix-emit) | check one file and emit a `.d.tynix` declaration |
| [`init`](#tynix-init) | create `tynix.config.tynix` and starter files |
| [`scaffold`](#tynix-scaffold) | create missing starter files from an existing config |
| [`check-project`](#tynix-check-project) | type-check every project source |
| [`build`](#tynix-build) | compile every project source and emit declarations |
| [`emit-project`](#tynix-emit-project) | emit declarations for every project source |
| [`version`](#tynix-version) | print the version |
| [`lsp`](#tynix-lsp) | start the language server over stdio |
| [`ide`](#tynix-ide) | install editor integrations, list supported editors |
| [`doctor`](#tynix-doctor) | check the toolchain, project and editor setup |

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

## `tynix check`

```text
tynix check FILE [-f|--format text|json]
```

Analyzes `FILE` and prints the inferred root type and the type of every
`let`-bound name of the root `let`, sorted by name:

```text
root: String
greeting :: String
```

A declaration-only file (`.d.tynix`) prints nothing when it checks. A failing
check prints the diagnostic to standard error and exits `1`:

```text
3:14: [TC0013] type mismatch: 42 vs String
```

## `tynix compile`

```text
tynix compile FILE [-o|--output OUTPUT] [--no-check]
```

Checks `FILE`, erases all type syntax and prints the resulting Nix, or writes
it to `OUTPUT` (parent directories are created; the write is atomic). Fails
without output if the file does not check. `--no-check` skips type checking
and only erases, like TypeScript's transpile-only mode: parse errors still
fail, type errors do not. A declaration-only file cannot be compiled.

## `tynix emit`

```text
tynix emit FILE [-o|--output OUTPUT]
```

Checks `FILE` and prints a declaration file describing it, or writes it to
`OUTPUT`. The `declare` target is `FILE` with a `.nix` extension, relative to
the declaration's location. Fails with `TD0008` for a declaration-only file.
See [declaration emit](./type-system-internals.md#erasure-and-compilation) for
how members are chosen.

## `tynix init`

```text
tynix init [DIRECTORY] [--editor EDITOR]...
```

Creates `DIRECTORY` if needed and writes a default `tynix.config.tynix`, then
runs [`scaffold`](#tynix-scaffold). Fails if `tynix.config.tynix` already exists.
The project name defaults to the directory name. Each `--editor` (repeatable)
also runs [`tynix ide install EDITOR`](#tynix-ide) for the new project.

## `tynix scaffold`

```text
tynix scaffold [DIRECTORY]
```

Reads `DIRECTORY/tynix.config.tynix` and creates whichever of these files are
missing, never overwriting existing ones:

- `tynix.config.d.tynix`: types for the config file,
- the `entry` file (by default `src/main.tynix`),
- `declarationDir/builtins.d.tynix` when `builtins = true`.

`builtins` is already typed by the prelude built into the binary. A scaffolded
`builtins.d.tynix` replaces that prelude with its short starter list, so delete
it (and set `builtins = false`) unless you want to restrict the builtins.

## `tynix check-project`

```text
tynix check-project [DIRECTORY] [-f|--format text|json]
```

Loads `DIRECTORY/tynix.config.tynix`, discovers sources (see
[source discovery](./config.md#source-discovery)), and checks every one, sharing
one declaration cache. All files are checked even if some fail.

```text
checked project hello-tynix
root: /home/you/hello-tynix
- ok src/main.tynix
  root: String
  greeting :: String
```

Fails with `no project source files discovered` when discovery finds nothing,
and with `missing tynix.config.tynix in DIRECTORY` without a config.

## `tynix build`

```text
tynix build [DIRECTORY] [-f|--format text|json]
```

For every discovered source, compiles it to `buildDir/<relative>.nix` and
emits `generatedDeclarationDir/<relative>.d.tynix`, where `<relative>` is the
source's path relative to `sourceDir` (or to the project root for sources
outside `sourceDir`). If **any** source fails, nothing is written.

## `tynix emit-project`

```text
tynix emit-project [DIRECTORY] [-f|--format text|json]
```

Like `build`, but writes only the declaration files.

## `tynix version`

```text
tynix version [-f|--format text|json]
```

Prints `tynix <version>`. `tynix --version` prints the same text.

## `tynix lsp`

```text
tynix lsp [--log-file PATH]
```

Executes `tynix-lsp --stdio`, which must be on `PATH`. Editors usually start
`tynix-lsp` directly; this subcommand exists so a single binary name can be
configured everywhere. `--log-file` is forwarded to the server.

## `tynix ide`

```text
tynix ide install vscode|cursor|vscodium|zed|neovim|helix
                 [--project DIR | -g|--global] [-n|--dry-run]
                 [--no-extension] [--force] [--lsp-path PATH]
tynix ide list
```

`tynix ide install EDITOR` installs the tynix extension (where the editor has
one) and merges the editor configuration that starts `tynix-lsp`: project
settings under the current directory (or `--project DIR`) by default, user
settings with `--global`. Settings are merged, never clobbered, and re-running
the command is a no-op. `--dry-run` prints the planned commands and a diff
without changing anything, `--no-extension` only writes configuration,
`--force` rewrites files that cannot be merged safely after saving a `.bak`
copy, and `--lsp-path` pins a `tynix-lsp` path (`""` pins nothing).

`tynix ide list` prints the supported editors and whether each one is detected.

[Editor setup](../editors.md) documents what each editor gets.

## `tynix doctor`

```text
tynix doctor [-f|--format text|json]
```

Checks that `tynix` and `tynix-lsp` are on `PATH` and report the same version,
that the current project's `tynix.config.tynix` loads, that each detected editor
has the tynix integration, and that `nix` is available. Each check prints one
line, with a suggested fix for each problem. Exits `1` if any check fails;
warnings do not change the exit status. See
[editor setup](../editors.md#tynix-doctor) for the list of checks and the JSON
report.

## JSON output

`--format json` is accepted by `check`, `check-project`, `build`,
`emit-project`, `version` and `doctor`. Every report is one JSON object on one line with
`schemaVersion` (currently `1`), `action`, and `success` or a `summary`.
Rendered types are strings in tynix syntax and may contain newlines.

`check`:

```json
{
  "schemaVersion": 1,
  "action": "check",
  "file": "hello.tynix",
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
  "projectName": "hello-tynix",
  "projectRoot": "/home/you/hello-tynix",
  "summary": { "total": 1, "ok": 1, "failed": 0 },
  "files": [
    {
      "source": "/home/you/hello-tynix/src/main.tynix",
      "relative": "main.tynix",
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
