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

CREATE FUNCTION factstr.query(
    event_types text[],
    payload_predicates jsonb DEFAULT '{}'::jsonb,
    min_sequence_number bigint DEFAULT 0
)
RETURNS TABLE (
    sequence_number bigint,
    occurred_at timestamptz,
    event_type text,
    payload jsonb
)
LANGUAGE sql
STABLE
AS $$
    SELECT
        events.sequence_number,
        events.occurred_at,
        events.event_type,
        events.payload
    FROM factstr.events
    WHERE cardinality(event_types) > 0
      AND events.event_type = ANY (event_types)
      AND events.payload @> COALESCE(payload_predicates, '{}'::jsonb)
      AND events.sequence_number > GREATEST(COALESCE(min_sequence_number, 0), 0)
    ORDER BY events.sequence_number ASC;
$$;

-- current_context_version is not a read cursor; it must be calculated over the
-- full command context selected by event types and payload predicates.
CREATE FUNCTION factstr.current_context_version(
    event_types text[],
    payload_predicates jsonb DEFAULT '{}'::jsonb
)
RETURNS bigint
LANGUAGE sql
STABLE
AS $$
    SELECT COALESCE(MAX(events.sequence_number), 0)
    FROM factstr.events
    WHERE cardinality(event_types) > 0
      AND events.event_type = ANY (event_types)
      AND events.payload @> COALESCE(payload_predicates, '{}'::jsonb);
$$;

-- append_if is the FACTSTR command context consistency primitive.
-- The context version is evaluated over the full command context and is not
-- affected by a read cursor.
CREATE FUNCTION factstr.append_if(
    events jsonb,
    context_event_types text[],
    context_payload_predicates jsonb,
    expected_context_version bigint
)
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
    actual_context_version bigint;
    normalized_context_payload_predicates jsonb;
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

    IF expected_context_version IS NULL THEN
        RAISE EXCEPTION 'expected_context_version must not be null';
    END IF;

    IF expected_context_version < 0 THEN
        RAISE EXCEPTION 'expected_context_version must be greater than or equal to 0';
    END IF;

    normalized_context_payload_predicates := COALESCE(context_payload_predicates, '{}'::jsonb);

    SELECT current_sequence_number
    INTO base_sequence
    FROM factstr.metadata
    WHERE id
    FOR UPDATE;

    IF cardinality(context_event_types) > 0 THEN
        SELECT COALESCE(MAX(factstr.events.sequence_number), 0)
        INTO actual_context_version
        FROM factstr.events
        WHERE factstr.events.event_type = ANY (context_event_types)
          AND factstr.events.payload @> normalized_context_payload_predicates;
    ELSE
        actual_context_version := 0;
    END IF;

    IF actual_context_version <> expected_context_version THEN
        RAISE EXCEPTION
            'conditional append conflict: expected %, actual %',
            expected_context_version,
            actual_context_version;
    END IF;

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
