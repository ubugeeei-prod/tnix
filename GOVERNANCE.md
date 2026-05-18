# Project Governance

This document describes how decisions are made in the `tnix` project. It is
deliberately lightweight to match the project's current size; expect it to grow
as the contributor base and surface area expand.

## Roles

### Maintainers

Maintainers have write access to the repository, can merge pull requests, and
cut releases. They are accountable for the long-term direction of the codebase
and for keeping the contribution experience friendly and predictable.

Current maintainers:

- [@ubugeeei](https://github.com/ubugeeei) — project lead

Reviewer routing for individual paths is configured in
[`.github/CODEOWNERS`](.github/CODEOWNERS).

### Contributors

Anyone who opens a meaningful pull request or files a substantive issue is a
contributor. There is no application process — open an issue or a PR and you
are in.

## Decision Making

Day-to-day decisions are made by lazy consensus on the relevant issue or pull
request:

1. A maintainer or contributor proposes a change in writing (issue, PR, or
   short design note in `docs/`).
2. Anyone may object within a reasonable window (typically 72 hours for
   non-urgent work).
3. If no objection surfaces, the proposal is considered accepted and a
   maintainer merges it.
4. If discussion is needed and consensus cannot be reached, the project lead
   makes the final call. The reasoning is recorded in the originating
   issue/PR.

Trivial changes (typo fixes, dependency bumps, formatting) do not require any
sign-off beyond CI passing.

## Proposing Larger Changes

For work that affects the language surface, the public CLI/LSP interface, or
the release process:

1. Open an issue tagged with the relevant area first. Describe the problem,
   the proposed direction, and any alternatives considered.
2. Wait for at least one maintainer to acknowledge before opening a PR.
3. If the change is large, prefer a short design note under `docs/` (similar
   in shape to `docs/architecture.md`) so the discussion has a stable
   reference.

Smaller, self-contained PRs (bug fixes, refactors, new test coverage) do not
need this dance — just open the PR.

## Releases

Releases follow [Semantic Versioning](https://semver.org/):

- **Patch** (`0.x.y`): bug fixes, internal refactors, documentation updates
  that do not alter user-visible behaviour.
- **Minor** (`0.x.0`): new features that are backwards compatible (additional
  CLI commands, opt-in language features, additional LSP methods).
- **Major** (`x.0.0`): breaking changes to the surface language, ambient
  declaration format, CLI flag/exit-code contracts, or LSP message shapes.

Only maintainers cut releases. The full release procedure lives in
[`RELEASING.md`](RELEASING.md). Releases are announced on the GitHub Releases
page; no separate mailing list or chat channel is in scope today.

## Changing This Document

Updates to this document follow the same lazy-consensus path as any other
change. Open a PR, request review from a maintainer, and merge once there are
no outstanding objections.
