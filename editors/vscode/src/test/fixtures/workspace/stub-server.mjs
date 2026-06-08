// A minimal, deterministic LSP server used only by the VS Code integration
// tests. It implements just enough of the protocol over stdio for the tnix
// extension to connect and for the test suite to exercise every provider the
// client wires up — without depending on the real Haskell `tnix-lsp` binary.
//
// Every response uses a recognizable marker (e.g. "tnix-stub") so the tests can
// assert the extension forwarded the request and surfaced the reply. Real
// feature correctness is covered by the Haskell `Session*.spec.hs` suites.
//
// IMPORTANT: stdout is the JSON-RPC channel. All diagnostics/logging must go to
// stderr so the framing stays intact.

import process from "node:process";

const STUB = "tnix-stub";

function log(message) {
  process.stderr.write(`[stub-server] ${message}\n`);
}

function send(message) {
  const body = JSON.stringify(message);
  const payload = Buffer.from(body, "utf8");
  process.stdout.write(`Content-Length: ${payload.byteLength}\r\n\r\n`);
  process.stdout.write(payload);
}

function respond(id, result) {
  send({ jsonrpc: "2.0", id, result });
}

function notify(method, params) {
  send({ jsonrpc: "2.0", method, params });
}

const fullRange = {
  start: { line: 0, character: 0 },
  end: { line: 0, character: 1 },
};

function uriOf(params) {
  return params?.textDocument?.uri ?? "file:///unknown";
}

function publishDiagnostics(uri) {
  notify("textDocument/publishDiagnostics", {
    uri,
    diagnostics: [
      {
        range: fullRange,
        severity: 2,
        source: STUB,
        code: "TNIX-STUB-0001",
        message: `${STUB} diagnostic`,
      },
    ],
  });
}

const capabilities = {
  positionEncoding: "utf-16",
  textDocumentSync: { openClose: true, change: 1, save: { includeText: true } },
  hoverProvider: true,
  completionProvider: { triggerCharacters: ["."] },
  signatureHelpProvider: { triggerCharacters: ["(", " ", ","] },
  definitionProvider: true,
  declarationProvider: true,
  referencesProvider: true,
  renameProvider: true,
  documentSymbolProvider: true,
  workspaceSymbolProvider: true,
  documentHighlightProvider: true,
  documentFormattingProvider: true,
  documentRangeFormattingProvider: true,
  foldingRangeProvider: true,
  codeActionProvider: true,
  documentLinkProvider: { resolveProvider: false },
  inlayHintProvider: { resolveProvider: false },
  semanticTokensProvider: {
    legend: {
      tokenTypes: ["keyword", "type", "function", "variable"],
      tokenModifiers: [],
    },
    full: true,
  },
};

function handleRequest(id, method, params) {
  switch (method) {
    case "initialize":
      respond(id, {
        capabilities,
        serverInfo: { name: STUB, version: "0.0.0" },
      });
      return;
    case "shutdown":
      respond(id, null);
      return;
    case "textDocument/hover":
      respond(id, {
        contents: { kind: "markdown", value: `${STUB}-hover: Int` },
        range: fullRange,
      });
      return;
    case "textDocument/completion":
      respond(id, {
        isIncomplete: false,
        items: [
          { label: `${STUB}Item`, kind: 6, detail: "Int" },
          { label: `${STUB}Builtin`, kind: 3, detail: "a -> a" },
        ],
      });
      return;
    case "textDocument/signatureHelp":
      respond(id, {
        signatures: [
          {
            label: `${STUB}(a: Int): Int`,
            documentation: `${STUB} signature`,
            parameters: [{ label: "a: Int" }],
          },
        ],
        activeSignature: 0,
        activeParameter: 0,
      });
      return;
    case "textDocument/definition":
    case "textDocument/declaration":
      respond(id, { uri: uriOf(params), range: fullRange });
      return;
    case "textDocument/references":
      respond(id, [{ uri: uriOf(params), range: fullRange }]);
      return;
    case "textDocument/documentHighlight":
      respond(id, [{ range: fullRange, kind: 1 }]);
      return;
    case "textDocument/rename":
      respond(id, {
        changes: {
          [uriOf(params)]: [{ range: fullRange, newText: `${STUB}Renamed` }],
        },
      });
      return;
    case "textDocument/documentSymbol":
      respond(id, [
        {
          name: `${STUB}Symbol`,
          kind: 13,
          range: fullRange,
          selectionRange: fullRange,
        },
      ]);
      return;
    case "workspace/symbol":
      respond(id, [
        {
          name: `${STUB}Symbol`,
          kind: 13,
          location: { uri: uriOf(params), range: fullRange },
        },
      ]);
      return;
    case "textDocument/formatting":
    case "textDocument/rangeFormatting":
      respond(id, [{ range: fullRange, newText: `# ${STUB} formatted\n` }]);
      return;
    case "textDocument/foldingRange":
      respond(id, [{ startLine: 0, endLine: 1, kind: "region" }]);
      return;
    case "textDocument/documentLink":
      respond(id, [
        { range: fullRange, target: "https://example.invalid/tnix-stub" },
      ]);
      return;
    case "textDocument/inlayHint":
      respond(id, [
        { position: { line: 0, character: 1 }, label: `: ${STUB}Int`, kind: 1 },
      ]);
      return;
    case "textDocument/semanticTokens/full":
      // One token: line 0, startChar 0, length 3, tokenType 0 (keyword), no modifiers.
      respond(id, { data: [0, 0, 3, 0, 0] });
      return;
    case "textDocument/codeAction":
      respond(id, [{ title: `${STUB} action`, kind: "quickfix" }]);
      return;
    default:
      // Unknown method with an id: reply with an empty/neutral result so the
      // client never blocks waiting on us.
      respond(id, null);
  }
}

function handleNotification(method, params) {
  switch (method) {
    case "initialized":
      return;
    case "textDocument/didOpen":
    case "textDocument/didChange":
    case "textDocument/didSave":
      publishDiagnostics(uriOf(params));
      return;
    case "exit":
      process.exit(0);
      return;
    default:
      return;
  }
}

function dispatch(message) {
  if (message.method && message.id !== undefined) {
    handleRequest(message.id, message.method, message.params);
  } else if (message.method) {
    handleNotification(message.method, message.params);
  }
}

let buffer = Buffer.alloc(0);

function drain() {
  while (true) {
    const headerEnd = buffer.indexOf("\r\n\r\n");
    if (headerEnd === -1) return;
    const header = buffer.slice(0, headerEnd).toString("ascii");
    const match = /Content-Length:\s*(\d+)/i.exec(header);
    if (!match) {
      buffer = buffer.slice(headerEnd + 4);
      continue;
    }
    const length = Number.parseInt(match[1], 10);
    const bodyStart = headerEnd + 4;
    if (buffer.byteLength < bodyStart + length) return;
    const body = buffer.slice(bodyStart, bodyStart + length).toString("utf8");
    buffer = buffer.slice(bodyStart + length);
    try {
      dispatch(JSON.parse(body));
    } catch (error) {
      log(`failed to handle message: ${String(error)}`);
    }
  }
}

process.stdin.on("data", (chunk) => {
  buffer = Buffer.concat([buffer, chunk]);
  drain();
});

process.stdin.on("end", () => process.exit(0));

log("ready");
