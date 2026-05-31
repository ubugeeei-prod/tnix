# Documentation Site

The public documentation site is built from the Markdown files in `docs/` with
Ox Content and deployed as static output with Void.

## Local Build

```bash
vp run build#docs
```

The build writes static HTML to `dist/docs`.

## Deploy

```bash
vp run deploy#docs
```

The deploy task runs the docs build first, then calls:

```bash
void deploy --dir dist/docs
```

Use `VOID_TOKEN` or `void auth login` for credentials. Use `VOID_PROJECT` or a
linked Void project when the deploy target should be selected non-interactively.
