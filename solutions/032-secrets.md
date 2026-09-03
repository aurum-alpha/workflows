# Acceptable solutions: secrets

The acceptable solutions register for
[`032-secrets.md`](../standards/032-secrets.md). It is not a standard and
states no rule — read
[the charter](../README.md#acceptable-solutions-the-register-of-what-satisfies-a-standard)
for what this class of document may and may not do. Everything below is a
claim that some implementation meets a rule 032 states, and the date that
claim was last checked.

SE10 pins two things this page does not repeat: the **mechanism class** per
runtime, and the **four properties** any implementation of one must have —
the environment complete before the process starts, the store credential held
by a platform component and never the application, rotation by re-render with
no code change, and the store's access log naming that platform component.
Read them there. A candidate is admitted by having those properties, not by
appearing here, and every entry below is on this page because it was checked
against them.

## The store

SE10 requires one store per platform, chosen by the platform. The register
names no default, and that is deliberate rather than an omission: the rule
already decides it. **The store is the one the hosting platform provides**,
because a second store attached for preference is the PC1 failure SE10 cites,
and because the delivery mechanisms below are built for the platform's own.

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
| Encrypted secret values committed to the repository, in any shape, sealed forms included | **SE10**, on five independent grounds — permanent history that leaves at handover, a bootstrap key that keeps the delivery step and adds a master key beside it, a second mechanism where one way is the rule, a GitOps premise the platform has not adopted, and required configuration in the repository against SC3. No exception; the register admits none and never will. |
| The application calling a store's SDK at start | **SE1**. This is the rule the whole standard opens with, and an operator's name on it does not change it. |
| A native secret object written by hand or by a pipeline | **SE10**. A copy nobody rotates. The operator owns the object. |
| A second store attached because a repository's author prefers it | **SE10**, and PC1 behind it. |

## Checked

**2026-09-03**, against each project's own documentation. Next re-check due
**2027-03-02**, per the charter's 180-day horizon. A re-check confirms that
each implementation still exists under that name, still meets SE10's four
properties, and that no runtime class has acquired a mechanism that the class
description no longer covers — the last being the one that would send a
finding back to the standard rather than to this page.
