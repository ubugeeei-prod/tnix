# Troubleshooting

Common problems and how to resolve them. If none of these match, open an issue
with a minimal reproduction (see [CONTRIBUTING.md](../CONTRIBUTING.md)).

## The CLI

### `tnix: command not found`

The binary is not on your `PATH`. Either install it from the flake
(`nix profile install github:ubugeeei/tnix#tnix`) or, when working from a
checkout, run it through Cabal inside the dev shell:

```bash
nix develop --accept-flake-config --command cabal run tnix -- --version
```

### A type error exits non-zero in CI

`tnix check` / `check-project` exit non-zero when they find type errors. That is
intended — it is how the tool gates a build. Use `--format json` to get a stable
machine-readable report for CI logs:

```bash
tnix check-project ./. --format json
```

### "no project source files discovered"

`check-project`, `build`, and `emit-project` walk the project from
`tnix.config.tnix`. If they find nothing, confirm that `sourceDir`/`entries`
point at directories that actually contain `.tnix` files and that `exclude`
isn't filtering everything out.

### A `.nix` file won't compile with `tnix compile`

Executable `.tnix` targets a reliable Nix-like subset, not full parser parity.
Constructs outside that subset are reported as parse errors. See the
"not yet supported" notes in [grammar.md](./grammar.md) and the parity statement
in the [README](../README.md). For existing `.nix` modules you usually want
*ambient typing* with a `.d.tnix` file rather than compiling them — see
[migration.md](./migration.md).

## Diagnostics

Every diagnostic has a stable code such as `[TC0013]`. Look the code up in
[diagnostics.md](./diagnostics.md) for an explanation and a suggested fix. The
prefix tells you the phase: `TP` parser, `TK` kind checker, `TC` type checker,
`TD` driver/project/IO.

### Silencing a known diagnostic

Use the directive comments documented in
[getting-started.md](./getting-started.md#diagnostic-directives):
`# @tnix-ignore` to suppress the next root expression's error, and
`# @tnix-expected` to assert that a specific error must occur.

## The language server (`tnix-lsp`)

### The server doesn't start in my editor

1. Confirm the binary runs on its own: `tnix-lsp --version`.
2. Confirm your editor points at the right executable. VS Code uses the
   `tnix.server.path` setting; Neovim and Zed resolve the binary from `PATH`.
3. Check the editor's LSP/output log for the server's stderr.

### No diagnostics or hovers appear

Make sure the file is recognized as a tnix document. The VS Code extension
activates on `.tnix`/`.d.tnix` (and `.nix`); see the
[editor integrations](../editors) for how each editor associates files.

## The Nix dev shell

### `nix develop` fails or is slow the first time

The flake builds GHC, Cabal, Node, Rust, and Neovim into the shell, so the first
entry downloads a lot. Subsequent entries are cached. Ensure flakes are enabled
and pass `--accept-flake-config` so the project's binary caches are used:

```bash
nix develop --accept-flake-config
```

### `vp: command not found`

`vp` (the `vite-plus` task runner) is provided inside the dev shell. Run
workspace commands from within `nix develop`, not your host shell.
