import assert from "node:assert/strict";
import test from "node:test";
import {
  defaultServerPathCandidates,
  normalizeServerArgs,
  normalizeServerPath,
  resolveDefaultServerPath,
  resolveRuntimeConfig,
  resolveInstalledServerPath,
  resolveServerCwd,
  resolveWorkspaceCwd,
} from "./runtime.js";

test("normalizeServerPath falls back to the resolved server command for missing or blank values", () => {
  const resolveDefault = () => "/resolved/tynix-lsp";
  assert.equal(
    normalizeServerPath(undefined, resolveDefault),
    "/resolved/tynix-lsp",
  );
  assert.equal(normalizeServerPath("", resolveDefault), "/resolved/tynix-lsp");
  assert.equal(
    normalizeServerPath("   ", resolveDefault),
    "/resolved/tynix-lsp",
  );
});

test("normalizeServerPath preserves explicit executable paths", () => {
  const unreachable = () => {
    throw new Error("should not resolve a fallback for explicit paths");
  };
  assert.equal(
    normalizeServerPath("/nix/store/bin/tynix-lsp", unreachable),
    "/nix/store/bin/tynix-lsp",
  );
  assert.equal(
    normalizeServerPath(" tynix-lsp-dev ", unreachable),
    "tynix-lsp-dev",
  );
});

test("defaultServerPathCandidates prioritize common Nix profile locations", () => {
  assert.deepEqual(defaultServerPathCandidates("/home/alice"), [
    "/home/alice/.nix-profile/bin/tynix-lsp",
    "/home/alice/.local/state/nix/profiles/profile/bin/tynix-lsp",
    "/home/alice/.local/state/nix/profiles/home-manager/home-path/bin/tynix-lsp",
    "/run/current-system/sw/bin/tynix-lsp",
  ]);
});

test("resolveInstalledServerPath returns the first existing Nix profile binary", () => {
  assert.equal(
    resolveInstalledServerPath(
      "/home/alice",
      (path) =>
        path === "/home/alice/.local/state/nix/profiles/profile/bin/tynix-lsp",
    ),
    "/home/alice/.local/state/nix/profiles/profile/bin/tynix-lsp",
  );
  assert.equal(
    resolveInstalledServerPath("/home/alice", () => false),
    undefined,
  );
});

test("resolveDefaultServerPath falls back to tynix-lsp when no profile binary exists", () => {
  assert.equal(
    resolveDefaultServerPath("/home/alice", () => false),
    "tynix-lsp",
  );
});

test("normalizeServerArgs trims and drops blank argv entries", () => {
  assert.deepEqual(normalizeServerArgs(undefined), []);
  assert.deepEqual(normalizeServerArgs(["", " --stdio ", "  "]), ["--stdio"]);
  assert.deepEqual(normalizeServerArgs(["--log-file", "/tmp/tynix.log"]), [
    "--log-file",
    "/tmp/tynix.log",
  ]);
});

test("resolveRuntimeConfig returns the expected selector and watcher glob", () => {
  assert.deepEqual(resolveRuntimeConfig("tynix-lsp"), {
    command: "tynix-lsp",
    args: [],
    cwd: undefined,
    documentSelector: [{ language: "tynix" }, { language: "nix" }],
    watchPattern: "**/*.{nix,tynix}",
  });
});

test("resolveRuntimeConfig honors args and cwd overrides", () => {
  assert.deepEqual(
    resolveRuntimeConfig("tynix-lsp-dev", [" --stdio ", ""], "/tmp/tynix", [
      "/workspace",
    ]),
    {
      command: "tynix-lsp-dev",
      args: ["--stdio"],
      cwd: "/tmp/tynix",
      documentSelector: [{ language: "tynix" }, { language: "nix" }],
      watchPattern: "**/*.{nix,tynix}",
    },
  );
});

test("resolveWorkspaceCwd chooses the first non-empty workspace path", () => {
  assert.equal(resolveWorkspaceCwd(undefined), undefined);
  assert.equal(
    resolveWorkspaceCwd(["", "  ", "/workspace/two"]),
    "/workspace/two",
  );
  assert.equal(
    resolveWorkspaceCwd(["/workspace/one", "/workspace/two"]),
    "/workspace/one",
  );
});

test("resolveServerCwd prefers explicit cwd over workspace discovery", () => {
  assert.equal(resolveServerCwd(undefined, ["/workspace"]), "/workspace");
  assert.equal(
    resolveServerCwd("  /custom/root  ", ["/workspace"]),
    "/custom/root",
  );
  assert.equal(resolveServerCwd("   ", ["/workspace"]), "/workspace");
});
