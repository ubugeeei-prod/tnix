# Tune the editor

Useful settings (search for `tnix` in the Settings editor):

| Setting                              | What it does                                                           |
| ------------------------------------ | ---------------------------------------------------------------------- |
| `tnix.server.path`                   | Explicit `tnix-lsp` binary                                             |
| `tnix.inlayHints.enabled`            | Show inferred types inline                                             |
| `tnix.diagnostics.severityOverrides` | Re-map or silence diagnostic codes, e.g. `{ "TNIX-T0001": "warning" }` |
| `tnix.trace.server`                  | Log JSON-RPC traffic                                                   |

Syntax highlighting works out of the box; when the server is running,
semantic highlighting from `tnix-lsp` refines it (types vs. functions vs.
variables).
