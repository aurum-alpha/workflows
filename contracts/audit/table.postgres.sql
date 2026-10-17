-- standards/080-audit.md: the audit store, one row per AE2 event and one
-- column per member. A product's migration carries this file verbatim and
-- substitutes the two role placeholders. No foreign key reaches this table
-- (AE4), and the application role holds INSERT and SELECT only (AE6):
-- retention and erasure run under the migrator role, by policy.
CREATE TABLE audit_events (
    event_id            uuid           PRIMARY KEY,
    schema_version      smallint       NOT NULL,
    occurred_at         timestamptz(3) NOT NULL,
    recorded_at         timestamptz(3) NOT NULL DEFAULT now(),
    action              text           NOT NULL,
    outcome             text           NOT NULL CHECK (outcome IN ('success', 'failure')),
    actor_type          text           NOT NULL,
    actor_id            text,
    actor_display       text,
    actor_ip            text,
    actor_user_agent    text,
    actor_impersonator  jsonb,
    target_type         text           NOT NULL,
    target_id           text,
    target_display      text,
    tenant_id           text,
    trace_id            text,
    span_id             text,
    request_id          text,
    decision            jsonb,
    changes             jsonb,
    reason              text,
    erased_at           timestamptz(3),
    erased_subjects     jsonb,
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

-- AE6. The request path can add and read; it cannot change or remove.
REVOKE UPDATE, DELETE, TRUNCATE ON audit_events FROM <application_role>;
GRANT  INSERT, SELECT ON audit_events TO <application_role>;
GRANT  SELECT, UPDATE, DELETE ON audit_events TO <migrator_role>;
