import assert from "node:assert/strict";
import test from "node:test";
import { defaultBinaryCandidates, resolveCliPath } from "./runtime.js";
import {
  VSCODE_SEVERITY,
  buildInitializationOptions,
  diagnosticCode,
  findExecutable,
  normalizeSeverityOverrides,
  overrideSeverity,
  parseVersion,
} from "./settings.js";

test("findExecutable searches PATH entries in order", () => {
  const existing = new Set(["/b/tnix-lsp", "/c/tnix-lsp"]);
  assert.equal(
    findExecutable("tnix-lsp", { PATH: "/a::/b:/c" }, "linux", (p) =>
      existing.has(p),
    ),
    "/b/tnix-lsp",
  );
  assert.equal(
    findExecutable("tnix-lsp", { PATH: "/a" }, "linux", (p) => existing.has(p)),
    undefined,
  );
});

test("findExecutable checks explicit paths directly", () => {
  assert.equal(
    findExecutable("/nix/store/x/bin/tnix-lsp", {}, "linux", () => true),
    "/nix/store/x/bin/tnix-lsp",
  );
  assert.equal(
    findExecutable(
      "./bin/tnix-lsp",
      { PATH: "/usr/bin" },
      "linux",
      () => false,
    ),
    undefined,
  );
  assert.equal(findExecutable("   ", { PATH: "/usr/bin" }), undefined);
});

test("findExecutable honours PATHEXT on Windows", () => {
  const found = findExecutable(
    "tnix-lsp",
    { PATH: "C:\\tools", PATHEXT: ".EXE;.CMD" },
    "win32",
    (p) => p.endsWith("tnix-lsp.CMD"),
  );
  assert.ok(found?.endsWith("tnix-lsp.CMD"));
});

test("normalizeSeverityOverrides upper-cases codes and drops invalid entries", () => {
  assert.deepEqual(
    normalizeSeverityOverrides({
      "tnix-t0001": "Warning",
      TNIX_X: "off",
      bad: "fatal",
      "": "error",
      num: 3,
    }),
    { "TNIX-T0001": "warning", TNIX_X: "off" },
  );
  assert.deepEqual(normalizeSeverityOverrides(null), {});
  assert.deepEqual(normalizeSeverityOverrides(["x"]), {});
});

test("diagnosticCode reads string, number, and { value } codes", () => {
  assert.equal(diagnosticCode("A1"), "A1");
  assert.equal(diagnosticCode(7), "7");
  assert.equal(diagnosticCode({ value: "B2", target: "x" }), "B2");
  assert.equal(diagnosticCode(undefined), undefined);
});

test("overrideSeverity remaps, silences, or keeps diagnostics", () => {
  const overrides = normalizeSeverityOverrides({
    "TNIX-T0001": "hint",
    TP0004: "off",
  });
  assert.equal(
    overrideSeverity("tnix-t0001", "msg", 0, overrides),
    VSCODE_SEVERITY.hint,
  );
  assert.equal(
    overrideSeverity({ value: "TP0004" }, "msg", 0, overrides),
    null,
  );
  assert.equal(
    overrideSeverity(undefined, "[TP0004] parse", 0, overrides),
    null,
  );
  assert.equal(overrideSeverity("OTHER1", "msg", 1, overrides), 1);
  assert.equal(overrideSeverity("TNIX-T0001", "msg", 0, {}), 0);
});

test("buildInitializationOptions mirrors the client settings", () => {
  assert.deepEqual(
    buildInitializationOptions({
      inlayHints: { enabled: false, typeHints: true, parameterHints: false },
      diagnostics: { enabled: true, severityOverrides: { A: "off" } },
    }),
    {
      inlayHints: { enabled: false, typeHints: true, parameterHints: false },
      diagnostics: { enabled: true, severityOverrides: { A: "off" } },
    },
  );
});

test("parseVersion extracts versions from --version output", () => {
  assert.equal(parseVersion("tnix-lsp 0.5.0\n"), "0.5.0");
  assert.equal(parseVersion("tnix 1.2.3-rc.1"), "1.2.3-rc.1");
  assert.equal(parseVersion("no version here"), undefined);
});

test("resolveCliPath prefers explicit paths, then Nix profiles, then PATH", () => {
  assert.equal(
    resolveCliPath(" /opt/tnix ", "/home/a", () => false),
    "/opt/tnix",
  );
  assert.equal(
    resolveCliPath("", "/home/a", (p) => p === "/home/a/.nix-profile/bin/tnix"),
    "/home/a/.nix-profile/bin/tnix",
  );
  assert.equal(
    resolveCliPath(undefined, "/home/a", () => false),
    "tnix",
  );
  assert.ok(
    defaultBinaryCandidates("tnix", "/home/a").every((c) =>
      c.endsWith("/tnix"),
    ),
  );
});
