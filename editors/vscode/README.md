# tynix — TypeScript for Nix

Gradual static types for Nix. `tynix` checks `.tynix` files (Nix plus type
annotations), `.d.tynix` declaration files, and plain `.nix` files, powered by
the `tynix-lsp` language server.

```tynix
type User = { name :: String; age :: Int; };

let
  greet :: User -> String;
  greet = user: "hello ${user.name}";
in greet { name = "alice"; age = 30; }
```

<!-- Screenshot placeholder: images/screenshots/hover.png — hover showing an inferred type -->
<!-- Screenshot placeholder: images/screenshots/diagnostics.png — a type error with quick fix -->
<!-- Screenshot placeholder: images/screenshots/highlighting.png — tynix syntax highlighting in a dark theme -->

## Features

- **Syntax highlighting** for the full Nix language — strings with `${}`
  interpolation, indented strings and their `''$` / `'''` / `''\` escapes,
  paths (`./x`, `~/x`, `<nixpkgs>`, `./a/${b}`), URIs, lambda formals
  (`{ a, b ? 1, ... }@args:`), `inherit`, `rec`, `with`, `assert`, operators
  (`//`, `++`, `->`, `|>`, `?`, `or`) and builtins — plus every tynix addition:
  `type` aliases, `declare` blocks, `name :: Type;` signatures, typed binders
  `(x :: Type):`, `expr as Type` casts, and the type language (`forall`, `->`,
  `%1 ->`, unions, record types, literal types, `extends ? :`, `infer`,
  `any` / `unknown` / `dynamic`, `List` / `Vec` / `Tuple` / `Range` / `Unit`).
- **Semantic highlighting** from `tynix-lsp` layered on top of the grammar.
- **Diagnostics** for parse and type errors, including
  `# @tynix-ignore` / `# @tynix-expected` directives (highlighted too).
- **Hover**, **completion**, **signature help**, **go to definition**,
  **references**, **rename**, **document symbols**, **inlay hints**,
  **code actions**, **formatting** and **folding**.
- `tynix` code blocks in Markdown are highlighted.
- Snippets for `type`, `declare`, signatures, typed lambdas, flakes and more.
- A **Get started with tynix** walkthrough (Help → Welcome).

## Requirements

Install the toolchain (`tynix` and `tynix-lsp`):

```sh
curl -fsSL https://tynix.dev/install.sh | sh
```

or with Nix:

```sh
nix profile install github:ubugeeei/tynix#tynix github:ubugeeei/tynix#tynix-lsp
```

If `tynix-lsp` cannot be found, the extension offers to run one of these for
you. It searches `tynix.server.path`, then common Nix profiles
(`~/.nix-profile/bin`, `~/.local/state/nix/profiles/…`,
`/run/current-system/sw/bin`), then `PATH`.

## Commands

| Command                          | Description                                |
| -------------------------------- | ------------------------------------------ |
| `tynix: Restart Language Server` | Restart `tynix-lsp` (e.g. after upgrading) |
| `tynix: Show Output`             | Open the language server log               |
| `tynix: Show Version`            | Show the server, CLI and extension version |
| `tynix: Run Doctor`              | Run `tynix doctor` in the workspace        |
| `tynix: Install tynix Toolchain` | Install via the script or Nix              |

The `tynix` status bar item shows the server state and version; click it for
the same actions.

## Settings

| Setting                               | Default | Description                                                        |
| ------------------------------------- | ------- | ------------------------------------------------------------------ |
| `tynix.server.path`                   | `""`    | `tynix-lsp` executable; blank = auto-detect                        |
| `tynix.server.args`                   | `[]`    | Extra server arguments                                             |
| `tynix.server.cwd`                    | `""`    | Server working directory; blank = first workspace folder           |
| `tynix.server.promptInstall`          | `true`  | Offer installation when `tynix-lsp` is missing                     |
| `tynix.cli.path`                      | `""`    | `tynix` CLI used by Doctor / Show Version; blank = auto-detect     |
| `tynix.trace.server`                  | `off`   | `messages` / `verbose` logs JSON-RPC traffic to the output channel |
| `tynix.inlayHints.enabled`            | `true`  | Show inlay hints                                                   |
| `tynix.inlayHints.typeHints`          | `true`  | Inferred-type hints                                                |
| `tynix.inlayHints.parameterHints`     | `true`  | Parameter hints                                                    |
| `tynix.diagnostics.enabled`           | `true`  | Show tynix diagnostics                                             |
| `tynix.diagnostics.severityOverrides` | `{}`    | Per-code severity, e.g. `{ "TYNIX-T0001": "warning" }` or `"off"`  |

All `tynix.*` settings are also sent to the server as `initializationOptions`
and through `workspace/didChangeConfiguration`. Inlay-hint toggles and severity
overrides are additionally enforced by the client, so they work with any
server version.

In untrusted workspaces, workspace-level `tynix.server.*` and `tynix.cli.path`
values are ignored.

## Troubleshooting

- Run **tynix: Run Doctor** and **tynix: Show Version**.
- Confirm `tynix-lsp --version` works in the shell VS Code inherits; set
  `tynix.server.path` if the binary lives elsewhere.
- Set `tynix.trace.server` to `verbose` and check **tynix: Show Output**.
- `.nix` files are opened as `tynix` so the server can check them. If another
  Nix extension should own `.nix`, add
  `"files.associations": { "*.nix": "nix" }` — `tynix-lsp` still attaches to
  the `nix` language id.

## Development

```sh
pnpm --filter tynix check   # grammar in sync + type-check
pnpm --filter tynix test    # unit + grammar snapshot tests
pnpm --filter tynix run build:grammar          # regenerate syntaxes/*.json
pnpm --filter tynix run test:update-snapshots  # accept grammar changes
pnpm --filter tynix run test:integration       # VS Code integration tests
```

The TextMate grammar is generated from `scripts/build-grammar.mjs`; edit that
file, not the JSON. Snapshot fixtures live in `test/grammar/`.
