-- standards/080-audit.md: the audit store, one row per AE2 event and one
-- column per member, for MySQL 8. A product's migration carries this file
-- verbatim and substitutes the two user placeholders. No foreign key reaches
-- this table (AE4), and the application user holds INSERT and SELECT only
-- (AE6): retention and erasure run under the migrator user, by policy.
CREATE TABLE audit_events (
    event_id            CHAR(36)     NOT NULL PRIMARY KEY,
    schema_version      SMALLINT     NOT NULL,
    occurred_at         DATETIME(3)  NOT NULL,
    recorded_at         DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    action              VARCHAR(255) NOT NULL,
    outcome             VARCHAR(16)  NOT NULL,
    actor_type          VARCHAR(64)  NOT NULL,
    actor_id            VARCHAR(128),
    actor_display       TEXT,
    actor_ip            VARCHAR(64),
    actor_user_agent    TEXT,
    actor_impersonator  JSON,
    target_type         VARCHAR(64)  NOT NULL,
    target_id           VARCHAR(128),
    target_display      TEXT,
    tenant_id           VARCHAR(128),
    trace_id            CHAR(32),
    span_id             CHAR(16),
    request_id          CHAR(36),
    decision            JSON,
    changes             JSON,
    reason              TEXT,
    erased_at           DATETIME(3),
    erased_subjects     JSON,
    CONSTRAINT audit_events_outcome CHECK (outcome IN ('success', 'failure')),
    CONSTRAINT audit_events_correlation CHECK (
        (trace_id IS NULL AND span_id IS NULL AND request_id IS NULL)
        OR (trace_id IS NOT NULL AND request_id IS NOT NULL)
    ),
    CONSTRAINT audit_events_erasure CHECK ((erased_at IS NULL) = (erased_subjects IS NULL)),
    INDEX audit_events_action_idx   (action, occurred_at),
    INDEX audit_events_actor_idx    (actor_id, occurred_at),
    INDEX audit_events_target_idx   (target_id, occurred_at),
    INDEX audit_events_tenant_idx   (tenant_id, occurred_at),
    INDEX audit_events_occurred_idx (occurred_at, event_id)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4;

-- AE6. The request path can add and read; it cannot change or remove.
REVOKE UPDATE, DELETE, DROP ON audit_events FROM '<application_user>'@'%';
GRANT  INSERT, SELECT ON audit_events TO '<application_user>'@'%';
GRANT  SELECT, UPDATE, DELETE ON audit_events TO '<migrator_user>'@'%';
