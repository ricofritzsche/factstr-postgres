# Release Process

This document describes the manual GitHub release process for the `factstr`
PostgreSQL extension.

PGXN publication is not part of the current release process. It is a later step.

## Version Checks

For a release version such as `0.1.1`, verify:

- `META.json` has the release version.
- `README.md` status matches the release version.
- `CHANGELOG.md` contains the release version.

For the PostgreSQL extension SQL version, verify:

- `extension/factstr.control` has the expected `default_version`.
- `extension/factstr--<extension-version>.sql` exists.
- `META.json` `provides.factstr.version` matches the extension SQL version.
- `META.json` `provides.factstr.file` points to the install SQL file.

Packaging-only releases may update the top-level `META.json` version without
changing the PostgreSQL extension SQL version. Do not change
`extension/factstr.control` or add SQL upgrade scripts unless the extension SQL
version changes.

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
git tag v0.1.1
git push origin v0.1.1
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
