import { execSync } from "child_process";
import fs from "fs";
import path from "path";

export type BuildChannel = "release" | "development" | "local";

/** Build provenance compiled into the Vite bundle (090 WC2). */
export interface ClientBuildVersion {
  /** Release line from `.version` (alias kept for existing imports). */
  version: string;
  releaseVersion: string;
  /** Primary display string; matches Go binary stamp and OCI label in CI. */
  buildStamp: string;
  isReleaseBuild: boolean;
  channel: BuildChannel;
  gitBranch: string;
  gitCommit: string;
  buildDate: string;
  environment: string;
  isDirty: boolean;
}

function readReleaseVersion(repoRoot: string): string {
  try {
    return (
      fs.readFileSync(path.join(repoRoot, ".version"), "utf-8").trim() ||
      "unknown"
    );
  } catch {
    return "unknown";
  }
}

function parseReleaseBuild(env: NodeJS.ProcessEnv): boolean {
  const raw = env.AURUM_RELEASE_BUILD?.trim().toLowerCase();
  return raw === "true" || raw === "1";
}

/**
 * Reads repo-root `.version`, CI stamp env, git (or CI env), and build time.
 * Used by the Vite plugin at compile time — not at request time on the API.
 */
export function resolveVersionInfo(
  repoRoot: string,
  env: NodeJS.ProcessEnv = process.env,
  now: () => Date = () => new Date(),
): ClientBuildVersion {
  const releaseVersion = readReleaseVersion(repoRoot);

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
  const inCi = Boolean(env.GITHUB_SHA?.trim());
  const isDirty = inCi ? false : git("git status --porcelain") !== "";

  const isReleaseBuild = inCi && parseReleaseBuild(env);
  const channel: BuildChannel = !inCi
    ? "local"
    : isReleaseBuild
      ? "release"
      : "development";

  const buildStamp = (() => {
    const fromCi = env.AURUM_BUILD_STAMP?.trim();
    if (fromCi) {
      return fromCi;
    }
    if (!inCi) {
      return releaseVersion;
    }
    return releaseVersion;
  })();

  return {
    version: releaseVersion,
    releaseVersion,
    buildStamp,
    isReleaseBuild,
    channel,
    gitBranch,
    gitCommit,
    buildDate: now().toISOString(),
    environment: env.NODE_ENV || "development",
    isDirty,
  };
}
