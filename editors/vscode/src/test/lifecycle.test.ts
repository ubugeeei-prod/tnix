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

suite("server lifecycle", () => {
  test("restarting the server keeps language features working", async () => {
    await activateExtension();
    await openFixture("sample.tnix");

    // Sanity: hover works before the restart.
    const before = await execProvider<vscode.Hover[]>(
      "vscode.executeHoverProvider",
      fixtureUri("sample.tnix"),
      position,
    );
    assert.ok(hoverText(before).includes(`${STUB}-hover`));

    await vscode.commands.executeCommand("tnix.restartServer");

    // After the restart the client should reconnect and serve hovers again.
    const after = await execProvider<vscode.Hover[]>(
      "vscode.executeHoverProvider",
      fixtureUri("sample.tnix"),
      position,
    );
    assert.ok(hoverText(after).includes(`${STUB}-hover`));
  });
});
