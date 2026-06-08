import * as assert from "node:assert";
import * as vscode from "vscode";
import {
  STUB,
  activateExtension,
  execProvider,
  fixtureUri,
  openFixture,
} from "./helpers";

suite("editor features", () => {
  setup(async () => {
    await activateExtension();
    await openFixture("sample.tnix");
  });

  test("semantic tokens are provided", async () => {
    const tokens = await execProvider<vscode.SemanticTokens>(
      "vscode.provideDocumentSemanticTokens",
      fixtureUri("sample.tnix"),
    );
    assert.ok(tokens.data.length >= 5, "expected at least one 5-tuple token");
  });

  test("inlay hints are provided", async () => {
    const range = new vscode.Range(
      new vscode.Position(0, 0),
      new vscode.Position(3, 0),
    );
    const hints = await execProvider<vscode.InlayHint[]>(
      "vscode.executeInlayHintProvider",
      fixtureUri("sample.tnix"),
      range,
    );
    assert.ok(hints.length >= 1);
    const label =
      typeof hints[0].label === "string"
        ? hints[0].label
        : hints[0].label.map((part) => part.value).join("");
    assert.ok(label.includes(`${STUB}Int`), label);
  });

  test("document links are provided", async () => {
    const links = await execProvider<vscode.DocumentLink[]>(
      "vscode.executeLinkProvider",
      fixtureUri("sample.tnix"),
    );
    assert.ok(links.length >= 1);
    assert.ok(links[0].target?.toString().includes(STUB));
  });
});
