import * as assert from "node:assert";
import * as vscode from "vscode";
import {
  STUB,
  activateExtension,
  execProvider,
  fixtureUri,
  openFixture,
} from "./helpers";

suite("formatting and structure", () => {
  setup(async () => {
    await activateExtension();
    await openFixture("sample.tnix");
  });

  test("document formatting returns text edits", async () => {
    const edits = await execProvider<vscode.TextEdit[]>(
      "vscode.executeFormatDocumentProvider",
      fixtureUri("sample.tnix"),
      { tabSize: 2, insertSpaces: true },
    );
    assert.ok(edits.length >= 1);
    assert.ok(edits[0].newText.includes(`${STUB} formatted`));
  });

  test("folding ranges are returned", async () => {
    const ranges = await execProvider<vscode.FoldingRange[]>(
      "vscode.executeFoldingRangeProvider",
      fixtureUri("sample.tnix"),
    );
    assert.ok(ranges.length >= 1);
  });
});
