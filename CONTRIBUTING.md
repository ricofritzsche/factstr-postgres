# Contributing

## Local Setup

```bash
cd extension
make
make install
make installcheck
```

Use the `pg_config` for the PostgreSQL installation you are testing against.

## SQL API Changes

Changes to the SQL API must include PostgreSQL regression tests under
`extension/sql` and `extension/expected`.

Public API changes must be documented in `README.md`.

Internal helper functions are not public API unless they are explicitly
documented as public.

## Version Changes

Extension version changes must update:

- `extension/factstr.control`
- `extension/factstr--<version>.sql` or upgrade scripts
- `README.md`
- `CHANGELOG.md`
