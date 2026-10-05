import * as assert from "node:assert";
import * as vscode from "vscode";
import {
  STUB,
  activateExtension,
  execProvider,
  fixtureUri,
  hoverText,
  openFixture,
} from "./helpers";

const position = new vscode.Position(3, 3);

suite("intellisense", () => {
  setup(async () => {
    await activateExtension();
    await openFixture("sample.tynix");
  });

  test("hover surfaces server-provided contents", async () => {
    const hovers = await execProvider<vscode.Hover[]>(
      "vscode.executeHoverProvider",
      fixtureUri("sample.tynix"),
      position,
    );
    const rendered = hoverText(hovers);
    assert.ok(rendered.includes(`${STUB}-hover`), rendered);
  });

  test("completion surfaces server-provided items", async () => {
    const list = await execProvider<vscode.CompletionList>(
      "vscode.executeCompletionItemProvider",
      fixtureUri("sample.tynix"),
      position,
    );
    const labels = list.items.map((item) =>
      typeof item.label === "string" ? item.label : item.label.label,
    );
    assert.ok(labels.includes(`${STUB}Item`), labels.join(", "));
    assert.ok(labels.includes(`${STUB}Builtin`), labels.join(", "));
  });

  test("signature help surfaces server-provided signatures", async () => {
    const help = await execProvider<vscode.SignatureHelp>(
      "vscode.executeSignatureHelpProvider",
      fixtureUri("sample.tynix"),
      position,
      "(",
    );
    assert.ok(help.signatures.length >= 1);
    assert.ok(help.signatures[0].label.includes(`${STUB}(a: Int)`));
  });
});
