# Embercue

Embercue is a local macOS 14+ rail for holding AI-work notes and next prompts. It is a native SwiftUI/AppKit implementation informed by the publicly available Copper demo, but uses its own name, assets, copy, and safety boundaries. It has no accounts, analytics, telemetry, AI integration, or background clipboard collection. **Check for Updates…** makes one user-requested GitHub Releases request and opens the public download page only when a newer release exists.

## Use

Open Embercue from its menu-bar Embercue item or `Control-Command-J`. The compact rail groups active cards into ordered sections, with a pinned one-line composer and History in the overflow menu. Enter `# Name` in the composer to create and select a section; other Markdown remains a normal note. Cards support local Markdown display, attachments, leading-circle selection, range selection, Copy, Copy as List, completion, editing, moving, and safe same-section merges. Drag files onto the composer or use its paperclip; files stay in Embercue-owned local storage and attachment-only cards are valid. `Keep Clipboard` reads the clipboard only after you select that command. The single default-off **Enable Double-Shift Capture…** action reads an accessible selection, or sends one guarded Command-C when that selection is unavailable; it captures only a resulting new nonblank plain-text clipboard value. `Copy` and `Copy as List` are explicit clipboard-write actions; neither pastes or submits into another app. Copy as List marks selected cards complete only after a successful combined text/file pasteboard write and then shows `Copied × N`.

`Copy & Return` in the top overflow menu copies the selected cards as plain text, hides Embercue, and reactivates the app that was frontmost before Embercue opened. It runs only after a successful clipboard write and never pastes, submits, or completes a card. Closing the panel, pressing Escape, or choosing Hide to Menu Bar only hides the rail: the menu-bar item, hot key, draft, search, and local library remain alive. Choose `Quit Embercue` from the menu bar or overflow menu to terminate the process.

## Keyboard shortcuts

Copper-compatible bindings are Shift twice (capture selected text after explicit Accessibility enablement), `Command-C` (Copy), `Shift-Command-C` (Copy as List), Space (Mark as Done), Return (Edit), `Command-Return` (Edit in New Window), and `Shift-Command-M` (Merge Notes). Text editing keeps priority: a nonempty NSTextView selection receives native `Command-C`, and Return is never intercepted while a text field or editor is focused. With an empty NSTextView selection, `Command-C` can copy the selected rail cards; NSTextField keeps native copy conservatively. Embercue's `Control-Command-J` is its independent global show shortcut, not a Copper-compatible binding.

## Build and package

```bash
swift package describe
swift test --parallel
swift run EmbercueChecks
swift build -c release
bash scripts/package-app.sh
bash scripts/verify-local.sh
```

The package script writes `dist/Embercue.app`, embeds the exact `swift-markdown`/`swift-cmark` license inventory, and applies an ad-hoc signature by default. Set `SIGN_IDENTITY` only when an approved signing identity is available. The result is not notarized or ready for public distribution.

For a local GUI smoke check of the packaged app, run `make verify-startup-ui`. It launches the app with a temporary isolated data directory and verifies one on-screen, non-transparent 364×640 pt Embercue rail. This check is intentionally not part of `make verify` or non-interactive CI.

This host's Command Line Tools omit both XCTest and Swift Testing. The matching test targets contain conditional XCTest suites that run on a full Xcode host; here `swift test --parallel` compiles the targets but cannot execute framework-backed cases. `EmbercueChecks` is the local executable coverage: validation boundaries, explicit clipboard/copy semantics, rollback, cross-process revision conflict, reload, export, malformed/corrupt/future recovery, recovery-then-mutate, and the data-root override.

## Data and recovery

The live library is `~/Library/Application Support/Embercue/library.json`. Schema v3 adds managed attachment references to v2's durable sections and per-section card order. Attachments are copied to the sibling owner-only `attachments/` directory; source paths are never retained. The first successful mutation of a v1 or v2 library preserves exact prior bytes in an owner-only migration snapshot before the v3 write; merely opening legacy data never rewrites it. Before replacing an existing library, Embercue writes `library.last-known-good.json`; corrupt, malformed, or unsupported primary files and unreadable active backups are preserved under timestamped `*.quarantine-*.json` names before normal backup rotation continues. The in-app export writes JSON metadata only; it does not copy attachment files. A complete manual backup must preserve both `library.json` and the sibling `attachments/` directory together.

## Visual fixture and overlay evidence

The fixture and overlay tools only use isolated absolute paths:

```bash
FIXTURE_ROOT="$(mktemp -d /tmp/embercue-fixture.XXXXXX)/data"
swift run EmbercueChecks --write-visual-fixture "$FIXTURE_ROOT"
ARTIFACT_DIR="$(mktemp -d /tmp/embercue-fidelity.XXXXXX)"
EMBERCUE_QA_APPEARANCE=light bash scripts/capture-fidelity-fixture.sh --launch "$ARTIFACT_DIR/base"
```

`scripts/compose-fidelity-overlays.py` crops a caller-provided reference frame and produces normalized side-by-side, overlay, difference, and geometry-metrics PNGs. It never downloads, modifies, or embeds reference video content.

For a test-only GUI smoke run, do not overwrite an existing store. Set `EMBERCUE_DATA_DIRECTORY` to a dedicated, absolute disposable directory before launching the packaged app, for example `EMBERCUE_DATA_DIRECTORY="$(mktemp -d)/Embercue" dist/Embercue.app/Contents/MacOS/Embercue`. The override is validated as a non-symlink directory; `HOME` is not a supported isolation control.

## Accessibility-selected text capture

Double-Shift capture is off until you choose **Enable Double-Shift Capture…** from the rail's More menu and confirm the consent explanation. Embercue then asks macOS for Accessibility access once and shows **Waiting for Accessibility…** while System Settings is pending. After granting access, return to Embercue; it rechecks authorization and enables double-Shift capture without a restart. Use **Disable Double-Shift Capture** to stop monitoring and clear the saved opt-in.

Embercue remembers only that unified explicit opt-in. A legacy selected-text preference does not enable this feature or synthetic Command-C. A later launch starts capture only when the current build is already trusted, and never prompts for Accessibility on its own. The default package is ad-hoc signed, so rebuilding or repackaging can create a new identity that must be authorized again; use a stable approved signing identity before relying on permission continuity.

## Scope and release boundary

Embercue never monitors or polls the clipboard, auto-pastes, or submits into another app. Double-Shift capture is optional: after its one explicit consent and Accessibility enablement, paired local and global monitors observe modifier-flag transitions and synchronously read the current selection after an uninterrupted double Shift. Only Shift presses count toward the gesture; Command, Option, Control, or Fn cancels it. When that attempt returns exactly “unavailable,” the same consent sends one Command-C to the captured current frontmost non-Embercue app PID, then waits briefly while that PID remains frontmost. It captures only a resulting nonblank plain-text pasteboard count of exactly one; focus loss, a count jump, timeout, or blank result is discarded without reading old clipboard text. It never activates an app, pastes, submits, clears, or restores. Selection resolution tries each focused candidate's direct text, selected range, and full value before moving to a bounded ancestor. The name is provisional and requires clearance before public use. See [architecture](docs/architecture.md), [privacy](PRIVACY.md), and [security](SECURITY.md).
