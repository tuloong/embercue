# Security

Please report a suspected vulnerability privately to the maintainer who supplied this repository; do not include library contents, exported data, or credentials in a public issue.

This source build is local-only. It uses atomic JSON replacement, a last-known-good backup, and quarantine for unreadable or future-schema primary files. Exported JSON is intentionally readable and should be stored where its contents are appropriate.

The ad-hoc signature produced by `scripts/package-app.sh` is for local validation only. A public distribution requires an approved Developer ID identity, hardened runtime, notarization, stapling, Gatekeeper assessment, and clean-machine verification.
