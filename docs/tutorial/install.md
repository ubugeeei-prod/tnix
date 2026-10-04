---
title: "1. Install"
description: Install the tnix CLI and the tnix-lsp language server with the installer script or Nix.
---

# 1. Install

tnix ships as two executables:

- `tnix`, the CLI that checks, compiles and emits declarations, and
- `tnix-lsp`, the language server your editor talks to.

Pick one of the installation methods below.

## Option A: the installer script

On Linux x64 and macOS arm64, the quickest route is the installer script. It
downloads the prebuilt release archive for your platform from GitHub Releases
and installs `tnix` and `tnix-lsp`:

```bash
curl -fsSL https://tnix.dev/install.sh | sh
```

> [!NOTE]
> Prefer to read a script before piping it to a shell? Download it first with
> `curl -fsSL https://tnix.dev/install.sh -o install.sh`, inspect it, then run
> `sh install.sh`. The [installation section of Getting Started](../getting-started.md#installation)
> documents the options the script accepts.

## Option B: Nix profile

On any host with flakes enabled, install straight from the flake:

```bash
nix profile install github:ubugeeei-prod/tnix
```

The default package is the `tnix` CLI. Add the language server as well (you
need it in step 10), or install both at once through the `tnix-toolchain`
package:

```bash
nix profile install github:ubugeeei-prod/tnix#tnix-lsp
# or, both binaries in one package:
nix profile install github:ubugeeei-prod/tnix#tnix-toolchain
```

To pin a release, add a tag to the flake reference, for example
`github:ubugeeei-prod/tnix/v0.5.0`.

## Option C: run without installing

`nix run` is handy for a one-off check or for CI:

```bash
nix run github:ubugeeei-prod/tnix -- --version
```

## Check the installation

```bash
tnix --version
```

```text
tnix 0.5.0.0
```

`tnix --help` lists every command. You will meet most of them in this tutorial;
the [CLI reference](../reference/cli.md) documents all of them.

> [!TIP]
> Platform support differs per tier. Linux x64 and macOS arm64 have prebuilt
> archives; Linux arm64 and macOS x64 build through the flake. See the
> [support matrix](../support-matrix.md) for details.

## Set up a playground

Create a directory for the tutorial and make it a Git repository:

```bash
mkdir tnix-tour && cd tnix-tour
git init
```

The `git init` matters. tnix treats the nearest directory that contains `.git`,
`flake.nix`, `tnix.config.tnix`, `cabal.project` or `pnpm-workspace.yaml` as the
*workspace root*, and it discovers `.d.tnix` declaration files anywhere under
that root. You will rely on that in step 6.

<div class="tx-pager">

[← Tutorial overview](./index.md) [2. Your first file →](./first-file.md)

</div>
