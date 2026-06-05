\set VERBOSITY terse

DROP EXTENSION IF EXISTS factstr CASCADE;
CREATE EXTENSION factstr;

SELECT count(*) AS appended
FROM factstr.append(
    '[
        {"event_type":"account.created","payload":{"account_id":"acct_1","region":"eu"}},
        {"event_type":"account.credited","payload":{"account_id":"acct_1","amount":10,"region":"eu"}},
        {"event_type":"account.debited","payload":{"account_id":"acct_1","amount":4,"region":"eu"}},
        {"event_type":"account.created","payload":{"account_id":"acct_2","region":"us"}},
        {"event_type":"account.credited","payload":{"account_id":"acct_2","amount":7,"region":"us"}},
        {"event_type":"invoice.created","payload":{"account_id":"acct_1","invoice_id":"inv_1"}}
    ]'::jsonb
);

COPY (
    SELECT sequence_number, event_type, payload
    FROM factstr.query(ARRAY['account.created'])
    ORDER BY sequence_number
) TO STDOUT;

COPY (
    SELECT sequence_number, event_type, payload
    FROM factstr.query(ARRAY['account.credited', 'account.debited'])
    ORDER BY sequence_number
) TO STDOUT;

COPY (
    SELECT sequence_number, event_type, payload
    FROM factstr.query(ARRAY['account.created', 'account.credited', 'account.debited'], '{"account_id":"acct_1"}')
    ORDER BY sequence_number
) TO STDOUT;

COPY (
    SELECT sequence_number, event_type, payload
    FROM factstr.query(ARRAY['account.credited'], '{"region":"us"}')
    ORDER BY sequence_number
) TO STDOUT;

COPY (
    SELECT sequence_number, event_type, payload
    FROM factstr.query(ARRAY['account.created', 'account.credited'], '{}'::jsonb, 5)
    ORDER BY sequence_number
) TO STDOUT;

COPY (
    SELECT sequence_number, event_type, payload
    FROM factstr.query(ARRAY['account.created'], '{}'::jsonb, 3)
    ORDER BY sequence_number
) TO STDOUT;

SELECT factstr.current_context_version(
    ARRAY['account.created', 'account.credited', 'account.debited'],
    '{"account_id":"acct_1"}'
) AS context_version;

COPY (
    SELECT sequence_number, event_type, payload
    FROM factstr.query(
        ARRAY['account.created', 'account.credited', 'account.debited'],
        '{"account_id":"acct_1"}',
        3
    )
    ORDER BY sequence_number
) TO STDOUT;

SELECT factstr.current_context_version(
    ARRAY['account.created', 'account.credited', 'account.debited'],
    '{"account_id":"acct_1"}'
) AS context_version;

SELECT factstr.current_context_version(
    ARRAY['account.created', 'account.credited', 'account.debited'],
    '{"account_id":"acct_2"}'
) AS context_version;

SELECT count(*) AS rows
FROM factstr.query(NULL, '{}'::jsonb);

SELECT count(*) AS rows
FROM factstr.query(ARRAY[]::text[], '{}'::jsonb);

SELECT factstr.current_context_version(NULL, '{}'::jsonb) AS context_version;

SELECT factstr.current_context_version(ARRAY[]::text[], '{}'::jsonb) AS context_version;

COPY (
    SELECT sequence_number, event_type, payload
    FROM factstr.query(ARRAY['account.created'], NULL)
    ORDER BY sequence_number
) TO STDOUT;

COPY (
    SELECT sequence_number, event_type, payload
    FROM factstr.query(ARRAY['account.created'], '{}'::jsonb, -10)
    ORDER BY sequence_number
) TO STDOUT;

SELECT count(*) AS result_rows
FROM factstr.query_result(
    ARRAY['account.created', 'account.credited', 'account.debited'],
    '{"account_id":"acct_1"}',
    1
);

COPY (
    WITH result AS (
        SELECT event_records
        FROM factstr.query_result(
            ARRAY['account.created', 'account.credited', 'account.debited'],
            '{"account_id":"acct_1"}',
            1
        )
    )
    SELECT
        event_record.ordinality,
        event_record.value ->> 'sequence_number',
        event_record.value ->> 'event_type',
        event_record.value -> 'payload',
        event_record.value ? 'occurred_at'
    FROM result,
         jsonb_array_elements(result.event_records) WITH ORDINALITY AS event_record(value, ordinality)
    ORDER BY event_record.ordinality
) TO STDOUT;

