# FACTSTR PostgreSQL

## Purpose

FACTSTR PostgreSQL provides a PostgreSQL-native runtime for FACTSTR event storage and command context consistency.

The extension provides FACTSTR semantics inside PostgreSQL. It includes a
convenience API for simple single-filter SQL usage and a contract API based on
JSON EventQuery. JSON EventQuery is the preferred long-term API shape; the
single-filter functions remain useful for direct SQL inspection and simple
queries.

## Current API

Convenience API:

```sql
factstr.append(events jsonb)
factstr.query(event_types text[], payload_predicates jsonb, min_sequence_number bigint)
factstr.query_result(event_types text[], payload_predicates jsonb, min_sequence_number bigint)
factstr.current_context_version(event_types text[], payload_predicates jsonb)
factstr.append_if(events jsonb, context_event_types text[], context_payload_predicates jsonb, expected_context_version bigint)
```

Contract API:

```sql
factstr.query_result(event_query jsonb)
factstr.append_if(events jsonb, context_query jsonb, expected_context_version bigint)
```

Internal helper:

```sql
factstr._current_context_version(event_query jsonb)
```

The internal helper is used by the extension implementation and is not intended
as the public API.

## JSON EventQuery

```json
{
  "filters": [
    {
      "event_types": ["account.created", "account.credited"],
      "payload_predicates": [
        { "account_id": "acct_1" },
        { "region": "eu" }
      ]
    }
  ],
  "min_sequence_number": 3
}
```

Semantics:

- `filters` omitted or `[]` means all records.
- Filters are OR.
- `event_types` omitted means unconstrained.
- `event_types: []` means no event type match.
- `payload_predicates` omitted means unconstrained.
- `payload_predicates: []` means no payload match.
- Payload predicates are OR.
- Event type and payload predicates inside one filter are AND.
- `min_sequence_number` is exclusive.
- `min_sequence_number` affects returned records only.
- `current_context_version` ignores `min_sequence_number`.

## Query Result

```sql
factstr.query_result(event_query jsonb)
```

Returns exactly one row with:

- `event_records`
- `last_returned_sequence_number`
- `current_context_version`

`event_records` is ordered by `sequence_number ASC`.
`last_returned_sequence_number` describes the returned records.
`current_context_version` describes the full matching context and ignores
`min_sequence_number`.

## Conditional Append

```sql
factstr.append_if(events jsonb, context_query jsonb, expected_context_version bigint)
```

Uses the full JSON EventQuery as the command context. It locks the metadata row,
computes the current context version, compares it to `expected_context_version`,
and appends only if the versions match. A conflict commits no events and
consumes no sequence numbers.

## Minimal Examples

```sql
CREATE EXTENSION factstr;
```

```sql
SELECT *
FROM factstr.append(
  '[{"event_type":"account.created","payload":{"account_id":"acct_1"}}]'::jsonb
);
```

```sql
SELECT *
FROM factstr.query_result(
  '{
    "filters": [
      {
        "event_types": ["account.created", "account.credited"],
        "payload_predicates": [{ "account_id": "acct_1" }]
      }
    ],
    "min_sequence_number": 0
  }'::jsonb
);
```

```sql
SELECT *
FROM factstr.append_if(
  '[{"event_type":"account.credited","payload":{"account_id":"acct_1","amount":100}}]'::jsonb,
  '{
    "filters": [
      {
        "event_types": ["account.created", "account.credited"],
        "payload_predicates": [{ "account_id": "acct_1" }]
      }
    ]
  }'::jsonb,
  1
);
```

## License

Licensed under either of Apache License, Version 2.0 or MIT license at your option.
