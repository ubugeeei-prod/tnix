# Editor Setup

`tnix ide install <editor>` installs the tnix editor integration and writes the
editor configuration in one step. `tnix doctor` then checks that the toolchain
and the editors are wired up.

Install `tnix` and `tnix-lsp` first, with the installer script or the flake
(its default package contains both binaries):

```bash
curl -fsSL https://tnix.dev/install.sh | sh
# or
nix profile install github:ubugeeei-prod/tnix
```

## Quick start

```bash
cd my-project
tnix ide install vscode     # or: cursor, vscodium, zed, neovim, helix
tnix doctor
```

New projects can do both at once:

```bash
tnix init my-project --editor vscode
```

## `tnix ide install`

```text
tnix ide install <vscode|cursor|vscodium|zed|neovim|helix>
                 [--project DIR | --global] [--dry-run] [--no-extension]
                 [--force] [--lsp-path PATH]
```

| Flag             | Effect                                                                                                    |
| ---------------- | --------------------------------------------------------------------------------------------------------- |
| `--project DIR`  | Write project-level settings under `DIR` (default: the current directory).                               |
| `--global`, `-g` | Write user-level settings instead.                                                                        |
| `--dry-run`, `-n`| Print the planned commands and a line diff of every file, without changing anything.                     |
| `--no-extension` | Only write configuration; do not run the editor CLI.                                                      |
| `--force`        | Rewrite files that cannot be merged safely (see below), keeping a `.bak` copy of the original first.     |
| `--lsp-path`     | The `tnix-lsp` path to pin in settings. By default it is found on `PATH` or in a Nix profile. `""` pins nothing. |

Without `--project` or `--global`, every editor uses project settings except
Neovim, which uses your user config.

The command is idempotent: running it again reports `already up to date`
for files that already contain the settings, and skips the extension install
when the extension is already present. It exits non-zero only if a step fails,
for example when the editor CLI cannot install the extension or a file cannot
be written.

### What each editor gets

| Editor   | Extension                                                                 | Project scope                                                  | `--global`                                         |
| -------- | ------------------------------------------------------------------------- | -------------------------------------------------------------- | -------------------------------------------------- |
| vscode   | `code --install-extension ubugeeei.tnix` (VS Code Marketplace)            | `.vscode/settings.json`, `.vscode/extensions.json`             | VS Code user `settings.json`                       |
| cursor   | `cursor --install-extension ubugeeei.tnix` (Open VSX)                     | same as vscode                                                 | Cursor user `settings.json`                        |
| vscodium | `codium --install-extension ubugeeei.tnix` (Open VSX)                     | same as vscode                                                 | VSCodium user `settings.json`                      |
| zed      | `auto_install_extensions` in the settings file                            | `.zed/settings.json`                                           | `~/.config/zed/settings.json`                      |
| neovim   | none, a generated Lua file                                                | `.nvim.lua` (needs `:set exrc`)                                | `~/.config/nvim/after/plugin/tnix.lua` (default)   |
| helix    | none, `languages.toml` entries                                            | `.helix/languages.toml`                                        | `~/.config/helix/languages.toml`                   |

