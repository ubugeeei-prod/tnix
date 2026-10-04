import { accessSync, constants, statSync } from "node:fs";
import { isAbsolute, join } from "node:path";

/**
 * Pure helpers shared by the extension host code and the unit tests.
 *
 * Nothing in this module imports `vscode`, so `node --test` can exercise it
 * directly.
 */

export const INSTALL_SCRIPT_COMMAND =
  "curl -fsSL https://tnix.dev/install.sh | sh";
export const NIX_INSTALL_COMMAND =
  "nix profile install github:ubugeeei/tnix#tnix github:ubugeeei/tnix#tnix-lsp";

/** Severity names accepted by `tnix.diagnostics.severityOverrides`. */
export type SeverityName = "error" | "warning" | "information" | "hint" | "off";

const SEVERITY_NAMES: readonly SeverityName[] = [
  "error",
  "warning",
  "information",
  "hint",
  "off",
];

/** LSP / VS Code numeric severities (VS Code: 0 = Error ... 3 = Hint). */
export const VSCODE_SEVERITY: Record<Exclude<SeverityName, "off">, number> = {
  error: 0,
  warning: 1,
  information: 2,
  hint: 3,
};

export type ExtensionSettings = {
  inlayHints: {
    enabled: boolean;
    typeHints: boolean;
    parameterHints: boolean;
  };
  diagnostics: {
    enabled: boolean;
    severityOverrides: Record<string, SeverityName>;
  };
};

const isExecutableFile = (path: string): boolean => {
  try {
    if (!statSync(path).isFile()) return false;
    if (process.platform !== "win32") accessSync(path, constants.X_OK);
    return true;
  } catch {
    return false;
  }
};

/**
 * Resolve `command` the way a shell would: explicit paths are checked as-is,
 * bare names are searched on `PATH` (honouring `PATHEXT` on Windows).
 *
 * Returns the resolved absolute path, or `undefined` when nothing matches.
 */
export function findExecutable(
  command: string,
  env: NodeJS.ProcessEnv = process.env,
  platform: NodeJS.Platform = process.platform,
  isExecutable: (path: string) => boolean = isExecutableFile,
): string | undefined {
  const trimmed = command.trim();
  if (trimmed.length === 0) return undefined;
  const hasSeparator = trimmed.includes("/") || trimmed.includes("\\");
  if (isAbsolute(trimmed) || hasSeparator) {
    return isExecutable(trimmed) ? trimmed : undefined;
  }
  const pathValue = env.PATH ?? env.Path ?? "";
  const sep = platform === "win32" ? ";" : ":";
  const extensions =
    platform === "win32"
      ? ["", ...(env.PATHEXT ?? ".EXE;.CMD;.BAT").split(";")]
      : [""];
  for (const dir of pathValue.split(sep)) {
    if (dir.length === 0) continue;
    for (const ext of extensions) {
      const candidate = join(dir, trimmed + ext);
      if (isExecutable(candidate)) return candidate;
    }
  }
  return undefined;
}

/**
 * Normalize `tnix.diagnostics.severityOverrides`: keys are upper-cased
 * diagnostic codes, unknown severity names are dropped.
 */
export function normalizeSeverityOverrides(
  raw: unknown,
): Record<string, SeverityName> {
  const result: Record<string, SeverityName> = {};
  if (raw === null || typeof raw !== "object" || Array.isArray(raw)) {
    return result;
  }
  for (const [code, value] of Object.entries(raw as Record<string, unknown>)) {
    const key = code.trim().toUpperCase();
    if (key.length === 0 || typeof value !== "string") continue;
    const severity = value.trim().toLowerCase();
    if ((SEVERITY_NAMES as readonly string[]).includes(severity)) {
      result[key] = severity as SeverityName;
    }
  }
  return result;
}

/** Extract the textual code of a diagnostic (`string`, `number` or `{ value }`). */
export function diagnosticCode(code: unknown): string | undefined {
  if (typeof code === "string") return code;
  if (typeof code === "number") return String(code);
  if (code && typeof code === "object" && "value" in code) {
    return diagnosticCode((code as { value: unknown }).value);
  }
  return undefined;
}

/**
 * Compute the severity a diagnostic should be shown with.
 *
 * Returns the original severity when no override applies, a new VS Code
 * severity number when one does, or `null` when the diagnostic is silenced.
 * Codes match case-insensitively, either exactly or as the prefix of the
 * message (tnix prefixes messages with `[CODE]` when no code field is set).
 */
export function overrideSeverity(
  code: unknown,
  message: string,
  severity: number,
  overrides: Record<string, SeverityName>,
): number | null {
  const keys = Object.keys(overrides);
  if (keys.length === 0) return severity;
  const text = diagnosticCode(code)?.toUpperCase();
  let match = text !== undefined ? overrides[text] : undefined;
  if (match === undefined) {
    const prefix = /^\s*\[?([A-Za-z]+[-_]?[A-Za-z]*\d+)\]?/.exec(message)?.[1];
    if (prefix) match = overrides[prefix.toUpperCase()];
  }
  if (match === undefined) return severity;
  return match === "off" ? null : VSCODE_SEVERITY[match];
}

/** Build the `initializationOptions` payload sent to `tnix-lsp`. */
export function buildInitializationOptions(settings: ExtensionSettings) {
  return {
    inlayHints: { ...settings.inlayHints },
    diagnostics: {
      enabled: settings.diagnostics.enabled,
      severityOverrides: { ...settings.diagnostics.severityOverrides },
    },
  };
}

/** Pull a semantic version (`0.5.0`, `1.2.3-rc.1`) out of `--version` output. */
export function parseVersion(output: string): string | undefined {
  return /\b(\d+\.\d+(?:\.\d+)?(?:[-+][0-9A-Za-z.-]+)?)\b/.exec(output)?.[1];
}
