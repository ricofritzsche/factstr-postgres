# Changelog

All notable changes to this project are documented in this file.

The format follows Keep a Changelog, and this project uses extension versions
for releases.

## [Unreleased]

No unreleased changes yet.

## [0.1.2] - 2026-06-07

### Added

- Root `Makefile` for PGXN package checks.

### Changed

- No SQL API changes.
- No extension behavior changes.

## [0.1.1] - 2026-06-07

### Added

- PGXN `META.json` metadata.

### Changed

- No SQL API changes.
- No extension behavior changes.

## [0.1.0] - 2026-06-07

### Added

- PostgreSQL extension packaging for `factstr`.
- `factstr.append(events jsonb)` for appending event batches.
- `factstr.query(event_query jsonb)` for querying events with JSON EventQuery.
- `factstr.append_if(events jsonb, context_query jsonb, expected_context_version bigint)` for conditional append.
- Internal `factstr._current_context_version(event_query jsonb)` helper for context version calculation.
- PostgreSQL regression tests under `extension/sql` and `extension/expected`.
