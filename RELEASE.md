# Release Process

This document describes the manual GitHub release process for the `factstr`
PostgreSQL extension.

PGXN publication is not part of the current release process. It is a later step.

## Version Checks

For a release version such as `0.1.0`, verify:

- `extension/factstr.control` has `default_version = '0.1.0'`.
- `extension/factstr--0.1.0.sql` exists.
- `README.md` status matches `0.1.0`.
- `CHANGELOG.md` contains `0.1.0`.

## Local Verification

Run the extension build and regression tests:

```bash
cd extension
make
make install
make installcheck
```

Verify extension creation in a PostgreSQL database:

```sql
CREATE EXTENSION factstr;
```

## Git Tag

Check the working tree:

```bash
git status
```

Create and push the release tag:

```bash
git tag v0.1.0
git push origin v0.1.0
```

## GitHub Release Notes

Create a GitHub Release for the pushed tag.

Include:

- Summary
- Changes
- Installation
- Upgrade notes
- Known limitations

Keep release notes specific to the extension version being released.
