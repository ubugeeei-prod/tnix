# Tune the editor

Useful settings (search for `tynix` in the Settings editor):

| Setting                               | What it does                                                            |
| ------------------------------------- | ----------------------------------------------------------------------- |
| `tynix.server.path`                   | Explicit `tynix-lsp` binary                                             |
| `tynix.inlayHints.enabled`            | Show inferred types inline                                              |
| `tynix.diagnostics.severityOverrides` | Re-map or silence diagnostic codes, e.g. `{ "TYNIX-T0001": "warning" }` |
| `tynix.trace.server`                  | Log JSON-RPC traffic                                                    |

Syntax highlighting works out of the box; when the server is running,
semantic highlighting from `tynix-lsp` refines it (types vs. functions vs.
variables).