SELECT last_returned_sequence_number, current_context_version
FROM factstr.query_result(
    ARRAY['account.created', 'account.credited', 'account.debited'],
    '{"account_id":"acct_1"}',
    1
);

SELECT event_records, last_returned_sequence_number IS NULL AS no_last_returned, current_context_version
FROM factstr.query_result(
    ARRAY['account.created', 'account.credited', 'account.debited'],
    '{"account_id":"acct_1"}',
    3
);

COPY (
    WITH result AS (
        SELECT event_records
        FROM factstr.query_result(ARRAY['account.created'], NULL)
    )
    SELECT
        event_record.ordinality,
        event_record.value ->> 'sequence_number',
        event_record.value ->> 'event_type'
    FROM result,
         jsonb_array_elements(result.event_records) WITH ORDINALITY AS event_record(value, ordinality)
    ORDER BY event_record.ordinality
) TO STDOUT;

SELECT event_records, last_returned_sequence_number IS NULL AS no_last_returned, current_context_version IS NULL AS no_context
FROM factstr.query_result(NULL, '{}'::jsonb);

SELECT event_records, last_returned_sequence_number IS NULL AS no_last_returned, current_context_version IS NULL AS no_context
FROM factstr.query_result(ARRAY[]::text[], '{}'::jsonb);

SELECT event_records, last_returned_sequence_number IS NULL AS no_last_returned, current_context_version IS NULL AS no_context
FROM factstr.query_result(ARRAY['account.missing'], '{}'::jsonb);

SELECT count(*) AS result_rows
FROM factstr.query_result('{}'::jsonb);

SELECT jsonb_array_length(event_records) AS record_count,
       last_returned_sequence_number,
       current_context_version
FROM factstr.query_result('{}'::jsonb);

COPY (
    WITH result AS (
        SELECT event_records
        FROM factstr.query_result('{"filters":[]}'::jsonb)
    )
    SELECT
        event_record.ordinality,
        event_record.value ->> 'sequence_number',
        event_record.value ->> 'event_type'
    FROM result,
         jsonb_array_elements(result.event_records) WITH ORDINALITY AS event_record(value, ordinality)
    ORDER BY event_record.ordinality
) TO STDOUT;

COPY (
    WITH result AS (
        SELECT event_records
        FROM factstr.query_result('{"filters":[{"payload_predicates":[{"region":"eu"}]}]}'::jsonb)
    )
    SELECT
        event_record.ordinality,
        event_record.value ->> 'sequence_number',
        event_record.value ->> 'event_type'
    FROM result,
         jsonb_array_elements(result.event_records) WITH ORDINALITY AS event_record(value, ordinality)
    ORDER BY event_record.ordinality
) TO STDOUT;

COPY (
    WITH result AS (
        SELECT event_records
        FROM factstr.query_result('{"filters":[{"event_types":["account.created"]}]}'::jsonb)
    )
    SELECT
        event_record.ordinality,
        event_record.value ->> 'sequence_number',
        event_record.value ->> 'event_type'
    FROM result,
         jsonb_array_elements(result.event_records) WITH ORDINALITY AS event_record(value, ordinality)
    ORDER BY event_record.ordinality
) TO STDOUT;

COPY (
    WITH result AS (
        SELECT event_records
        FROM factstr.query_result(
            '{
                "filters": [
                    {
                        "event_types": ["account.created"],
                        "payload_predicates": [{"account_id":"acct_2"}]
                    },
                    {
                        "event_types": ["invoice.created"],
                        "payload_predicates": [{"account_id":"acct_1"}]
                    }
                ]
            }'::jsonb
        )
    )
    SELECT
        event_record.ordinality,
        event_record.value ->> 'sequence_number',
        event_record.value ->> 'event_type'
    FROM result,
         jsonb_array_elements(result.event_records) WITH ORDINALITY AS event_record(value, ordinality)
    ORDER BY event_record.ordinality
) TO STDOUT;

