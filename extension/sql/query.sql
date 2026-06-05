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
