import { execSync } from "child_process";
import fs from "fs";
import path from "path";

/** Build provenance compiled into the Vite bundle (090 WC2). */
export interface ClientBuildVersion {
  version: string;
  gitBranch: string;
  gitCommit: string;
  buildDate: string;
  environment: string;
  isDirty: boolean;
}

/**
 * Reads repo-root `.version`, git (or CI env), and build time.
 * Used by the Vite plugin at compile time — not at request time on the API.
 */
export function resolveVersionInfo(
  repoRoot: string,
  env: NodeJS.ProcessEnv = process.env,
  now: () => Date = () => new Date(),
): ClientBuildVersion {
  const version = (() => {
    try {
      return (
        fs.readFileSync(path.join(repoRoot, ".version"), "utf-8").trim() ||
        "unknown"
      );
    } catch {
      return "unknown";
    }
  })();

  const git = (command: string): string => {
    try {
      return execSync(command, {
        cwd: repoRoot,
        stdio: ["ignore", "pipe", "ignore"],
      })
        .toString()
        .trim();
    } catch {
      return "";
    }
  };

  const gitBranch =
    env.GITHUB_REF_NAME || git("git rev-parse --abbrev-ref HEAD") || "unknown";
  const gitCommit =
    (env.GITHUB_SHA || git("git rev-parse HEAD")).slice(0, 7) || "unknown";
  const isDirty = env.GITHUB_SHA
    ? false
    : git("git status --porcelain") !== "";

  return {
    version,
    gitBranch,
    gitCommit,
    buildDate: now().toISOString(),
    environment: env.NODE_ENV || "development",
    isDirty,
  };
}
