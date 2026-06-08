import * as assert from "node:assert";
import * as vscode from "vscode";
import { EXTENSION_ID, activateExtension, openFixture } from "./helpers";

suite("activation", () => {
  test("the extension is installed and activates", async () => {
    const ext = await activateExtension();
    assert.strictEqual(ext.id, EXTENSION_ID);
    assert.strictEqual(ext.isActive, true);
  });

  test("registers the restart command", async () => {
    await activateExtension();
    const commands = await vscode.commands.getCommands(true);
    assert.ok(
      commands.includes("tnix.restartServer"),
      "tnix.restartServer should be registered",
    );
  });

  test("contributes the tnix language", async () => {
    await activateExtension();
    const languages = await vscode.languages.getLanguages();
    assert.ok(languages.includes("tnix"), "tnix language should be registered");
  });

  test("opens .tnix files as the tnix language", async () => {
    await activateExtension();
    const document = await openFixture("sample.tnix");
    assert.strictEqual(document.languageId, "tnix");
  });

  test("treats .nix files with the tnix document selector", async () => {
    await activateExtension();
    const document = await openFixture("library.nix");
    // VS Code reports the built-in id when no other extension claims it; the
    // tnix client selector still matches via the `nix` language id.
    assert.ok(["nix", "tnix"].includes(document.languageId));
  });
});
