# Acceptable solutions: workers

The acceptable solutions register for
[`035-workers.md`](../standards/035-workers.md). It is not a standard and
states no rule — read
[the charter](../README.md#acceptable-solutions-the-register-of-what-satisfies-a-standard)
for what this class of document may and may not do. Everything below is a
claim that some component satisfies a verb WK5 states, and the date that claim
was last checked.

WK5 names seven verbs and
[`runner-contract.json`](../contracts/workers/runner-contract.json) is their
machine-readable form. This page maps them onto components. It adds no verb,
excuses none, and a component that leaves one unsatisfied is shown here
leaving it unsatisfied rather than quietly dropped.

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

**Read the container-CLI column as the standard means it.** It satisfies the
three verbs a pipeline or an operator needs to run a one-shot on demand
(WK4's shape) and it is not a scheduler: verbs 4 to 7 have no answer there.
That column is admitted for deployment-step and operator-triggered jobs, and
is not a runner for a periodic job. The gap is the point, and it is why WK5
states verbs rather than naming a component.

## What to verify before adopting one

1. **All seven, or which four are missing.** A runtime satisfying three verbs
   runs one-shots and does not run periodic jobs, and a repository that puts a
   periodic job on it has a schedule nothing enforces.
2. **That the schedule is read in UTC.** Verb 4 is the one most often
   satisfied *nearly*: a scheduler with a default local zone will fire the
   right expression at the wrong instant, and the failure is invisible until a
   clock change.
3. **That overlap is forbidden by the runner and not only by the job.** WK5
   says the duplication with 057 JB6 is deliberate; a runtime whose overlap
   setting is advisory leaves only the job's lock, which is the case the
   standard chose not to rely on alone.
4. **That the rendered form is generated, per WK6.** Whatever the runtime, the
   manifest or unit file is rendered from the job's declaration at deployment
   and never hand-edited — which is a rule, and the reason this register names
   settings rather than telling anyone to write them.

## Checked

**2026-09-03**, against each component's own documentation. Next re-check due
**2027-03-02**, per the charter's 180-day horizon. A re-check confirms that
each setting still carries that name and that meaning, and that no runtime has
gained or lost a verb. A setting renamed in an orchestrator release is the
most likely finding, and it is a correction to this page and not to WK5.
