# Embercue initial repository audit

Date: 2026-08-01 (Asia/Shanghai)

Branch: `main`

Decision: approved as a local, ad-hoc macOS MVP; not approved for public distribution.

## Scope reviewed

This audit covers the complete initial Embercue repository: the native SwiftUI/AppKit application, domain and persistence layers, global hot-key and menu-bar adapters, clipboard boundary, executable behavior checks, conditional XCTest suites, packaging scripts, CI, privacy/security documentation, research, and the packaged local application.

The product boundary is intentionally narrow: plain-text prompts and keeps, a queue/history workflow, explicit copy and completion actions, local versioned JSON, export, and recovery. It includes no account, sync, network client, telemetry, updater, Accessibility permission, synthetic paste, or background clipboard collection.

## Independent gates

| Gate | Result | Evidence |
| --- | --- | --- |
| Independent QA | PASS for runnable local scope | `docs/verification.md`; fresh durable-recovery artifacts under `/tmp/embercue-qa-durable-final.cMMHet/` |
| Code-quality review | APPROVE; no actionable findings | `.omo/evidence/embercue-macos-mvp-code-review.md` |
| Security review | APPROVE for local ad-hoc MVP; no P1/P2 | Final read-only security review, 2026-08-01 |
| Root verification | PASS | Commands in the matrix below |

## Resolved review history

- Lost-update risk was closed with an on-disk revision check performed under a cross-process file lock.
- Missing-primary recovery now restores a valid last-known-good backup before returning live state.
- Corrupt, unsupported, oversized, and symlinked managed files are not silently treated as valid data.
- Unreadable primary and backup data are renamed to unique quarantine files and kept at mode `0600`; later backup rotation cannot overwrite those retained bytes.
- Recovery is tested through two subsequent mutations and relaunch, proving a valid revision-1 active backup and revision-2 primary.
- Revision values below zero, duplicate identifiers, invalid state combinations, oversized items/documents, and `Int.max` overflow are rejected.
- Export is serialized by the repository lock and rejects direct, normalized, parent-normalized, and symlink-resolved aliases of the primary, backup, and lock files.
- Reads, lock creation, and temporary writes use no-follow descriptors and regular-file checks. Temporary files are exclusive, mode `0600`, fully written, synchronized, and atomically renamed.
- Clipboard writes are checked for success. Copying never marks an item complete, and `Copy & Return` never claims to paste or submit.
- Hot-key registration failure retains the menu-bar fallback; foreground-app tracking is one-shot and is not persisted.
- Packaging now validates exact icon raster sizes and produces a self-contained, strictly verifiable ad-hoc app bundle.

## Verification matrix

| Command or scenario | Result | Proof boundary |
| --- | --- | --- |
| `swift package describe` | PASS | Package topology and no external package dependencies |
| `swift test --parallel` | PASS at build level | Conditional XCTest targets compile; this Command Line Tools host cannot execute XCTest |
| `swift run EmbercueChecks` | PASS | Domain, adapter, clipboard, recovery, file-safety, export, overflow, permissions, and concurrent-writer behavior |
| `swift build -c release` | PASS | Release compilation |
| `bash scripts/package-app.sh` | PASS | Deterministic local `.app` construction and ad-hoc signing |
| `bash scripts/verify-local.sh` | PASS | Bundle, executable checks, current static privacy guard, and positive probes |
| `plutil -lint dist/Embercue.app/Contents/Info.plist` | PASS | Bundle metadata syntax |
| `codesign --verify --strict --verbose=4 dist/Embercue.app` | PASS | Local ad-hoc signature integrity only |
| `git diff --check` | PASS | Patch hygiene before staging |
| Focused durable-recovery harness | PASS | First launch, valid-backup restore, single and dual quarantine, byte/mode retention, two mutations, and relaunch |
| Isolated and copied-bundle process smoke runs | PASS | Process startup, bundle self-containment, and disposable data-root isolation |

## Non-blocking hardening backlog

The security approval records three low-priority gaps that do not change the local-MVP decision:

1. `scripts/verify-local.sh` is a regression tripwire, not a complete static analyzer. Future changes should expand it to realistic Network, Accessibility, and synthetic-input spellings and stronger ownership checks for clipboard access.
2. The repository is hardened against symlink substitution at final file nodes, but the root-directory path still has same-account TOCTOU limits. A future implementation may use a root directory descriptor with `openat`/`fstatat`/`renameat` and nonblocking handling for special files.
3. Files are synchronized before rename, but the parent directory is not synchronized after rename or quarantine. A public-release durability pass should add directory `fsync` and fault-injection evidence.

The `0700` directory and `0600` files isolate other ordinary Unix users; they are not encryption and do not defend against another malicious process running as the same macOS account, root, backups, or a user-selected export destination.

## Evidence limits and release gate

- The desktop was locked during attempted interactive GUI automation. No bypass was attempted. Composer, history, menu/hot-key invocation, clipboard interaction, VoiceOver, Full Keyboard Access, multiple displays, Spaces, Stage Manager, and clean macOS 14 behavior therefore remain unverified at the real GUI surface.
- The build host has Command Line Tools rather than full Xcode, so framework-backed XCTest cases compiled but did not execute. Equivalent behaviors were exercised by `EmbercueChecks` and focused harnesses.
- The bundle is ad-hoc signed. It has not passed Developer ID signing, hardened runtime, notarization, stapling, Gatekeeper assessment for a downloaded artifact, or clean-machine installation.
- `Embercue` is a provisional product name. Public use still requires professional trademark, App Store, domain, and market clearance.
- No Git remote was configured and no code was pushed.

## Final recommendation

The repository is suitable for local evaluation and further product discovery. Public distribution remains blocked until the GUI/accessibility matrix, full-Xcode tests, name clearance, signing/notarization pipeline, and documented security hardening are completed with fresh evidence.
