# Check your setup

Run **tnix: Run Doctor** from the Command Palette. It runs `tnix doctor` in
your workspace and prints a report in the _tnix doctor_ output channel: the
toolchain versions, the project configuration it found, and anything that
needs attention.

Other useful commands:

- **tnix: Show Version** — server and CLI versions
- **tnix: Restart Language Server** — after upgrading `tnix-lsp`
- **tnix: Show Output** — the language server log (set
  **tnix.trace.server** to `verbose` to include the JSON-RPC traffic)

The status bar item (`tnix`) shows whether the server is running; click it for
a quick menu.
