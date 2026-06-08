import * as assert from "node:assert";
import * as vscode from "vscode";
import {
  STUB,
  activateExtension,
  execProvider,
  fixtureUri,
  openFixture,
} from "./helpers";

const position = new vscode.Position(3, 3);

suite("refactor and symbols", () => {
  setup(async () => {
    await activateExtension();
    await openFixture("sample.tnix");
  });

  test("rename returns a workspace edit", async () => {
    const edit = await execProvider<vscode.WorkspaceEdit>(
      "vscode.executeDocumentRenameProvider",
      fixtureUri("sample.tnix"),
      position,
      "renamed",
    );
    assert.ok(edit instanceof vscode.WorkspaceEdit);
    const edits = edit.get(fixtureUri("sample.tnix"));
    assert.ok(edits.length >= 1);
    assert.ok(edits[0].newText.includes(`${STUB}Renamed`));
  });

  test("document symbols are returned", async () => {
    const symbols = await execProvider<
      Array<vscode.SymbolInformation | vscode.DocumentSymbol>
    >("vscode.executeDocumentSymbolProvider", fixtureUri("sample.tnix"));
    assert.ok(symbols.length >= 1);
    assert.ok(symbols.some((symbol) => symbol.name.includes(`${STUB}Symbol`)));
  });

  test("workspace symbols are returned", async () => {
    const symbols = await execProvider<vscode.SymbolInformation[]>(
      "vscode.executeWorkspaceSymbolProvider",
      STUB,
    );
    assert.ok(symbols.length >= 1);
  });

  test("code actions are returned", async () => {
    const range = new vscode.Range(position, position);
    const actions = await execProvider<vscode.CodeAction[]>(
      "vscode.executeCodeActionProvider",
      fixtureUri("sample.tnix"),
      range,
    );
    assert.ok(actions.length >= 1);
  });
});
