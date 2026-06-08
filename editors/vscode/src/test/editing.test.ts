import * as assert from "node:assert";
import * as vscode from "vscode";
import {
  STUB,
  activateExtension,
  execProvider,
  fixtureUri,
  openFixture,
  waitFor,
} from "./helpers";

suite("editing and sync", () => {
  setup(async () => {
    await activateExtension();
  });

  test("publishes diagnostics for multiple open documents", async () => {
    await openFixture("sample.tnix");
    await openFixture("library.nix");
    const tnixDiags = await waitFor(
      () => vscode.languages.getDiagnostics(fixtureUri("sample.tnix")),
      "sample.tnix diagnostics",
    );
    const nixDiags = await waitFor(
      () => vscode.languages.getDiagnostics(fixtureUri("library.nix")),
      "library.nix diagnostics",
    );
    assert.ok(tnixDiags.length >= 1);
    assert.ok(nixDiags.length >= 1);
  });

  test("re-publishes diagnostics after an incremental edit", async () => {
    const document = await openFixture("sample.tnix");
    await waitFor(
      () => vscode.languages.getDiagnostics(document.uri),
      "initial diagnostics",
    );

    const edit = new vscode.WorkspaceEdit();
    edit.insert(document.uri, new vscode.Position(0, 0), "# edited\n");
    assert.ok(await vscode.workspace.applyEdit(edit));

    const after = await waitFor(
      () => vscode.languages.getDiagnostics(document.uri),
      "diagnostics after edit",
    );
    assert.ok(after.length >= 1);
    assert.ok(after.some((diagnostic) => diagnostic.source === STUB));
  });

  test("offers completion when triggered by the '.' character", async () => {
    await openFixture("sample.tnix");
    const list = await execProvider<vscode.CompletionList>(
      "vscode.executeCompletionItemProvider",
      fixtureUri("sample.tnix"),
      new vscode.Position(3, 3),
      ".",
    );
    const labels = list.items.map((item) =>
      typeof item.label === "string" ? item.label : item.label.label,
    );
    assert.ok(labels.includes(`${STUB}Item`), labels.join(", "));
  });
});
