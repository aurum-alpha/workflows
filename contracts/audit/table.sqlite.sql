-- standards/080-audit.md: the audit store, one row per AE2 event and one
-- column per member, for SQLite. A product's migration carries this file
-- verbatim. No foreign key reaches this table (AE4). SQLite has no roles, so
-- AE6 here is the request path holding no UPDATE and no DELETE statement at
-- all: retention and erasure run from a separate process, by policy.
-- Timestamps are the canonical IP4 form, which sorts as text.
CREATE TABLE audit_events (
    event_id            TEXT    NOT NULL PRIMARY KEY,
    schema_version      INTEGER NOT NULL,
    occurred_at         TEXT    NOT NULL,
    recorded_at         TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
    action              TEXT    NOT NULL,
    outcome             TEXT    NOT NULL CHECK (outcome IN ('success', 'failure')),
    actor_type          TEXT    NOT NULL,
    actor_id            TEXT,
    actor_display       TEXT,
    actor_ip            TEXT,
    actor_user_agent    TEXT,
    actor_impersonator  TEXT,
    target_type         TEXT    NOT NULL,
    target_id           TEXT,
    target_display      TEXT,
    tenant_id           TEXT,
    trace_id            TEXT,
    span_id             TEXT,
    request_id          TEXT,
    decision            TEXT,
    changes             TEXT,
    reason              TEXT,
    erased_at           TEXT,
    erased_subjects     TEXT,
    CONSTRAINT audit_events_correlation CHECK (
        (trace_id IS NULL AND span_id IS NULL AND request_id IS NULL)
        OR (trace_id IS NOT NULL AND request_id IS NOT NULL)
    ),
    CONSTRAINT audit_events_erasure CHECK ((erased_at IS NULL) = (erased_subjects IS NULL))
);

CREATE INDEX audit_events_action_idx   ON audit_events (action, occurred_at DESC);
CREATE INDEX audit_events_actor_idx    ON audit_events (actor_id, occurred_at DESC);
CREATE INDEX audit_events_target_idx   ON audit_events (target_id, occurred_at DESC);
CREATE INDEX audit_events_tenant_idx   ON audit_events (tenant_id, occurred_at DESC);
CREATE INDEX audit_events_occurred_idx ON audit_events (occurred_at DESC, event_id DESC);