COPY (
    WITH result AS (
        SELECT event_records
        FROM factstr.query_result(
            '{
                "filters": [
                    {
                        "event_types": ["account.credited", "account.debited"],
                        "payload_predicates": [{"account_id":"acct_1"}]
                    }
                ]
            }'::jsonb
        )
    )
    SELECT
        event_record.ordinality,
        event_record.value ->> 'sequence_number',
        event_record.value ->> 'event_type'
    FROM result,
         jsonb_array_elements(result.event_records) WITH ORDINALITY AS event_record(value, ordinality)
    ORDER BY event_record.ordinality
) TO STDOUT;

COPY (
    WITH result AS (
        SELECT event_records
        FROM factstr.query_result(
            '{
                "filters": [
                    {
                        "event_types": ["account.created"],
                        "payload_predicates": [{"account_id":"acct_1"}, {"region":"us"}]
                    }
                ]
            }'::jsonb
        )
    )
    SELECT
        event_record.ordinality,
        event_record.value ->> 'sequence_number',
        event_record.value ->> 'event_type',
        event_record.value -> 'payload'
    FROM result,
         jsonb_array_elements(result.event_records) WITH ORDINALITY AS event_record(value, ordinality)
    ORDER BY event_record.ordinality
) TO STDOUT;

COPY (
    WITH result AS (
        SELECT event_records
        FROM factstr.query_result(
            '{
                "filters": [
                    {
                        "event_types": ["account.credited"],
                        "payload_predicates": [{"region":"us"}]
                    }
                ]
            }'::jsonb
        )
    )
    SELECT
        event_record.ordinality,
        event_record.value ->> 'sequence_number',
        event_record.value ->> 'event_type',
        event_record.value -> 'payload'
    FROM result,
         jsonb_array_elements(result.event_records) WITH ORDINALITY AS event_record(value, ordinality)
    ORDER BY event_record.ordinality
) TO STDOUT;

SELECT event_records, last_returned_sequence_number IS NULL AS no_last_returned, current_context_version IS NULL AS no_context
FROM factstr.query_result('{"filters":[{"event_types":[]}]}'::jsonb);

SELECT event_records, last_returned_sequence_number IS NULL AS no_last_returned, current_context_version IS NULL AS no_context
FROM factstr.query_result('{"filters":[{"payload_predicates":[]}]}'::jsonb);

SELECT last_returned_sequence_number, current_context_version
FROM factstr.query_result('{"filters": [], "min_sequence_number": 3}'::jsonb);

COPY (
    WITH result AS (
        SELECT event_records
        FROM factstr.query_result('{"filters": [], "min_sequence_number": 3}'::jsonb)
    )
    SELECT
        event_record.ordinality,
        event_record.value ->> 'sequence_number',
        event_record.value ->> 'event_type',
        event_record.value ? 'occurred_at'
    FROM result,
         jsonb_array_elements(result.event_records) WITH ORDINALITY AS event_record(value, ordinality)
    ORDER BY event_record.ordinality
) TO STDOUT;

SELECT event_records, last_returned_sequence_number IS NULL AS no_last_returned, current_context_version
FROM factstr.query_result(
    '{
        "filters": [
            {
                "event_types": ["account.created", "account.credited", "account.debited"],
                "payload_predicates": [{"account_id":"acct_1"}]
            }
        ],
        "min_sequence_number": 3
    }'::jsonb
);

SELECT event_records, last_returned_sequence_number IS NULL AS no_last_returned, current_context_version IS NULL AS no_context
FROM factstr.query_result('{"filters":[{"event_types":["account.missing"]}]}'::jsonb);

SELECT factstr.query_result('[]'::jsonb);
SELECT factstr.query_result('{"filters":{}}'::jsonb);
SELECT factstr.query_result('{"filters":[[]]}'::jsonb);
SELECT factstr.query_result('{"filters":[{"event_types":"account.created"}]}'::jsonb);
SELECT factstr.query_result('{"filters":[{"event_types":[""]}]}'::jsonb);
SELECT factstr.query_result('{"filters":[{"event_types":[1]}]}'::jsonb);
SELECT factstr.query_result('{"filters":[{"payload_predicates":{}}]}'::jsonb);
SELECT factstr.query_result('{"filters":[{"payload_predicates":[[]]}]}'::jsonb);
SELECT factstr.query_result('{"min_sequence_number":1.5}'::jsonb);
SELECT factstr.query_result('{"min_sequence_number":-1}'::jsonb);
