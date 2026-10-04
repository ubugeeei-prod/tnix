# Install the tnix toolchain

The extension talks to `tnix-lsp`, the tnix language server. Install it with
the official script:

```sh
curl -fsSL https://tnix.dev/install.sh | sh
```

or with Nix:

```sh
nix profile install github:ubugeeei/tnix#tnix github:ubugeeei/tnix#tnix-lsp
```

The extension looks for `tnix-lsp` on your `PATH` and in the usual Nix profile
locations (`~/.nix-profile/bin`, `/run/current-system/sw/bin`, ...). If you
keep it somewhere else, set **tnix.server.path**.
