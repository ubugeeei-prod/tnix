---
title: "10. Editor setup"
description: Connect VS Code, Zed or Neovim to the tnix language server, and diagnose the setup with tnix doctor.
---

# 10. Editor setup

Everything `tnix check` tells you, the language server tells you while you
type: diagnostics with their codes, underlined at the exact span the checker
reports, hover types, inlay hints for inferred bindings, scope- and type-aware
completion, go to definition, find references, rename, document symbols,
folding and semantic highlighting. It also adds two lints of its own: unused
bindings (`TL0001`, shown faded) and uses of declarations documented as
`@deprecated` (`TL0002`, shown struck through). See
[diagnostics](../diagnostics.md#language-server-lints-tlxxxx).

The server is the `tnix-lsp` binary from step 1. Every editor integration
starts it over stdio; the integrations differ only in how they are installed.

## The quick way: `tnix ide install`

`tnix ide install <editor>` sets up an editor in one command:

```bash
tnix ide install vscode     # or: cursor, vscodium, zed, neovim, helix
```

For VS Code it installs the tnix extension, writes `.vscode/settings.json` with
the path of the `tnix-lsp` it found, and recommends the extension in
`.vscode/extensions.json`. Every editor gets the equivalent: Zed's
`auto_install_extensions`, a generated Lua file for Neovim, `languages.toml`
entries for Helix. Settings are merged into existing files, never clobbered,
and running the command again is a no-op. Add `--dry-run` to preview the
changes and `--global` to write user-level settings instead of project
settings. `tnix ide list` shows which supported editors are detected on your
machine. [Editor setup](../editors.md) documents every flag.

## Check the setup: `tnix doctor`

When something does not light up, run:

```bash
tnix doctor
```

`tnix doctor` reports, check by check, whether `tnix` and `tnix-lsp` are on
`PATH` and report the same version, whether the current project's
`tnix.config.tnix` loads, whether each detected editor has the tnix
integration, and whether `nix` is available. Each problem comes with the
command that fixes it, for example `run tnix ide install vscode`. It exits with
status `1` only when a check fails; warnings do not change the exit status.
Include its output (or `tnix doctor --format json`) when you file a bug.

## Manual setup

### VS Code

Install the **tnix** extension (publisher `ubugeeei`). From a checkout of the
repository you can also build and install it locally with `vp run ide`, which
installs the CLI, the language server and the extension together.

The extension looks for `tnix-lsp` in common Nix profile locations, then on
`PATH`. Override that in `settings.json` if needed:

```json
{
  "tnix.server.path": "/run/current-system/sw/bin/tnix-lsp",
  "tnix.trace.server": "messages"
}
```

`tnix.trace.server` logs the protocol traffic to the **tnix** output channel.

### Zed

The Zed extension lives in
[`editors/zed`](https://github.com/ubugeeei-prod/tnix/tree/main/editors/zed). Run
**zed: install dev extension** from the command palette and select that
directory. Zed launches `tnix-lsp` from your `PATH`.

### Neovim

The Neovim plugin lives in
[`editors/neovim`](https://github.com/ubugeeei-prod/tnix/tree/main/editors/neovim)
and needs Neovim 0.10 or newer. With lazy.nvim:

```lua
{
  "ubugeeei-prod/tnix",
  config = function()
    require("tnix").setup()
  end,
}
```

The plugin starts `tnix-lsp` for `.tnix`, `.d.tnix`, and by default also `.nix`
buffers, rooted at the nearest workspace marker.

### Any other LSP client

Start `tnix-lsp --stdio` (or `tnix lsp`, which forwards to it) for the
`tnix` language and use the directory that contains `.git`, `flake.nix` or
`tnix.config.tnix` as the root. `tnix lsp --log-file /tmp/tnix-lsp.log` writes a
server log that is useful when debugging a client.

## Try it

Open `package.tnix` from step 9 and:

1. hover `mkDerivation` to see `MkDerivationArgs -> Derivation`;
2. delete the `version` line and watch the `TC0009` diagnostic appear on the
   `mkDerivation` argument;
3. type `pkgs.` inside `flake.tnix` to complete the attributes of `Pkgs`.

<div class="tx-pager">

[← 9. Flakes and packages](./flakes-and-packages.md) [11. Projects →](./projects.md)

</div>
