# Acceptable solutions: secrets

Register for [`standards/032-secrets.md`](../standards/032-secrets.md).
Checked 2026-09-03; next check due 2027-03-02.

A candidate is admitted by SE10's four properties.

## The store

The store is the platform's own (SE10).

| Class | Implementations checked | Notes against 032 |
|---|---|---|
| The hosting provider's own manager | AWS Secrets Manager and SSM Parameter Store; Google Secret Manager; Azure Key Vault | The default consequence of SE10's "chosen by the platform". Versioning and access logging are native; per-environment and per-service scoping is an access-policy question the platform's own identity system answers. |
| A hosted manager | Doppler, Infisical | Meets SE10's three store properties. Its usual role is a sync source into the platform's native store rather than a second store beside it — which is what keeps the delivery row below unchanged. |
| A self-hosted manager | HashiCorp Vault, OpenBao | Meets the properties; the operational burden is yours, including its own unsealing and backup under [`028-backup-and-recovery.md`](../standards/028-backup-and-recovery.md). |

## Delivery, per SE10's runtime classes

| SE10 runtime class | Implementations checked | What to verify before adopting |
|---|---|---|
| An orchestrator with a native secret object | **External Secrets Operator**, syncing the store into native `Secret` objects; **Secrets Store CSI Driver**, mounting store entries as files with an optional sync to a `Secret` for variables | That a provider plugin exists for your store, and that rotation is a refresh interval or a rotation poll you can state — SE7's `reissue` needs the file rotated in place. |
| Managed container services | The platform's own injection: ECS task-definition `secrets`, Cloud Run secret environment variables and volume mounts, Azure Container Apps secret references | That the platform injects **by reference at start** rather than the pipeline baking a value into the task definition, which is a value in a deployment artifact and fails SE4. |
| Virtual machines and init-system units | An agent rendering the store into the unit's `EnvironmentFile=`, or into `$CREDENTIALS_DIRECTORY` via `LoadCredential=` — Vault Agent and `consul-template` are the established renderers | That the agent runs as its own unit under the machine's platform identity, and that the service unit holds no store credential of its own. |
| The developer's machine | `.env` from `.env.example`, per SE9 | Nothing to verify; there is no product here, and that is the point. A hosted manager's per-developer development configuration may fill the file and is still not the process's client. |
| The pipeline | The CI system's own secret store, with OIDC federation to the cloud in place of a long-lived key | That the deploying job hands the platform a **reference**, never a value. |

## Refused, and the rule that refuses each

| Route | Refused by |
|---|---|
| Encrypted secret values committed to the repository, in any shape, sealed forms included | **SE10**. |
| The application calling a store's SDK at start | **SE1**. |
| A native secret object written by hand or by a pipeline | **SE10**. A copy nobody rotates. The operator owns the object. |
| A second store attached because a repository's author prefers it | **SE10**, and PC1 behind it. |
