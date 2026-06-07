# FACTSTR PostgreSQL

FACTSTR PostgreSQL is a PostgreSQL extension that provides FACTSTR event storage
and command context consistency inside PostgreSQL.

## Status

The current extension version is `0.1.0`.

This extension is not yet published to PGXN. Install it from source.

## What It Provides

- PostgreSQL-native FACTSTR event storage
- Gapless committed sequence numbers
- JSONB event payloads
- JSON EventQuery based querying
- Conditional append for command context consistency

## Requirements

- PostgreSQL
- `pg_config` from the target PostgreSQL installation
- PostgreSQL server development package for PGXS builds

## Installation From Source

The extension files are in [`extension/`](extension/).

```bash
cd extension
make
make install
```

Then enable the extension in a database:

```sql
CREATE EXTENSION factstr;
```

If `pg_config` on `PATH` does not point to the target PostgreSQL installation,
pass it explicitly:

```bash
make PG_CONFIG=/path/to/pg_config install
```

## Running Tests

Regression tests are under [`extension/sql/`](extension/sql/) and
[`extension/expected/`](extension/expected/).

```bash
cd extension
make installcheck
```

If needed, pass the target PostgreSQL connection settings:

```bash
make installcheck PGHOST=localhost PGPORT=5432 PGUSER=postgres
```

The GitHub Actions workflow also runs the extension regression tests.

## API

### `factstr.append(events jsonb)`

Appends one or more events as a single committed batch.

Each event must be a JSON object with:

- `event_type`: non-empty string
- `payload`: JSON object

The function returns the inserted event records with assigned
`sequence_number` values.

### `factstr.query(event_query jsonb)`

Runs a JSON EventQuery and returns exactly one row with:

- `event_records jsonb`
- `last_returned_sequence_number bigint`
- `current_context_version bigint`

`event_records` is a JSON array ordered by `sequence_number ASC`.
`last_returned_sequence_number` describes the returned records.
`current_context_version` describes the full matching context and ignores
`min_sequence_number`.

### `factstr.append_if(events jsonb, context_query jsonb, expected_context_version bigint)`

Conditionally appends events using a JSON EventQuery as the command context.

The function locks the metadata row, computes the current context version,
compares it with `expected_context_version`, and appends only when they match.
On conflict, it commits no events and consumes no sequence numbers.

### Internal Helper

```sql
factstr._current_context_version(event_query jsonb)
```

This function is used internally by the extension implementation. It is not a
public API.

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
FROM factstr.query(
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

## Versioning

`0.1.0` is the first extension version.

## License

Licensed under either the MIT license or Apache License, Version 2.0, at your
option.
