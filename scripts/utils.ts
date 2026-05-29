import { accessSync, constants, existsSync } from "node:fs";
import { delimiter, dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync, type SpawnSyncOptions } from "node:child_process";

export const rootDir = resolve(dirname(fileURLToPath(import.meta.url)), "..");

export function run(command: string, args: string[], options: SpawnSyncOptions = {}): void {
  const result = spawnSync(command, args, {
    stdio: "inherit",
    cwd: rootDir,
    ...options,
  });

  if (result.error) {
    throw result.error;
  }

  if (result.status !== 0) {
    process.exit(result.status ?? 1);
  }
}

export function capture(command: string, args: string[], options: SpawnSyncOptions = {}): string {
  const result = spawnSync(command, args, {
    stdio: ["inherit", "pipe", "inherit"],
    encoding: "utf8",
    cwd: rootDir,
    ...options,
  });

  if (result.error) {
    throw result.error;
  }

  if (result.status !== 0) {
    process.exit(result.status ?? 1);
  }

  return result.stdout.trim();
}

export function tryRun(command: string, args: string[], options: SpawnSyncOptions = {}): boolean {
  const result = spawnSync(command, args, {
    stdio: "ignore",
    cwd: rootDir,
    ...options,
  });

  return result.status === 0;
}

export function findExecutable(name: string): string | undefined {
  const pathValue = process.env.PATH ?? "";
  const isWindows = process.platform === "win32";

  // On Windows, executables are resolved by appending one of the PATHEXT
  // extensions (unless the name already carries one). Elsewhere the name is
  // used verbatim.
  const candidateNames = (() => {
    if (!isWindows) {
      return [name];
    }
    const hasExtension = /\.[^./\\]+$/.test(name);
    if (hasExtension) {
      return [name];
    }
    const pathext = (process.env.PATHEXT ?? ".COM;.EXE;.BAT;.CMD")
      .split(";")
      .map((ext) => ext.trim())
      .filter((ext) => ext.length > 0);
    return [name, ...pathext.map((ext) => name + ext)];
  })();

  for (const entry of pathValue.split(delimiter)) {
    if (!entry) {
      continue;
    }

    for (const candidateName of candidateNames) {
      const candidate = join(entry, candidateName);
      if (!existsSync(candidate)) {
        continue;
      }

      // The execute bit is not meaningful on Windows; existence on PATH is
      // sufficient there.
      if (isWindows) {
        return candidate;
      }

      try {
        accessSync(candidate, constants.X_OK);
        return candidate;
      } catch {
        continue;
      }
    }
  }

  return undefined;
}

export function printUsage(lines: string[]): void {
  console.log(lines.join("\n"));
}
