CREATE SCHEMA factstr;

-- FACTSTR requires gapless committed sequence numbers, so metadata tracks the
-- current number instead of using PostgreSQL sequences.
CREATE TABLE factstr.metadata (
    id boolean PRIMARY KEY DEFAULT true CHECK (id),
    current_sequence_number bigint NOT NULL DEFAULT 0 CHECK (current_sequence_number >= 0)
);

INSERT INTO factstr.metadata (id, current_sequence_number)
VALUES (true, 0);

CREATE TABLE factstr.events (
    -- Canonical global ordering mechanism for all FACTSTR events.
    sequence_number bigint PRIMARY KEY CHECK (sequence_number > 0),

    -- Event metadata only; this timestamp is not the ordering mechanism.
    occurred_at timestamptz NOT NULL DEFAULT transaction_timestamp(),

    event_type text NOT NULL CHECK (length(event_type) > 0),

    -- The first PostgreSQL implementation stores event payloads as JSONB.
    payload jsonb NOT NULL CHECK (jsonb_typeof(payload) = 'object')
);

CREATE INDEX factstr_events_event_type_idx
ON factstr.events (event_type);

CREATE INDEX factstr_events_event_type_sequence_idx
ON factstr.events (event_type, sequence_number);

CREATE INDEX factstr_events_payload_gin_idx
ON factstr.events USING gin (payload jsonb_path_ops);
