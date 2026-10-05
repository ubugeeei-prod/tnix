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
    for (const command of [
      "tynix.restartServer",
      "tynix.showOutput",
      "tynix.showVersion",
      "tynix.runDoctor",
      "tynix.installServer",
      "tynix.showMenu",
    ]) {
      assert.ok(commands.includes(command), `${command} should be registered`);
    }
  });

  test("contributes the tynix language", async () => {
    await activateExtension();
    const languages = await vscode.languages.getLanguages();
    assert.ok(languages.includes("tynix"), "tynix language should be registered");
  });

  test("contributes the tynix grammars and snippets", async () => {
    const ext = await activateExtension();
    const contributes = (
      ext.packageJSON as { contributes: Record<string, unknown> }
    ).contributes as {
      grammars: { scopeName: string }[];
      snippets: { language: string }[];
      walkthroughs: { id: string }[];
    };
    const scopes = contributes.grammars.map((g) => g.scopeName);
    assert.ok(scopes.includes("source.tynix"));
    assert.ok(scopes.includes("markdown.tynix.codeblock"));
    assert.ok(contributes.snippets.some((s) => s.language === "tynix"));
    assert.ok(
      contributes.walkthroughs.some((w) => w.id === "tynix.gettingStarted"),
    );
  });

  test("opens .tynix files as the tynix language", async () => {
    await activateExtension();
    const document = await openFixture("sample.tynix");
    assert.strictEqual(document.languageId, "tynix");
  });

  test("treats .nix files with the tynix document selector", async () => {
    await activateExtension();
    const document = await openFixture("library.nix");
    // VS Code reports the built-in id when no other extension claims it; the
    // tynix client selector still matches via the `nix` language id.
    assert.ok(["nix", "tynix"].includes(document.languageId));
  });
});
