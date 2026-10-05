# Client build version (Vite)

Build provenance for the browser is **compiled into the bundle**, not fetched
( [`standards/090-web-client.md`](../../standards/090-web-client.md) WC2).

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
       readonly gitBranch: string;
       readonly gitCommit: string;
       readonly buildDate: string;
       readonly environment: string;
       readonly isDirty: boolean;
     };
   }
   ```

4. UI: `import { versionInfo } from "virtual:app-version-info"` on an
   **existing** admin/settings screen (no new route unless nothing fits).
5. Remove any `/api/version-info`, `version-info.json` fetch, or server-side
   generators for the client stamp.
6. CI: `vite build` must run with `.version` and git (or `GITHUB_*`) available.

Do not commit generated stamps. The plugin runs at bundle time only.
