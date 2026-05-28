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

CREATE FUNCTION factstr.append(events jsonb)
RETURNS TABLE (
    sequence_number bigint,
    occurred_at timestamptz,
    event_type text,
    payload jsonb
)
LANGUAGE plpgsql
VOLATILE
AS $$
DECLARE
    base_sequence bigint;
    event_count bigint;
BEGIN
    IF jsonb_typeof(events) IS DISTINCT FROM 'array' THEN
        RAISE EXCEPTION 'events must be a JSON array';
    END IF;

    event_count := jsonb_array_length(events);

    IF event_count = 0 THEN
        RAISE EXCEPTION 'events must not be empty';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM jsonb_array_elements(events) AS event_data(event_value)
        WHERE jsonb_typeof(event_value) IS DISTINCT FROM 'object'
           OR jsonb_typeof(event_value -> 'event_type') IS DISTINCT FROM 'string'
           OR length(event_value ->> 'event_type') = 0
    ) THEN
        RAISE EXCEPTION 'event_type must be a non-empty string';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM jsonb_array_elements(events) AS event_data(event_value)
        WHERE jsonb_typeof(event_value -> 'payload') IS DISTINCT FROM 'object'
    ) THEN
        RAISE EXCEPTION 'payload must be a JSON object';
    END IF;

    SELECT current_sequence_number
    INTO base_sequence
    FROM factstr.metadata
    WHERE id
    FOR UPDATE;

    RETURN QUERY
    WITH inserted AS (
        INSERT INTO factstr.events (sequence_number, event_type, payload)
        SELECT
            base_sequence + event_data.ordinality,
            event_data.event_value ->> 'event_type',
            event_data.event_value -> 'payload'
        FROM jsonb_array_elements(events) WITH ORDINALITY AS event_data(event_value, ordinality)
        ORDER BY event_data.ordinality
        RETURNING
            factstr.events.sequence_number,
            factstr.events.occurred_at,
            factstr.events.event_type,
            factstr.events.payload
    ),
    updated_metadata AS (
        UPDATE factstr.metadata
        SET current_sequence_number = base_sequence + event_count
        WHERE id
        RETURNING current_sequence_number
    )
    SELECT
        inserted.sequence_number,
        inserted.occurred_at,
        inserted.event_type,
        inserted.payload
    FROM inserted
    CROSS JOIN updated_metadata
    ORDER BY inserted.sequence_number;
END;
$$;
