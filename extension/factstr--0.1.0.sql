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

CREATE FUNCTION factstr.append_if(
    events jsonb,
    context_query jsonb,
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

    SELECT current_sequence_number
    INTO base_sequence
    FROM factstr.metadata
    WHERE id
    FOR UPDATE;

    actual_context_version := COALESCE(factstr._current_context_version(context_query), 0);

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

CREATE FUNCTION factstr._current_context_version(event_query jsonb)
RETURNS bigint
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    normalized_filters jsonb;
    filters_match_all boolean;
    min_sequence bigint;
BEGIN
    IF jsonb_typeof(event_query) IS DISTINCT FROM 'object' THEN
        RAISE EXCEPTION 'event_query must be a JSON object';
    END IF;

    IF event_query ? 'filters'
       AND jsonb_typeof(event_query -> 'filters') IS DISTINCT FROM 'array' THEN
        RAISE EXCEPTION 'filters must be an array';
    END IF;

    normalized_filters := COALESCE(event_query -> 'filters', '[]'::jsonb);
    filters_match_all := NOT (event_query ? 'filters') OR jsonb_array_length(normalized_filters) = 0;

    IF EXISTS (
        SELECT 1
        FROM jsonb_array_elements(normalized_filters) AS filter_data(filter_value)
        WHERE jsonb_typeof(filter_value) IS DISTINCT FROM 'object'
    ) THEN
        RAISE EXCEPTION 'filter must be a JSON object';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM jsonb_array_elements(normalized_filters) AS filter_data(filter_value)
        WHERE filter_value ? 'event_types'
          AND jsonb_typeof(filter_value -> 'event_types') IS DISTINCT FROM 'array'
    ) THEN
        RAISE EXCEPTION 'event_types must be an array';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM jsonb_array_elements(normalized_filters) AS filter_data(filter_value)
        CROSS JOIN LATERAL jsonb_array_elements(filter_value -> 'event_types') AS event_type_data(event_type_value)
        WHERE filter_value ? 'event_types'
          AND (
              jsonb_typeof(event_type_value) IS DISTINCT FROM 'string'
              OR length(event_type_value #>> '{}') = 0
          )
    ) THEN
        RAISE EXCEPTION 'event_type must be a non-empty string';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM jsonb_array_elements(normalized_filters) AS filter_data(filter_value)
        WHERE filter_value ? 'payload_predicates'
          AND jsonb_typeof(filter_value -> 'payload_predicates') IS DISTINCT FROM 'array'
    ) THEN
        RAISE EXCEPTION 'payload_predicates must be an array';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM jsonb_array_elements(normalized_filters) AS filter_data(filter_value)
        CROSS JOIN LATERAL jsonb_array_elements(filter_value -> 'payload_predicates') AS predicate_data(predicate_value)
        WHERE filter_value ? 'payload_predicates'
          AND jsonb_typeof(predicate_value) IS DISTINCT FROM 'object'
    ) THEN
        RAISE EXCEPTION 'payload_predicate must be a JSON object';
    END IF;

    IF event_query ? 'min_sequence_number'
       AND (
           jsonb_typeof(event_query -> 'min_sequence_number') IS DISTINCT FROM 'number'
           OR NOT ((event_query ->> 'min_sequence_number') ~ '^-?[0-9]+$')
       ) THEN
        RAISE EXCEPTION 'min_sequence_number must be an integer';
    END IF;

    min_sequence := COALESCE((event_query ->> 'min_sequence_number')::bigint, 0);

    IF min_sequence < 0 THEN
        RAISE EXCEPTION 'min_sequence_number must be greater than or equal to 0';
    END IF;

    RETURN (
        WITH matching_context AS (
            SELECT events.sequence_number
            FROM factstr.events
            WHERE filters_match_all
               OR EXISTS (
                   SELECT 1
                   FROM jsonb_array_elements(normalized_filters) AS filter_data(filter_value)
                   WHERE (
                       NOT (filter_value ? 'event_types')
                       OR EXISTS (
                           SELECT 1
                           FROM jsonb_array_elements_text(filter_value -> 'event_types') AS event_type_data(event_type_value)
                           WHERE events.event_type = event_type_data.event_type_value
                       )
                   )
                   AND (
                       NOT (filter_value ? 'payload_predicates')
                       OR EXISTS (
                           SELECT 1
                           FROM jsonb_array_elements(filter_value -> 'payload_predicates') AS predicate_data(predicate_value)
                           WHERE events.payload @> predicate_data.predicate_value
                       )
                   )
               )
        )
        SELECT MAX(matching_context.sequence_number)
        FROM matching_context
    );
END;
$$;

CREATE FUNCTION factstr.query(event_query jsonb)
RETURNS TABLE (
    event_records jsonb,
    last_returned_sequence_number bigint,
    current_context_version bigint
)
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    normalized_filters jsonb;
    min_sequence bigint;
    filters_match_all boolean;
    actual_context_version bigint;
BEGIN
    actual_context_version := factstr._current_context_version(event_query);
    normalized_filters := COALESCE(event_query -> 'filters', '[]'::jsonb);
    filters_match_all := NOT (event_query ? 'filters') OR jsonb_array_length(normalized_filters) = 0;
    min_sequence := COALESCE((event_query ->> 'min_sequence_number')::bigint, 0);

    RETURN QUERY
    WITH matching_context AS (
        SELECT
            events.sequence_number,
            events.occurred_at,
            events.event_type,
            events.payload
        FROM factstr.events
        WHERE filters_match_all
           OR EXISTS (
               SELECT 1
               FROM jsonb_array_elements(normalized_filters) AS filter_data(filter_value)
               WHERE (
                   NOT (filter_value ? 'event_types')
                   OR EXISTS (
                       SELECT 1
                       FROM jsonb_array_elements_text(filter_value -> 'event_types') AS event_type_data(event_type_value)
                       WHERE events.event_type = event_type_data.event_type_value
                   )
               )
               AND (
                   NOT (filter_value ? 'payload_predicates')
                   OR EXISTS (
                       SELECT 1
                       FROM jsonb_array_elements(filter_value -> 'payload_predicates') AS predicate_data(predicate_value)
                       WHERE events.payload @> predicate_data.predicate_value
                   )
               )
           )
    ),
    returned_events AS (
        SELECT
            matching_context.sequence_number,
            matching_context.occurred_at,
            matching_context.event_type,
            matching_context.payload
        FROM matching_context
        WHERE matching_context.sequence_number > min_sequence
    )
    SELECT
        COALESCE(
            jsonb_agg(
                jsonb_build_object(
                    'sequence_number', returned_events.sequence_number,
                    'occurred_at', returned_events.occurred_at,
                    'event_type', returned_events.event_type,
                    'payload', returned_events.payload
                )
                ORDER BY returned_events.sequence_number ASC
            ) FILTER (WHERE returned_events.sequence_number IS NOT NULL),
            '[]'::jsonb
        ) AS event_records,
        MAX(returned_events.sequence_number) AS last_returned_sequence_number,
        actual_context_version AS current_context_version
    FROM returned_events;
END;
$$;
