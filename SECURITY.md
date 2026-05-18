# Security Policy

## Supported Versions

Security fixes target the latest released version of `tnix`. Older releases may
receive fixes when a safe patch is straightforward, but users should plan to
upgrade to the latest release.

## Reporting a Vulnerability

Please do not publish exploit details in a public issue.

Preferred reporting path:

1. Use GitHub private vulnerability reporting or create a draft security
   advisory for this repository when available.
2. If private reporting is not available, open a minimal public issue asking for
   a private coordination channel. Do not include reproduction details, payloads,
   or sensitive logs in that issue.

Include the affected version, operating system, installation method, and the
smallest safe reproduction you can share privately.

## Scope

The highest-priority reports are vulnerabilities that affect:

- `tnix` CLI compilation or project build output paths.
- `tnix-lsp` behavior when handling untrusted workspace files.
- Release artifacts, checksums, or editor extension packaging.
- Generated files that could overwrite data outside configured project roots.

Type-checking mistakes without a security boundary are still important bugs, but
they should usually be reported as ordinary issues.

## Disclosure

The project aims to acknowledge security reports within seven days. Once a fix
is available, the release notes should identify the affected surface and upgrade
path without exposing unnecessary exploit detail.
