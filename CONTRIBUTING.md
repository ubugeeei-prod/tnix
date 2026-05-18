# Contributing

Thanks for helping make `tnix` sturdier. The project is still small, so the best
contributions are focused, reproducible, and easy to review.

## Development Environment

Use the Nix development shell before running workspace commands:

```bash
nix develop
pnpm install --frozen-lockfile
```

The shell provides GHC/Cabal, Node.js, pnpm, Rust/Cargo, Neovim, and the `vp`
task runner used by CI.

## Common Commands

```bash
vp run check
pnpm run check
nix flake check --accept-flake-config
```

For narrower loops:

```bash
vp run test:haskell
pnpm --filter tnix test
vp run test:zed
vp run check:neovim
```

## Pull Requests

- Use conventional commit-style titles when practical, such as `fix(cli): ...`
  or `docs(release): ...`.
- Keep PRs small enough that each one can be reviewed and reverted on its own.
- Link the issue being addressed with `Closes #123` when the PR fully resolves
  it.
- Include the most relevant local verification command in the PR body.

## Regression Tests

Bug fixes should include a regression test near the affected surface:

- Haskell parser/checker/compiler behavior lives under `packages/tnix-core/src`.
- CLI project behavior lives under `packages/tnix-cli/src/Cli.spec.hs`.
- LSP behavior lives under `packages/tnix-lsp/src`.
- VS Code runtime behavior lives under `editors/vscode/src`.
- Zed and Neovim integration checks live under `editors/zed` and
  `editors/neovim`.

When a test is not practical, explain the residual risk in the PR body.
