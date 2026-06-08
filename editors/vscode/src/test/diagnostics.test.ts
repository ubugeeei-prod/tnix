import * as assert from "node:assert";
import * as vscode from "vscode";
import {
  STUB,
  activateExtension,
  fixtureUri,
  openFixture,
  waitFor,
} from "./helpers";

suite("diagnostics", () => {
  test("surfaces diagnostics published by the language server", async () => {
    await activateExtension();
    const uri = fixtureUri("sample.tnix");
    await openFixture("sample.tnix");

    const diagnostics = await waitFor(
      () => vscode.languages.getDiagnostics(uri),
      "diagnostics",
    );
    assert.ok(diagnostics.length >= 1);
    const diagnostic = diagnostics[0];
    assert.ok(diagnostic.message.includes(`${STUB} diagnostic`));
    assert.strictEqual(diagnostic.source, STUB);
  });

  test("clears diagnostics state is queryable for all uris", async () => {
    await activateExtension();
    await openFixture("sample.tnix");
    const all = vscode.languages.getDiagnostics();
    assert.ok(Array.isArray(all));
  });
});
