import * as assert from "node:assert";
import * as vscode from "vscode";
import { EXTENSION_ID, activateExtension } from "./helpers";

suite("configuration", () => {
  test("exposes the tnix configuration section", async () => {
    await activateExtension();
    const config = vscode.workspace.getConfiguration("tnix");
    assert.ok(config.has("server.path"));
    assert.ok(config.has("server.args"));
    assert.ok(config.has("server.cwd"));
    assert.ok(config.has("trace.server"));
  });

  test("reads the fixture workspace server settings", async () => {
    await activateExtension();
    const config = vscode.workspace.getConfiguration("tnix");
    assert.strictEqual(config.get<string>("server.path"), "node");
    assert.deepStrictEqual(config.get<string[]>("server.args"), [
      "stub-server.mjs",
    ]);
  });

  test("declares the configuration contributions in the manifest", async () => {
    const ext = vscode.extensions.getExtension(EXTENSION_ID);
    assert.ok(ext);
    const props = ext.packageJSON.contributes?.configuration?.properties ?? {};
    for (const key of [
      "tnix.server.path",
      "tnix.server.args",
      "tnix.server.cwd",
      "tnix.trace.server",
    ]) {
      assert.ok(key in props, `${key} should be contributed`);
    }
  });

  test("declares the .nix/.tnix/.d.tnix file extensions", async () => {
    const ext = vscode.extensions.getExtension(EXTENSION_ID);
    assert.ok(ext);
    const language = ext.packageJSON.contributes.languages.find(
      (entry: { id: string }) => entry.id === "tnix",
    );
    assert.ok(language);
    for (const extension of [".nix", ".tnix", ".d.tnix"]) {
      assert.ok(
        language.extensions.includes(extension),
        `${extension} should be associated with tnix`,
      );
    }
  });
});
