import type { Plugin } from "vite";
import { resolveVersionInfo } from "./resolve-version-info";

/** Import as `virtual:app-version-info` in client code. */
export const APP_VERSION_INFO_MODULE = "virtual:app-version-info";

const RESOLVED = `\0${APP_VERSION_INFO_MODULE}`;

/**
 * Compiles build provenance into the client bundle (090 WC2).
 * Dev and production: `import { versionInfo } from "virtual:app-version-info"`.
 */
export function vitePluginVersionInfo(repoRoot: string): Plugin {
  return {
    name: "aurum:vite-plugin-version-info",
    resolveId(id: string) {
      if (id === APP_VERSION_INFO_MODULE) {
        return RESOLVED;
      }
    },
    load(id: string) {
      if (id !== RESOLVED) {
        return;
      }
      const info = resolveVersionInfo(repoRoot);
      return `export const versionInfo = ${JSON.stringify(info)};\n`;
    },
  };
}
