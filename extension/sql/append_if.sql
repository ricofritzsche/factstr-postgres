\set VERBOSITY terse

DROP EXTENSION IF EXISTS factstr CASCADE;
CREATE EXTENSION factstr;

SELECT count(*) AS appended
FROM factstr.append(
    '[{"event_type":"tool.configured","payload":{"tool_id":"t-123","mode":"fast"}}]'::jsonb
);

SELECT factstr.current_context_version(
    ARRAY['tool.configured', 'tool.used'],
    '{"tool_id":"t-123"}'
) AS context_version;

SELECT count(*) AS appended
FROM factstr.append(
    '[{"event_type":"other.happened","payload":{"other_id":"o-1"}}]'::jsonb
);

SELECT factstr.current_context_version(
    ARRAY['tool.configured', 'tool.used'],
    '{"tool_id":"t-123"}'
) AS context_version;

COPY (
    SELECT sequence_number, event_type, payload
    FROM factstr.append_if(
        '[{"event_type":"tool.used","payload":{"tool_id":"t-123","user_id":"u-1"}}]'::jsonb,
        ARRAY['tool.configured', 'tool.used'],
        '{"tool_id":"t-123"}',
        1
    )
    ORDER BY sequence_number
) TO STDOUT;

COPY (
    SELECT current_sequence_number
    FROM factstr.metadata
) TO STDOUT;

SELECT factstr.append_if(
    '[{"event_type":"tool.used","payload":{"tool_id":"t-123","user_id":"u-2"}}]'::jsonb,
    ARRAY['tool.configured', 'tool.used'],
    '{"tool_id":"t-123"}',
    1
);

COPY (
    SELECT sequence_number, event_type, payload
    FROM factstr.events
    ORDER BY sequence_number
) TO STDOUT;

COPY (
    SELECT current_sequence_number
    FROM factstr.metadata
) TO STDOUT;

SELECT count(*) AS appended
FROM factstr.append(
    '[{"event_type":"other.happened","payload":{"other_id":"o-2"}}]'::jsonb
);

SELECT factstr.current_context_version(
    ARRAY['tool.configured', 'tool.used'],
    '{"tool_id":"t-123"}'
) AS context_version;

COPY (
    SELECT sequence_number, event_type, payload
    FROM factstr.append_if(
        '[{"event_type":"tool.used","payload":{"tool_id":"t-123","user_id":"u-3"}}]'::jsonb,
        ARRAY['tool.configured', 'tool.used'],
        '{"tool_id":"t-123"}',
        3
    )
    ORDER BY sequence_number
) TO STDOUT;

COPY (
    SELECT sequence_number, event_type, payload
    FROM factstr.append_if(
        '[{"event_type":"audit.logged","payload":{"scope":"all"}}]'::jsonb,
        ARRAY['audit.logged'],
        NULL,
        0
    )
    ORDER BY sequence_number
) TO STDOUT;

COPY (
    SELECT sequence_number, event_type, payload
    FROM factstr.append_if(
        '[{"event_type":"empty.context.null","payload":{"ok":true}}]'::jsonb,
        NULL,
        '{"ignored":true}',
        0
    )
    ORDER BY sequence_number
) TO STDOUT;

COPY (
    SELECT sequence_number, event_type, payload
    FROM factstr.append_if(
        '[{"event_type":"empty.context.array","payload":{"ok":true}}]'::jsonb,
        ARRAY[]::text[],
        '{"ignored":true}',
        0
    )
    ORDER BY sequence_number
) TO STDOUT;

SELECT factstr.append_if(
    '[{"event_type":"bad.version","payload":{}}]'::jsonb,
    ARRAY['bad.version'],
    '{}'::jsonb,
    NULL
);

SELECT factstr.append_if(
    '[{"event_type":"bad.version","payload":{}}]'::jsonb,
    ARRAY['bad.version'],
    '{}'::jsonb,
    -1
);

