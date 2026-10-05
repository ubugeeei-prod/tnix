# Troubleshooting

Common problems and how to resolve them. If none of these match, open an issue
with a minimal reproduction (see [CONTRIBUTING.md](https://github.com/ubugeeei-prod/tnix/blob/main/CONTRIBUTING.md)).

## The CLI

### `tnix: command not found`

The binary is not on your `PATH`. The installer script puts it in
`~/.tnix/bin` and prints the line to add to your shell profile. Otherwise
install it from the flake (`nix profile install github:ubugeeei-prod/tnix`) or,
when working from a checkout, run it through Cabal inside the dev shell:

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

The parser accepts the whole Nix expression language, so a parse error usually
points at a real syntax error. The known exception is unquoted URIs
(`https://...`), which are only recognized in argument position; quote them.

More often, `tnix compile` refuses a file because it does not type-check:
compile checks first and never writes output for an ill-typed file. Fix the
reported diagnostic, suppress it with `# @tnix-ignore`, or annotate the
offending boundary with `dynamic`. For existing `.nix` modules that you do not
want to convert, *ambient typing* with a `.d.tnix` file is usually the better
route; see [migration.md](./migration.md).

### `missing field` on `builtins`

`builtins` and the global builtins are typed by a prelude built into `tnix`.
If a builtin that exists in Nix is reported as a missing field, the workspace
probably contains its own `declare "builtins"` block, which replaces the
prelude. `tnix init` scaffolds one at `types/builtins.d.tnix` when
`builtins = true`. Delete that file (and set `builtins = false;` in
`tnix.config.tnix`) to use the full prelude again.

### Declarations are not picked up

`.d.tnix` files are discovered under the *workspace root*, the nearest
directory containing `.git`, `flake.nix`, `tnix.config.tnix`, `cabal.project`
or `pnpm-workspace.yaml`. Without such a marker, only declaration files next to
the checked file are loaded. Nested workspaces, hidden directories,
`node_modules`, `dist-newstyle`, `result*` links and symlinked directories are
skipped. Move the file under the root, or list it in `declarationPacks`.

## Diagnostics

Every diagnostic has a stable code such as `[TC0013]`, usually preceded by the
`line:col` of the offending expression. Look the code up in
[diagnostics.md](./diagnostics.md) for an explanation and a suggested fix. The
prefix tells you the phase: `TP` parser, `TK` kind checker, `TC` type checker,
`TD` driver/project/IO, and `TL` for lints that only the language server
reports.

### Silencing a known diagnostic

Use the directive comments documented in
[getting-started.md](./getting-started.md#diagnostic-directives):
`# @tnix-ignore` to suppress the error of the next `let` item or root
expression, and `# @tnix-expected` to assert that an error must occur there.

## The language server (`tnix-lsp`)

### The server doesn't start in my editor

Run `tnix doctor` first: it checks that `tnix` and `tnix-lsp` are on `PATH`
with matching versions and that each detected editor is set up, and prints the
command that fixes each problem (usually `tnix ide install <editor>`). If it
reports no problem:

1. Confirm the binary runs on its own: `tnix-lsp --version`.
2. Confirm your editor points at the right executable. VS Code uses the
   `tnix.server.path` setting; Neovim and Zed resolve the binary from `PATH`.
3. Check the editor's LSP/output log for the server's stderr.

### No diagnostics or hovers appear

Make sure the file is recognized as a tnix document. The VS Code extension
activates on `.tnix`/`.d.tnix` (and `.nix`); see the
[editor integrations](https://github.com/ubugeeei-prod/tnix/tree/main/editors) for how each editor associates files.

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
