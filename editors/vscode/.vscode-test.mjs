import { defineConfig } from "@vscode/test-cli";

// Integration tests run the real extension inside a downloaded VS Code build and
// drive it against the hermetic stub LSP server in the fixture workspace (see
// src/test/fixtures/workspace). No Haskell `tnix-lsp` build is required.
export default defineConfig({
  files: "out/test/**/*.test.js",
  workspaceFolder: "src/test/fixtures/workspace",
  mocha: {
    ui: "tdd",
    color: true,
    timeout: 60000,
  },
});
