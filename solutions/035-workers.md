# Acceptable solutions: workers

Register for [`standards/035-workers.md`](../standards/035-workers.md).
Checked 2026-09-03; next check due 2027-03-02.

WK5 names seven verbs, with
[`runner-contract.json`](../contracts/workers/runner-contract.json) as their
machine-readable form; this page maps them onto components.

## The mapping

| WK5 verb | Orchestrator `batch/v1` | Init-system timer and oneshot unit | Container CLI, by a pipeline or an operator | Managed schedulers |
|---|---|---|---|---|
| 1. Run an image to completion, exit code exposed | `Job`, `restartPolicy: Never` | `Type=oneshot`, `ExecStart=` | `docker run` | ECS RunTask, Cloud Run Jobs, Nomad `batch` |
| 2. `SIGTERM`, then the declared grace | `terminationGracePeriodSeconds` | `TimeoutStopSec=` | `docker stop -t` | Task stop timeout |
| 3. Enforce the deadline | `activeDeadlineSeconds` | `RuntimeMaxSec=` | `timeout` around the run | Task timeout |
| 4. Five-field cron in UTC, tick as `--at` | `schedule`, `timeZone: Etc/UTC` | `OnCalendar=`, translated from cron | **Not a scheduler** | EventBridge Scheduler, Cloud Scheduler, Nomad `periodic` |
| 5. No second run of one schedule | `concurrencyPolicy: Forbid` | A timer never starts an active unit | **—** | `prohibit_overlap` and equivalents |
| 6. No retry of a failed run | `backoffLimit: 0` | No `Restart=` | **—** | Retry count zero |
| 7. Missed tick by the declared policy | `startingDeadlineSeconds` | `Persistent=` | **—** | Catch-up settings |

The CLI column runs one-shots only (WK4); it is not a runner for a periodic
job.

## What to verify before adopting one

1. **All seven, or which four are missing.** A runtime satisfying three verbs
   runs one-shots and does not run periodic jobs. A repository that puts a
   periodic job on it has a schedule nothing enforces.
2. **That the schedule is read in UTC.** Verb 4 is the one most often
   satisfied *nearly*. A scheduler with a default local zone will fire the
   right expression at the wrong instant. The failure is invisible until a
   clock change.
3. **That overlap is forbidden by the runner and not only by the job.** WK5
   says the duplication with 057 JB6 is deliberate. A runtime whose overlap
   setting is advisory leaves only the job's lock. That is the case the
   standard chose not to rely on alone.
