import { copyFileSync, createReadStream, mkdirSync, rmSync } from "node:fs";
import { createHash } from "node:crypto";
import { readFile, writeFile } from "node:fs/promises";
import { basename, dirname, isAbsolute, join, relative, resolve, sep } from "node:path";
import { tmpdir } from "node:os";
import { capture, printUsage, run, rootDir } from "./utils.ts";

type ChecksumEntry = {
  expectedDigest: string;
  archiveName: string;
  archivePath: string;
  lineNumber: number;
};

async function sha256File(path: string): Promise<string> {
  const hash = createHash("sha256");

  await new Promise<void>((resolvePromise, reject) => {
    const stream = createReadStream(path);
    stream.on("data", (chunk) => hash.update(chunk));
    stream.on("end", () => resolvePromise());
    stream.on("error", reject);
  });

  return hash.digest("hex");
}

function printHelp(): void {
  printUsage([
    "Usage:",
    "  node --experimental-strip-types ./scripts/package-release.ts <version> <target> <archive> <sha>",
    "  node --experimental-strip-types ./scripts/package-release.ts verify-checksum <sha> [<sha> ...]",
    "",
    "Examples:",
    "  node --experimental-strip-types ./scripts/package-release.ts v0.2.0 linux-x64 tnix-v0.2.0-linux-x64.tar.gz tnix-v0.2.0-linux-x64.sha256",
    "  node --experimental-strip-types ./scripts/package-release.ts verify-checksum tnix-v0.2.0-linux-x64.sha256",
  ]);
}

function resolveArchivePath(checksumPath: string, archiveName: string, lineNumber: number): string {
  if (isAbsolute(archiveName)) {
    throw new Error(`${checksumPath}:${lineNumber}: archive path must be relative`);
  }

  const checksumDir = dirname(checksumPath);
  const archivePath = resolve(checksumDir, archiveName);
  const relativeArchivePath = relative(checksumDir, archivePath);

  if (
    relativeArchivePath === "" ||
    relativeArchivePath === ".." ||
    relativeArchivePath.startsWith(`..${sep}`) ||
    isAbsolute(relativeArchivePath)
  ) {
    throw new Error(
      `${checksumPath}:${lineNumber}: archive path must stay within the checksum file directory`,
    );
  }

  return archivePath;
}

function parseChecksumEntries(checksumPath: string, contents: string): ChecksumEntry[] {
  const entries: ChecksumEntry[] = [];
  const lines = contents.split("\n");

  for (const [index, rawLine] of lines.entries()) {
    const lineNumber = index + 1;
    const line = rawLine.endsWith("\r") ? rawLine.slice(0, -1) : rawLine;

    if (line === "" && index === lines.length - 1) {
      continue;
    }

    const match = /^([0-9a-fA-F]{64})  (.+)$/.exec(line);
    if (!match) {
      throw new Error(`${checksumPath}:${lineNumber}: expected "<sha256>  <archive>"`);
    }

    const archiveName = match[2];
    if (archiveName.includes("\0")) {
      throw new Error(`${checksumPath}:${lineNumber}: archive path contains a NUL byte`);
    }

    entries.push({
      expectedDigest: match[1].toLowerCase(),
      archiveName,
      archivePath: resolveArchivePath(checksumPath, archiveName, lineNumber),
      lineNumber,
    });
  }

  if (entries.length === 0) {
    throw new Error(`${checksumPath}: checksum file is empty`);
  }

  return entries;
}

async function verifyChecksumFile(checksumPath: string): Promise<void> {
  const contents = await readFile(checksumPath, "utf8");
  const entries = parseChecksumEntries(checksumPath, contents);

  for (const entry of entries) {
    const actualDigest = await sha256File(entry.archivePath);
    if (actualDigest !== entry.expectedDigest) {
      throw new Error(
        `${checksumPath}:${entry.lineNumber}: checksum mismatch for ${entry.archiveName}\n` +
          `  expected: ${entry.expectedDigest}\n` +
          `  actual:   ${actualDigest}`,
      );
    }

    console.log(`${entry.archiveName}: OK`);
  }
}

async function packageRelease(
  version: string,
  target: string,
  archiveName: string,
  shaName: string,
): Promise<void> {
  const stageDir = join(tmpdir(), `tnix-release-${process.pid}-${Date.now()}`);
  const releaseDir = join(stageDir, `tnix-${version.replace(/^v/, "")}-${target}`);

  mkdirSync(join(releaseDir, "bin"), { recursive: true });

  try {
    run("cabal", ["build", "exe:tnix", "exe:tnix-lsp"]);

    const tnixBin = capture("cabal", ["list-bin", "exe:tnix"]);
    const tnixLspBin = capture("cabal", ["list-bin", "exe:tnix-lsp"]);

    copyFileSync(tnixBin, join(releaseDir, "bin/tnix"));
    copyFileSync(tnixLspBin, join(releaseDir, "bin/tnix-lsp"));
    copyFileSync(join(rootDir, "README.md"), join(releaseDir, "README.md"));
    copyFileSync(join(rootDir, "CHANGELOG.md"), join(releaseDir, "CHANGELOG.md"));
    copyFileSync(join(rootDir, "LICENSE"), join(releaseDir, "LICENSE"));

    run("tar", ["-C", stageDir, "-czf", archiveName, basename(releaseDir)]);

    const digest = await sha256File(join(rootDir, archiveName));
    const checksumLine = `${digest}  ${archiveName}\n`;
    await writeFile(join(rootDir, shaName), checksumLine);
  } finally {
    rmSync(stageDir, { recursive: true, force: true });
  }
}

async function main(): Promise<void> {
  const args = process.argv.slice(2);
  const wantsHelp = args.includes("--help") || args.includes("-h");

  if (wantsHelp) {
    printHelp();
    return;
  }

  process.chdir(rootDir);

  if (args[0] === "verify-checksum") {
    const checksumNames = args.slice(1);
    if (checksumNames.length === 0) {
      printHelp();
      process.exit(1);
    }

    for (const checksumName of checksumNames) {
      await verifyChecksumFile(resolve(rootDir, checksumName));
    }
    return;
  }

  const [version, target, archiveName, shaName] = args;
  if (!version || !target || !archiveName || !shaName || args.length !== 4) {
    printHelp();
    process.exit(1);
  }

  await packageRelease(version, target, archiveName, shaName);
}

await main().catch((error: unknown) => {
  console.error(error instanceof Error ? error.message : String(error));
  process.exit(1);
});
