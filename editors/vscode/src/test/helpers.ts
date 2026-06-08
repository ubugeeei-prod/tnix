import * as assert from "node:assert";
import * as vscode from "vscode";

export const EXTENSION_ID = "ubugeeei.tnix";
export const STUB = "tnix-stub";

/**
 * Activate the tnix extension and return its host record.
 *
 * The fixture workspace points `tnix.server.path` at the stub LSP server, so by
 * the time `activate()` resolves the language client has connected.
 */
export async function activateExtension(): Promise<vscode.Extension<unknown>> {
  const ext = vscode.extensions.getExtension(EXTENSION_ID);
  assert.ok(ext, `extension ${EXTENSION_ID} should be installed`);
  await ext.activate();
  return ext;
}

export function fixtureUri(name: string): vscode.Uri {
  const folder = vscode.workspace.workspaceFolders?.[0];
  assert.ok(folder, "a workspace folder should be open");
  return vscode.Uri.joinPath(folder.uri, name);
}

export async function openFixture(name: string): Promise<vscode.TextDocument> {
  const document = await vscode.workspace.openTextDocument(fixtureUri(name));
  await vscode.window.showTextDocument(document, { preview: false });
  return document;
}

const sleep = (ms: number): Promise<void> =>
  new Promise((resolve) => setTimeout(resolve, ms));

/**
 * Poll until `produce` yields a non-empty value or the deadline elapses.
 *
 * Language-client providers register asynchronously after the server reports
 * its capabilities, so feature requests are retried rather than asserted once.
 */
export async function waitFor<T>(
  produce: () => Promise<T> | T,
  describe = "condition",
  timeoutMs = 30000,
  intervalMs = 150,
): Promise<T> {
  const deadline = Date.now() + timeoutMs;
  let last: unknown;
  for (;;) {
    try {
      const value = await produce();
      if (isPresent(value)) return value;
      last = value;
    } catch (error) {
      last = error;
    }
    if (Date.now() > deadline) {
      throw new Error(
        `waitFor(${describe}) timed out; last=${JSON.stringify(last)}`,
      );
    }
    await sleep(intervalMs);
  }
}

function isPresent(value: unknown): boolean {
  if (value === undefined || value === null) return false;
  if (Array.isArray(value)) return value.length > 0;
  if (value instanceof vscode.SignatureHelp) return value.signatures.length > 0;
  if (value instanceof vscode.CompletionList) return value.items.length > 0;
  return true;
}

/** Flatten hover contents (strings or MarkdownStrings) into plain text. */
export function hoverText(hovers: vscode.Hover[]): string {
  return hovers
    .flatMap((hover) => hover.contents)
    .map((content) =>
      typeof content === "string"
        ? content
        : (content as vscode.MarkdownString).value,
    )
    .join("\n");
}

export async function execProvider<T>(
  command: string,
  ...args: unknown[]
): Promise<T> {
  return waitFor<T>(
    () => Promise.resolve(vscode.commands.executeCommand<T>(command, ...args)),
    command,
  );
}