SELECT factstr.append_if('{"event_type":"not-array","payload":{}}'::jsonb, ARRAY['bad.event'], '{}'::jsonb, 0);
SELECT factstr.append_if('[]'::jsonb, ARRAY['bad.event'], '{}'::jsonb, 0);
SELECT factstr.append_if('[{"payload":{}}]'::jsonb, ARRAY['bad.event'], '{}'::jsonb, 0);
SELECT factstr.append_if('[{"event_type":"","payload":{}}]'::jsonb, ARRAY['bad.event'], '{}'::jsonb, 0);
SELECT factstr.append_if('[{"event_type":"missing.payload"}]'::jsonb, ARRAY['bad.event'], '{}'::jsonb, 0);
SELECT factstr.append_if('[{"event_type":"bad.payload","payload":[]}]'::jsonb, ARRAY['bad.event'], '{}'::jsonb, 0);

COPY (
    SELECT sequence_number, event_type, payload
    FROM factstr.append_if(
        '[{"event_type":"json.tool.used","payload":{"tool_id":"t-123","user_id":"u-4"}}]'::jsonb,
        '{
            "filters": [
                {
                    "event_types": ["tool.configured", "tool.used", "json.tool.used"],
                    "payload_predicates": [{"tool_id":"t-123"}]
                }
            ]
        }'::jsonb,
        5
    )
    ORDER BY sequence_number
) TO STDOUT;

COPY (
    SELECT current_sequence_number
    FROM factstr.metadata
) TO STDOUT;

SELECT factstr.append_if(
    '[{"event_type":"json.tool.used","payload":{"tool_id":"t-123","user_id":"u-5"}}]'::jsonb,
    '{
        "filters": [
            {
                "event_types": ["tool.configured", "tool.used", "json.tool.used"],
                "payload_predicates": [{"tool_id":"t-123"}]
            }
        ]
    }'::jsonb,
    5
);

COPY (
    SELECT sequence_number, event_type, payload
    FROM factstr.events
    WHERE event_type = 'json.tool.used'
    ORDER BY sequence_number
) TO STDOUT;

COPY (
    SELECT current_sequence_number
    FROM factstr.metadata
) TO STDOUT;

COPY (
    SELECT sequence_number, event_type, payload
    FROM factstr.append_if(
        '[{"event_type":"json.tool.used","payload":{"tool_id":"t-123","user_id":"u-6"}}]'::jsonb,
        '{
            "filters": [
                {
                    "event_types": ["tool.configured", "tool.used", "json.tool.used"],
                    "payload_predicates": [{"tool_id":"t-123"}]
                }
            ],
            "min_sequence_number": 9
        }'::jsonb,
        9
    )
    ORDER BY sequence_number
) TO STDOUT;

COPY (
    SELECT sequence_number, event_type, payload
    FROM factstr.append_if(
        '[{"event_type":"json.full.omitted","payload":{"ok":true}}]'::jsonb,
        '{}'::jsonb,
        10
    )
    ORDER BY sequence_number
) TO STDOUT;

COPY (
    SELECT sequence_number, event_type, payload
    FROM factstr.append_if(
        '[{"event_type":"json.full.empty","payload":{"ok":true}}]'::jsonb,
        '{"filters":[]}'::jsonb,
        11
    )
    ORDER BY sequence_number
) TO STDOUT;

COPY (
    SELECT sequence_number, event_type, payload
    FROM factstr.append_if(
        '[{"event_type":"json.or.filters","payload":{"ok":true}}]'::jsonb,
        '{
            "filters": [
                {"event_types": ["audit.logged"]},
                {"event_types": ["empty.context.array"]}
            ]
        }'::jsonb,
        8
    )
    ORDER BY sequence_number
) TO STDOUT;

COPY (
    SELECT sequence_number, event_type, payload
    FROM factstr.append_if(
        '[{"event_type":"json.or.event_types","payload":{"ok":true}}]'::jsonb,
        '{
            "filters": [
                {"event_types": ["tool.configured", "json.full.omitted"]}
            ]
        }'::jsonb,
        11
    )
    ORDER BY sequence_number
) TO STDOUT;

