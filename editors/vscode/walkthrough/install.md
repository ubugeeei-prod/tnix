# Install the tynix toolchain

The extension talks to `tynix-lsp`, the tynix language server. Install it with
the official script:

```sh
curl -fsSL https://tynix.dev/install.sh | sh
```

or with Nix:

```sh
nix profile install github:ubugeeei/tynix#tynix github:ubugeeei/tynix#tynix-lsp
```

The extension looks for `tynix-lsp` on your `PATH` and in the usual Nix profile
locations (`~/.nix-profile/bin`, `/run/current-system/sw/bin`, ...). If you
keep it somewhere else, set **tynix.server.path**.
