---
title: "10. Editor setup"
description: Connect VS Code, Zed or Neovim to the tnix language server, and diagnose the setup with tnix doctor.
---

# 10. Editor setup

Everything `tnix check` tells you, the language server tells you while you
type: diagnostics with their codes, hover types, inlay hints for inferred
bindings, completion after `.`, go to definition, find references, rename,
document symbols, folding and semantic highlighting.

The server is the `tnix-lsp` binary from step 1. Every editor integration
starts it over stdio; the integrations differ only in how they are installed.

## The quick way: `tnix ide install`

> [!NOTE]
> **Upcoming.** `tnix ide install` and `tnix doctor` are being added to the CLI
> for the next release. This section describes their intended behavior; until
> they ship, use the manual setup below.

`tnix ide install <editor>` sets up an editor in one command:

```bash
tnix ide install vscode
```

For VS Code it installs the tnix extension and points it at the `tnix-lsp` that
belongs to the same installation as the `tnix` you ran, so the CLI and the
editor always agree on the language version. The same command accepts the other
supported editors (`zed`, `neovim`); run `tnix ide --help` for the current list.

## Check the setup: `tnix doctor`

When something does not light up, run:

```bash
tnix doctor
```

`tnix doctor` inspects your environment and reports, check by check, whether
`tnix` and `tnix-lsp` are on `PATH`, whether their versions match, whether the
current directory has a workspace root and a readable `tnix.config.tnix`, and
whether the editor integrations it knows about are installed. Each failing
check comes with the command that fixes it. Include its output when you file a
bug.

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
2. delete the `version` line and watch the `TC0013` diagnostic appear;
3. type `pkgs.` inside `flake.tnix` to complete the attributes of `Pkgs`.

<div class="tx-pager">

[← 9. Flakes and packages](./flakes-and-packages.md) [11. Projects →](./projects.md)

</div>