COPY (
    SELECT sequence_number, event_type, payload
    FROM factstr.append_if(
        '[{"event_type":"json.or.payloads","payload":{"ok":true}}]'::jsonb,
        '{
            "filters": [
                {
                    "event_types": ["other.happened"],
                    "payload_predicates": [{"other_id":"o-1"}, {"other_id":"o-2"}]
                }
            ]
        }'::jsonb,
        4
    )
    ORDER BY sequence_number
) TO STDOUT;

COPY (
    SELECT sequence_number, event_type, payload
    FROM factstr.append_if(
        '[{"event_type":"json.and.filter","payload":{"ok":true}}]'::jsonb,
        '{
            "filters": [
                {
                    "event_types": ["other.happened"],
                    "payload_predicates": [{"other_id":"o-2"}]
                }
            ]
        }'::jsonb,
        4
    )
    ORDER BY sequence_number
) TO STDOUT;

COPY (
    SELECT sequence_number, event_type, payload
    FROM factstr.append_if(
        '[{"event_type":"json.empty.event_types","payload":{"ok":true}}]'::jsonb,
        '{"filters":[{"event_types":[]}]}'::jsonb,
        0
    )
    ORDER BY sequence_number
) TO STDOUT;

COPY (
    SELECT sequence_number, event_type, payload
    FROM factstr.append_if(
        '[{"event_type":"json.empty.payload_predicates","payload":{"ok":true}}]'::jsonb,
        '{"filters":[{"payload_predicates":[]}]}'::jsonb,
        0
    )
    ORDER BY sequence_number
) TO STDOUT;

COPY (
    SELECT sequence_number, event_type, payload
    FROM factstr.append_if(
        '[{"event_type":"json.selected","payload":{"selected_id":"s-1"}}]'::jsonb,
        '{"filters":[{"event_types":["json.selected"],"payload_predicates":[{"selected_id":"s-1"}]}]}'::jsonb,
        0
    )
    ORDER BY sequence_number
) TO STDOUT;

COPY (
    SELECT count(*)
    FROM factstr.append(
        '[{"event_type":"json.unrelated","payload":{"selected_id":"s-1"}}]'::jsonb
    )
) TO STDOUT;

COPY (
    SELECT sequence_number, event_type, payload
    FROM factstr.append_if(
        '[{"event_type":"json.selected","payload":{"selected_id":"s-1","step":2}}]'::jsonb,
        '{"filters":[{"event_types":["json.selected"],"payload_predicates":[{"selected_id":"s-1"}]}]}'::jsonb,
        19
    )
    ORDER BY sequence_number
) TO STDOUT;

SELECT factstr.append_if(
    '[{"event_type":"json.bad.context","payload":{}}]'::jsonb,
    '[]'::jsonb,
    0
);

SELECT factstr.append_if(
    '[{"event_type":"json.bad.version","payload":{}}]'::jsonb,
    '{}'::jsonb,
    NULL
);

SELECT factstr.append_if(
    '[{"event_type":"json.bad.version","payload":{}}]'::jsonb,
    '{}'::jsonb,
    -1
);

SELECT factstr.append_if('{"event_type":"not-array","payload":{}}'::jsonb, '{}'::jsonb, 0);
SELECT factstr.append_if('[]'::jsonb, '{}'::jsonb, 0);
SELECT factstr.append_if('[{"payload":{}}]'::jsonb, '{}'::jsonb, 0);
SELECT factstr.append_if('[{"event_type":"","payload":{}}]'::jsonb, '{}'::jsonb, 0);
SELECT factstr.append_if('[{"event_type":"missing.payload"}]'::jsonb, '{}'::jsonb, 0);
SELECT factstr.append_if('[{"event_type":"bad.payload","payload":[]}]'::jsonb, '{}'::jsonb, 0);
