import * as vscode from "vscode";
import {
  Executable,
  LanguageClient,
  LanguageClientOptions,
  ServerOptions,
  State,
} from "vscode-languageclient/node";
import { resolveRuntimeConfig } from "./runtime.js";

let client: LanguageClient | undefined;
let statusBarItem: vscode.StatusBarItem | undefined;

const RESTART_COMMAND = "tnix.restartServer";

/**
 * Boot the tnix language client inside VS Code.
 *
 * The extension keeps configuration deliberately small: users may override the
 * `tnix-lsp` binary path, while everything else is derived from the current
 * workspace. The runtime work itself is delegated to the Haskell LSP server.
 *
 * Startup is wrapped so a missing or crashing `tnix-lsp` shows a clear toast
 * with the resolved command, surfaces a status bar indicator, and registers a
 * `tnix.restartServer` command so users can recover without reloading the
 * window.
 */
export async function activate(
  context: vscode.ExtensionContext,
): Promise<void> {
  statusBarItem = vscode.window.createStatusBarItem(
    vscode.StatusBarAlignment.Right,
    100,
  );
  statusBarItem.command = RESTART_COMMAND;
  statusBarItem.tooltip = "Click to restart the tnix language server";
  context.subscriptions.push(statusBarItem);

  context.subscriptions.push(
    vscode.commands.registerCommand(RESTART_COMMAND, async () => {
      await stopClient();
      await startClient(context);
    }),
  );

  await startClient(context);
}

/**
 * Stop the language client when the extension is deactivated.
 *
 * Keeping shutdown explicit avoids orphaned child processes when VS Code unloads
 * the extension during reloads or window closure.
 */
export async function deactivate(): Promise<void> {
  await stopClient();
}

async function startClient(context: vscode.ExtensionContext): Promise<void> {
  const config = vscode.workspace.getConfiguration("tnix");
  const runtime = resolveRuntimeConfig(
    config.get<string>("server.path"),
    config.get<string[]>("server.args"),
    config.get<string>("server.cwd"),
    vscode.workspace.workspaceFolders?.map((folder) => folder.uri.fsPath),
  );
  const executable: Executable = {
    command: runtime.command,
    args: runtime.args,
    options: { cwd: runtime.cwd, env: process.env },
  };
  const serverOptions: ServerOptions = {
    run: executable,
    debug: executable,
  };
  const clientOptions: LanguageClientOptions = {
    documentSelector: runtime.documentSelector,
    synchronize: {
      fileEvents: vscode.workspace.createFileSystemWatcher(
        runtime.watchPattern,
      ),
    },
  };

  const created = new LanguageClient(
    "tnix",
    "tnix",
    serverOptions,
    clientOptions,
  );
  client = created;
  context.subscriptions.push(created);
  context.subscriptions.push(
    created.onDidChangeState((event) => updateStatus(event.newState)),
  );

  setStatus("starting", runtime.command);

  try {
    await created.start();
    setStatus("running", runtime.command);
  } catch (error) {
    const detail = formatError(error);
    setStatus("error", runtime.command);
    const action = await vscode.window.showErrorMessage(
      `tnix-lsp failed to start using \`${describeCommand(runtime.command, runtime.args)}\`: ${detail}`,
      "Open Settings",
      "Restart Server",
    );
    if (action === "Open Settings") {
      await vscode.commands.executeCommand(
        "workbench.action.openSettings",
        "tnix.server.path",
      );
    } else if (action === "Restart Server") {
      await vscode.commands.executeCommand(RESTART_COMMAND);
    }
  }
}

async function stopClient(): Promise<void> {
  if (client) {
    try {
      await client.stop();
    } catch {
      // Stopping a client that already died is fine; suppress so deactivate stays clean.
    }
    client = undefined;
  }
}

type Status = "starting" | "running" | "error" | "stopped";

function setStatus(status: Status, command: string): void {
  if (!statusBarItem) return;
  switch (status) {
    case "starting":
      statusBarItem.text = "$(sync~spin) tnix";
      statusBarItem.tooltip = `Starting tnix-lsp (${command})`;
      statusBarItem.backgroundColor = undefined;
      break;
    case "running":
      statusBarItem.text = "$(check) tnix";
      statusBarItem.tooltip = `tnix-lsp running (${command}). Click to restart.`;
      statusBarItem.backgroundColor = undefined;
      break;
    case "error":
      statusBarItem.text = "$(error) tnix";
      statusBarItem.tooltip = `tnix-lsp failed (${command}). Click to retry.`;
      statusBarItem.backgroundColor = new vscode.ThemeColor(
        "statusBarItem.errorBackground",
      );
      break;
    case "stopped":
      statusBarItem.text = "$(circle-slash) tnix";
      statusBarItem.tooltip = "tnix-lsp stopped. Click to start.";
      statusBarItem.backgroundColor = undefined;
      break;
  }
  statusBarItem.show();
}

function updateStatus(state: State): void {
  if (!client || !statusBarItem) return;
  const command = client.clientOptions.outputChannel?.name ?? "tnix-lsp";
  switch (state) {
    case State.Starting:
      setStatus("starting", command);
      break;
    case State.Running:
      setStatus("running", command);
      break;
    case State.Stopped:
      setStatus("stopped", command);
      break;
  }
}

function describeCommand(command: string, args: readonly string[]): string {
  return [command, ...args].join(" ");
}

function formatError(error: unknown): string {
  if (error instanceof Error) return error.message;
  if (typeof error === "string") return error;
  return JSON.stringify(error);
}
