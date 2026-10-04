# tnix — TypeScript for Nix

Gradual static types for Nix. `tnix` checks `.tnix` files (Nix plus type
annotations), `.d.tnix` declaration files, and plain `.nix` files, powered by
the `tnix-lsp` language server.

```tnix
type User = { name :: String; age :: Int; };

let
  greet :: User -> String;
  greet = user: "hello ${user.name}";
in greet { name = "alice"; age = 30; }
```

<!-- Screenshot placeholder: images/screenshots/hover.png — hover showing an inferred type -->
<!-- Screenshot placeholder: images/screenshots/diagnostics.png — a type error with quick fix -->
<!-- Screenshot placeholder: images/screenshots/highlighting.png — tnix syntax highlighting in a dark theme -->

## Features

- **Syntax highlighting** for the full Nix language — strings with `${}`
  interpolation, indented strings and their `''$` / `'''` / `''\` escapes,
  paths (`./x`, `~/x`, `<nixpkgs>`, `./a/${b}`), URIs, lambda formals
  (`{ a, b ? 1, ... }@args:`), `inherit`, `rec`, `with`, `assert`, operators
  (`//`, `++`, `->`, `|>`, `?`, `or`) and builtins — plus every tnix addition:
  `type` aliases, `declare` blocks, `name :: Type;` signatures, typed binders
  `(x :: Type):`, `expr as Type` casts, and the type language (`forall`, `->`,
  `%1 ->`, unions, record types, literal types, `extends ? :`, `infer`,
  `any` / `unknown` / `dynamic`, `List` / `Vec` / `Tuple` / `Range` / `Unit`).
- **Semantic highlighting** from `tnix-lsp` layered on top of the grammar.
- **Diagnostics** for parse and type errors, including
  `# @tnix-ignore` / `# @tnix-expected` directives (highlighted too).
- **Hover**, **completion**, **signature help**, **go to definition**,
  **references**, **rename**, **document symbols**, **inlay hints**,
  **code actions**, **formatting** and **folding**.
- `tnix` code blocks in Markdown are highlighted.
- Snippets for `type`, `declare`, signatures, typed lambdas, flakes and more.
- A **Get started with tnix** walkthrough (Help → Welcome).

## Requirements

Install the toolchain (`tnix` and `tnix-lsp`):

```sh
curl -fsSL https://tnix.dev/install.sh | sh
```

or with Nix:

```sh
nix profile install github:ubugeeei/tnix#tnix github:ubugeeei/tnix#tnix-lsp
```

If `tnix-lsp` cannot be found, the extension offers to run one of these for
you. It searches `tnix.server.path`, then common Nix profiles
(`~/.nix-profile/bin`, `~/.local/state/nix/profiles/…`,
`/run/current-system/sw/bin`), then `PATH`.

## Commands

| Command                         | Description                                |
| ------------------------------- | ------------------------------------------ |
| `tnix: Restart Language Server` | Restart `tnix-lsp` (e.g. after upgrading)  |
| `tnix: Show Output`             | Open the language server log               |
| `tnix: Show Version`            | Show the server, CLI and extension version |
| `tnix: Run Doctor`              | Run `tnix doctor` in the workspace         |
| `tnix: Install tnix Toolchain`  | Install via the script or Nix              |

The `tnix` status bar item shows the server state and version; click it for
the same actions.

## Settings

| Setting                              | Default | Description                                                        |
| ------------------------------------ | ------- | ------------------------------------------------------------------ |
| `tnix.server.path`                   | `""`    | `tnix-lsp` executable; blank = auto-detect                         |
| `tnix.server.args`                   | `[]`    | Extra server arguments                                             |
| `tnix.server.cwd`                    | `""`    | Server working directory; blank = first workspace folder           |
| `tnix.server.promptInstall`          | `true`  | Offer installation when `tnix-lsp` is missing                      |
| `tnix.cli.path`                      | `""`    | `tnix` CLI used by Doctor / Show Version; blank = auto-detect      |
| `tnix.trace.server`                  | `off`   | `messages` / `verbose` logs JSON-RPC traffic to the output channel |
| `tnix.inlayHints.enabled`            | `true`  | Show inlay hints                                                   |
| `tnix.inlayHints.typeHints`          | `true`  | Inferred-type hints                                                |
| `tnix.inlayHints.parameterHints`     | `true`  | Parameter hints                                                    |
| `tnix.diagnostics.enabled`           | `true`  | Show tnix diagnostics                                              |
| `tnix.diagnostics.severityOverrides` | `{}`    | Per-code severity, e.g. `{ "TNIX-T0001": "warning" }` or `"off"`   |

All `tnix.*` settings are also sent to the server as `initializationOptions`
and through `workspace/didChangeConfiguration`. Inlay-hint toggles and severity
overrides are additionally enforced by the client, so they work with any
server version.

In untrusted workspaces, workspace-level `tnix.server.*` and `tnix.cli.path`
values are ignored.

## Troubleshooting

- Run **tnix: Run Doctor** and **tnix: Show Version**.
- Confirm `tnix-lsp --version` works in the shell VS Code inherits; set
  `tnix.server.path` if the binary lives elsewhere.
- Set `tnix.trace.server` to `verbose` and check **tnix: Show Output**.
- `.nix` files are opened as `tnix` so the server can check them. If another
  Nix extension should own `.nix`, add
  `"files.associations": { "*.nix": "nix" }` — `tnix-lsp` still attaches to
  the `nix` language id.

## Development

```sh
pnpm --filter tnix check   # grammar in sync + type-check
pnpm --filter tnix test    # unit + grammar snapshot tests
pnpm --filter tnix run build:grammar          # regenerate syntaxes/*.json
pnpm --filter tnix run test:update-snapshots  # accept grammar changes
pnpm --filter tnix run test:integration       # VS Code integration tests
```

The TextMate grammar is generated from `scripts/build-grammar.mjs`; edit that
file, not the JSON. Snapshot fixtures live in `test/grammar/`.
