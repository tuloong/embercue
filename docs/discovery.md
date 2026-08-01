# Embercue Discovery Report

- Date: 2026-08-01 (Asia/Shanghai)
- Lifecycle path: deep
- Risk tier: R2 for a future distributed desktop app; local source and ad-hoc build work remains reversible
- Evidence baseline: [`research/public-product-and-platform-evidence.md`](research/public-product-and-platform-evidence.md)

## Task and named seam

Create a new native macOS repository under the independent provisional brand **Embercue**. The product should let someone capture text worth keeping, queue prompts for later AI-assisted work, copy a queued prompt back to another app, and explicitly mark work complete. Its retained content must remain local, require no account, and avoid analytics, telemetry, AI APIs, and background clipboard collection.

The first implementation seam is a SwiftUI workbench hosted in a small AppKit panel, backed by a versioned JSON repository in Application Support and opened through a registered global hot key or menu-bar item.

## Known Knowns

- The user supplied Copper's complete launch description as the product-problem reference. The first-party Copper page independently supports the high-level capture, queue, copy, and check-off workflow. Evidence: `docs/research/public-product-and-platform-evidence.md`, sections 2 and 3.
- Copper's implementation, source, assets, data format, and exact interface are not public inputs to this repository. Embercue must independently define its terminology, layout, copy, icon, storage, and behavior. Evidence: research section 5.
- Apple documents the general pasteboard as a shared system facility that can participate in Universal Clipboard. A truthful promise is therefore “no Embercue sync or network service,” not “copied text can never leave this Mac.” Evidence: research section 4.4.
- Apple requires a Developer ID signature, hardened runtime, and notarization for a normal direct public distribution. The current host has no valid code-signing identity. Evidence: research section 4.9 and `security find-identity -v -p codesigning` returning zero identities.
- The current host provides Apple Swift 6.2.3 and a macOS SDK through Command Line Tools. SwiftUI, AppKit, Carbon hot-key APIs, `codesign`, `iconutil`, `sips`, and `plutil` are available. Full Xcode is not installed or selected.
- `Embercue` has no exact public software/package collision found in the bounded pass, but `embercue.com` is registered and USPTO/App Store clearance was incomplete. The name is internal/provisional only. Evidence: research section 6.
- The target directory contains only the research and discovery documents and is not yet a Git repository.

## Known Unknowns

- Developer ID, notarization, stapling, and Gatekeeper behavior cannot be verified without the user's Apple signing authority and full release toolchain. This blocks public-release claims, not local development.
- A clean macOS 14 host is unavailable, so the minimum deployment target can be compiled but not exercised here.
- Multiple-display, Spaces, Stage Manager, and other-app full-screen behavior need a packaged GUI scenario; automation can cover only the currently available host.
- VoiceOver and Full Keyboard Access require manual runtime evidence after a usable build exists.
- Trademark and domain clearance require a separate professional/release decision.

## Unknown Knowns

- “Works with all AI apps, terminals and browsers” is best treated as a plain-text interoperability promise. The safe common denominator is explicit copy/paste, not app-specific integrations or synthetic submission.
- “Local and private” implies more than no server: no continuous clipboard polling, no source-app history, no payload logs, an inspectable storage location, and recoverable export.
- A capture tool that interrupts current work fails its main job even if feature-complete. The global shortcut must focus a compact composer, and all common actions must remain keyboard reachable.
- Copying a prompt does not prove that another app accepted it, and it must never implicitly mark the prompt done.

## Unknown Unknowns / blindspots

- Another process or a second Embercue instance could race a whole-file JSON save. The application needs single-instance behavior or revision conflict detection before multi-process editing is supported.
- A crash or disk-full condition during save could otherwise lose the latest content. Atomic replacement, a last-known-good backup, visible save failure, and corruption quarantine are required.
- Very large text or libraries can make whole-document JSON rewrites and SwiftUI rendering slow. The first release needs explicit text-size limits and a repository boundary that permits later storage replacement.
- Hot-key collisions and international keyboard layouts can make a default binding unavailable. Registration failure must be visible and the menu-bar route must remain usable.
- Explicit writes to the general pasteboard can overwrite user clipboard content and may sync through Universal Clipboard. Embercue must name this behavior and must not attempt racy background restoration.

## Risk ranking

- P0: none for a local, unpublished repository using the safe defaults below.
- P1: durable-save correctness; shortcut registration failure; false “sent/completed” state; silent clipboard reads; public release without signing/notarization; public use of an uncleared brand.
- P2: visual polish, configurable shortcut UI, multi-display anchoring, scale beyond the documented personal-library limit.

## Discovery handoff

### Confirmed constraints

- Native macOS 14+ implementation using system frameworks and no third-party runtime dependencies.
- No Copper code, assets, screenshots, exact copy, iconography, or trade dress.
- No account, sync, network client, analytics, updater, telemetry, crash upload, AI call, background clipboard monitoring, synthetic paste, or automatic prompt submission.
- Clipboard reads and writes occur only after a named user action.
- Copy and completion remain separate state transitions.
- Store content in `~/Library/Application Support/Embercue/` through a versioned, atomic local repository.
- Preserve corrupt or unsupported files and expose recovery rather than silently overwriting them.

### Assumptions and safe defaults

- One global prompt queue and one keep library are enough for v0.1; named projects/runs and tags are deferred.
- A floating, resizable right-edge panel plus a menu-bar item is the primary shell.
- A register-only Carbon hot key opens the panel without Accessibility permission.
- “Copy & Return” writes plain text to the pasteboard and reactivates the previously frontmost app; the user pastes manually.
- The initial UI is English, uses native controls, and documents keyboard access.
- Swift Package Manager is the source/build format; a deterministic script creates a local `.app` bundle because full Xcode is unavailable.

### Unresolved blockers

- None for implementation and local verification.
- Public branding is blocked on name clearance.
- Public distribution is blocked on Developer ID signing, hardened-runtime release signing, notarization, stapling, Gatekeeper, and clean-machine evidence.

### Evidence locations

- Public/product/platform evidence: `docs/research/public-product-and-platform-evidence.md`
- Interface synthesis: `docs/design-decision.md`
- Implementation plan: `.omo/plans/embercue-macos-mvp.md`
