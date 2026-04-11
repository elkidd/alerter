# Copilot Instructions for melding

Read this before doing any work on this project.

> ⚠️ Some project-specific details are stored in the **Personal-Memory** skill.

## Recurring gotchas

### 1. Zip structure for Homebrew
The zip MUST have a top-level directory: `melding-X.Y.Z/melding.app/...`
Homebrew auto-`cd`s into the top-level dir — if `melding.app/` is at the root it fails with "No such file or directory".

**Wrong:** `zip -r melding-X.Y.Z.zip melding.app`
**Correct:**
```bash
mkdir melding-X.Y.Z && cp -r melding.app melding-X.Y.Z/ && zip -r melding-X.Y.Z.zip melding-X.Y.Z
```
⚠️ `scripts/release.sh` has this bug — fix the zip step before using the script.

### 2. GitHub CDN caches release assets
Re-uploading the same filename to the same tag does NOT bypass the CDN cache.
- Use a different filename (e.g. `melding-X.Y.Z-2.zip`) and update the formula URL, or
- Delete and recreate the release tag entirely

### 3. Version string
The version in `Sources/Melding/MeldingCommand.swift` must be kept in sync with the git tag manually.
The release script bumps by patch from whatever is in the file — verify it matches the intended version before running.

### 5. Testing notifications
Never use `&` to background melding during testing — the process exits before delivery.
Always run in the foreground and wait for output (`@TIMEOUT`, `@CONTENTCLICKED`, etc.).

### 6. content-image limitations
- Local files only (no URLs)
- macOS **moves** the file on first delivery — re-copy before each test run
- Supported formats: PNG, JPEG, GIF (not ICNS)
- Use `~/test.png` as the scratch test path; avoid `/tmp` and `node_modules` paths
