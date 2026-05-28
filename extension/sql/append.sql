\set VERBOSITY terse

CREATE EXTENSION factstr;

SELECT count(*) AS appended
FROM factstr.append(
    '[{"event_type":"account.created","payload":{"account_id":"acct_1"}}]'::jsonb
);

SELECT count(*) AS appended
FROM factstr.append(
    '[
        {"event_type":"account.credited","payload":{"account_id":"acct_1","amount":10}},
        {"event_type":"account.debited","payload":{"account_id":"acct_1","amount":4}}
    ]'::jsonb
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

SELECT factstr.append('{"event_type":"not-an-array","payload":{}}'::jsonb);
SELECT factstr.append('[]'::jsonb);
SELECT factstr.append('[{"payload":{}}]'::jsonb);
SELECT factstr.append('[{"event_type":"","payload":{}}]'::jsonb);
SELECT factstr.append('[{"event_type":"missing.payload"}]'::jsonb);
SELECT factstr.append('[{"event_type":"bad.payload","payload":[]}]'::jsonb);
