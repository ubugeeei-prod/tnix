# Check your setup

Run **tynix: Run Doctor** from the Command Palette. It runs `tynix doctor` in
your workspace and prints a report in the _tynix doctor_ output channel: the
toolchain versions, the project configuration it found, and anything that
needs attention.

Other useful commands:

- **tynix: Show Version** — server and CLI versions
- **tynix: Restart Language Server** — after upgrading `tynix-lsp`
- **tynix: Show Output** — the language server log (set
  **tynix.trace.server** to `verbose` to include the JSON-RPC traffic)

The status bar item (`tynix`) shows whether the server is running; click it for
a quick menu.
