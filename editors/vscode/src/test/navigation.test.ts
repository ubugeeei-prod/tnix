import * as assert from "node:assert";
import * as vscode from "vscode";
import {
  activateExtension,
  execProvider,
  fixtureUri,
  openFixture,
} from "./helpers";

const position = new vscode.Position(3, 3);

function asLocations(
  result: Array<vscode.Location | vscode.LocationLink>,
): vscode.Location[] {
  return result.map((entry) =>
    entry instanceof vscode.Location
      ? entry
      : new vscode.Location(entry.targetUri, entry.targetRange),
  );
}

suite("navigation", () => {
  setup(async () => {
    await activateExtension();
    await openFixture("sample.tnix");
  });

  test("go to definition resolves a location", async () => {
    const result = await execProvider<
      Array<vscode.Location | vscode.LocationLink>
    >("vscode.executeDefinitionProvider", fixtureUri("sample.tnix"), position);
    assert.ok(asLocations(result).length >= 1);
  });

  test("go to declaration resolves a location", async () => {
    const result = await execProvider<
      Array<vscode.Location | vscode.LocationLink>
    >("vscode.executeDeclarationProvider", fixtureUri("sample.tnix"), position);
    assert.ok(asLocations(result).length >= 1);
  });

  test("find references resolves locations", async () => {
    const result = await execProvider<vscode.Location[]>(
      "vscode.executeReferenceProvider",
      fixtureUri("sample.tnix"),
      position,
    );
    assert.ok(result.length >= 1);
    assert.ok(result[0] instanceof vscode.Location);
  });

  test("document highlights resolve ranges", async () => {
    const result = await execProvider<vscode.DocumentHighlight[]>(
      "vscode.executeDocumentHighlights",
      fixtureUri("sample.tnix"),
      position,
    );
    assert.ok(result.length >= 1);
  });
});
