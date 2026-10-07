# Client build version (Vite)

Build provenance for the browser is **compiled into the bundle**, not fetched
( [`standards/090-web-client.md`](../../standards/090-web-client.md) WC2).

In CI, `job-build-js-vite` sets `AURUM_BUILD_STAMP` and `AURUM_RELEASE_BUILD`
from the shared version-stamp block (same answer as Go and OCI). The plugin
reads those env vars; it does not re-implement the stamp algorithm.

## Copy into a product repository

1. Copy `resolve-version-info.ts` and `vite-plugin-version-info.ts` into
   `scripts/` at the repository root (next to root `vite.config.ts`), or into
   `client/scripts/` when the Vite app lives under `client/` and only that
   tree has `node_modules` (so TypeScript can resolve `vite` during
   `tsc -b`).
2. Register in `vite.config.ts`:

   ```ts
   import path from "path";
   import { vitePluginVersionInfo } from "./scripts/vite-plugin-version-info";

   vitePluginVersionInfo(path.resolve(__dirname)), // repo root
   ```

3. Declare the virtual module (e.g. `client/src/vite-env.d.ts`):

   ```ts
   declare module "virtual:app-version-info" {
     export const versionInfo: {
       readonly version: string;
       readonly releaseVersion: string;
       readonly buildStamp: string;
       readonly isReleaseBuild: boolean;
       readonly channel: "release" | "development" | "local";
       readonly gitBranch: string;
       readonly gitCommit: string;
       readonly buildDate: string;
       readonly environment: string;
       readonly isDirty: boolean;
     };
   }
   ```

4. UI: show **`buildStamp`** as the headline; badge **Release** when
   `isReleaseBuild`, else **Development build** (or **Local** when
   `channel === "local"`). Prefer `@aurum-alpha/platform-web`'s
   `BuildProvenanceBlock` when available.
5. Remove any `/api/version-info`, `version-info.json` fetch, or server-side
   generators for the client stamp.
6. CI: `vite build` must run with `.version`, git (or `GITHUB_*`), and the
   catalog env vars above.

Do not commit generated stamps. The plugin runs at bundle time only.

## Node server bundles (`job-build-js-esbuild`)

The esbuild job does not run this Vite plugin. Server provenance on `/healthz`
comes from **runtime env** the image sets at deploy time (`VERSION` as the
build stamp, `GIT_COMMIT`, `BUILT_AT`), wired in the product's Dockerfile or
compose from the same `stamp` output as the client build. The browser bundle
alone uses `AURUM_BUILD_STAMP` at `vite build` time.