User settings follow each editor's platform convention: `~/Library/Application
Support/<App>/User` on macOS, `$XDG_CONFIG_HOME/<App>/User` on Linux.
`$XDG_CONFIG_HOME` (default `~/.config`) is respected for Zed, Neovim, and
Helix.

**VS Code / Cursor / VSCodium** settings:

```json
{
  "tnix.server.path": "/home/me/.nix-profile/bin/tnix-lsp",
  "files.associations": {
    "*.tnix": "tnix",
    "*.d.tnix": "tnix"
  }
}
```

`tnix.server.path` is only written when `tnix-lsp` was found. It is a
machine-specific path. If you commit `.vscode/settings.json`, consider
`--lsp-path ""`: the extension then finds `tnix-lsp` itself, looking in the
common Nix profile locations and then on `PATH`. `.vscode/extensions.json` gets
`ubugeeei.tnix` added to `recommendations`, so collaborators are prompted to
install it.

If the editor CLI is not on `PATH`, the command prints where to install the
extension from by hand and still writes the settings. In VS Code you can add
the CLI with **Shell Command: Install 'code' command in PATH**.

**Zed** settings use the `tnix-lsp` language-server id from
`editors/zed/extension.toml`:

```json
{
  "auto_install_extensions": { "tnix": true },
  "lsp": { "tnix-lsp": { "binary": { "path": "/home/me/.nix-profile/bin/tnix-lsp" } } }
}
```

Until tnix is listed in the Zed extension registry, install the extension as a
dev extension: run **zed: install dev extension** and pick `editors/zed`, or
run `vp ide` from a tnix checkout.

**Neovim** gets a self-contained Lua file. It registers the `tnix` filetype for
`*.tnix` and `*.d.tnix`, then starts `tnix-lsp` in one of three ways, whichever
is available first:

1. `require("tnix").setup(...)` when the [editors/neovim](../editors/neovim/README.md)
   plugin is on the runtimepath;
2. `vim.lsp.config` and `vim.lsp.enable` (Neovim 0.11+);
3. a `FileType` autocmd that calls `vim.lsp.start` (Neovim 0.10).

The file starts with a `Managed by tnix ide install` header. Re-running the
command updates that file. If a file at that path does not have the header, it
is left alone unless you pass `--force`. Delete the header to take ownership of
the file.

**Helix** gets a `[[language]] name = "tnix"` entry, which reuses Helix's
built-in Nix grammar, and a `[language-server.tnix-lsp]` table. Either one is
only added if it is missing, so an existing definition is never edited. Check
the result with `hx --health tnix`.

### Comments and hand-written settings

VS Code and Zed settings files are JSONC, so they may contain comments and
trailing commas. `tnix ide install` reads them and merges keys while keeping
the existing order and indentation. Comments, however, cannot be preserved
through a rewrite. When a file has comments and needs changes, the command
leaves the file alone and prints the snippet to add by hand. `--force`
rewrites the file anyway, after saving the original as `settings.json.bak`.
A file that already contains the settings is never rewritten.

A file that cannot be parsed, or a value with an unexpected shape (for
example `"files.associations"` that is not an object), is also never
overwritten. The command prints the snippet to add by hand instead.

## `tnix ide list`

Lists the supported editors and whether each one is detected. An editor counts
as detected when its CLI (`code`, `cursor`, `codium`, `zed`, `nvim`, `hx`) is
on `PATH` or its configuration directory exists.

## `tnix doctor`

```bash
tnix doctor
tnix doctor --format json
```

| Check            | Fails when                                                    | Warns when                                         |
| ---------------- | ------------------------------------------------------------- | -------------------------------------------------- |
| `tnix`           | `tnix --version` fails                                        | `tnix` is not on `PATH`, or its version differs    |
| `tnix-lsp`       | not on `PATH`, `tnix-lsp --version` fails, or version differs | the version cannot be read                         |
| project          | `tnix.config.tnix` exists but does not load                   | no `tnix.config.tnix` in this or a parent directory |
| each detected editor | —                                                         | the extension or config is missing                 |
| `nix`            | —                                                             | `nix` is not on `PATH`                             |

What "set up" means for each editor: VS Code, Cursor, and VSCodium have
`ubugeeei.tnix` in `--list-extensions`. Zed has the extension installed. Neovim
has the generated `after/plugin/tnix.lua`. Helix's user `languages.toml`
defines the tnix language and server.

The command exits with status 1 if any check fails. Warnings do not change the
exit status. Text output is colored on a terminal; set `NO_COLOR` to turn
color off. The JSON report follows the other `--format json` payloads:

```json
{
  "schemaVersion": 1,
  "action": "doctor",
  "success": true,
  "checks": [
    { "id": "tnix-lsp.version", "status": "ok", "message": "…", "hint": null }
  ]
}
```

Check `status` is one of `ok`, `warn`, `fail`, or `skip`.

See [troubleshooting.md](./troubleshooting.md) for fixes to common problems.
