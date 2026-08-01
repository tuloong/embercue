# Independent verification — Embercue macOS MVP (post-security remediation)

> Historical baseline: the 420×680 and 364×720 observations below predate the
> schema-v2/video-fidelity rail and must not be used as its acceptance evidence.

## Current fidelity implementation handoff (2026-08-01)

The current rail replaces lifecycle buckets with durable ordered sections,
schema-v2 raw-byte migration, compact Markdown cards, selection and native menu
commands. Author-run evidence is intentionally separated from independent QA:

- The current rail is **364×640 pt**. The older 420×680 and 364×720 values in
  the historical report below are not current acceptance evidence.
- `swift-markdown` **0.8.0** is the only direct external package dependency.
  It resolves `swift-cmark` **0.8.0** transitively. Both are used for local
  Markdown parsing only; their exact upstream license/notice inventories ship
  in the app bundle, and neither adds a network, sync, analytics, or account
  service.

- `swift run EmbercueChecks` covers literal schema-v1 load/mutation/recovery,
  byte-identical pre-schema backup, section/order operations, clipboard-first
  Copy as List semantics, visual-fixture payload, placement geometry and QA
  appearance gating.
- `scripts/capture-fidelity-fixture.sh --launch <absolute dir>` writes only an
  isolated fixture root and a temporary screenshot artifact; attach mode does
  not launch, focus, hide, or terminate the observed app.
- `scripts/compose-fidelity-overlays.py` makes normalized screenshot artifacts
  and fails geometry drift beyond the explicit tolerance.

The packaged interaction replay is now retained in
`.omo/evidence/embercue-computer-use-runtime-qa.md`. Computer Use exercised
selection/context menus, expanded text/chrome separation, inline and separate
editors, sections/composer, Move, Merge, copy/list-copy, lifecycle/history,
search, explicit clipboard capture, and export entry on an isolated Light
fixture. The older FAIL/MANUAL rows below are historical and are superseded for
those named surfaces. Global hot-key delivery, VoiceOver speech, Full Keyboard
Access system settings, Reduce Motion, multi-display/Spaces/Stage Manager,
clean macOS 14, and public release controls remain explicit manual/release
gates.

## Computer Use repair replay (2026-08-01)

The replay found and closed four observable defects: search-only empty section
headings, `Keep Clipboard` failure for valid custom-only schema-v2 libraries,
card pointer activation leaving keyboard focus in the composer, and archived
History cards announcing themselves as Active. Each repair has a retained
`EmbercueChecks` regression. Search, Keep Clipboard, and archived AX state were
then replayed against the repackaged app at
`/tmp/embercue-live-ui-qa.KTivKc/`; screenshots and accessibility trees are in
its `artifacts/` directory.

One stale accessibility-menu sequence produced a context-menu crash. The valid
right-click → Edit → Cancel workflow subsequently passed 20/20 repetitions,
stale-element reuse was rejected by Computer Use without a crash, and no later
Embercue crash report appeared. This is retained as stress evidence rather than
a reproducible command-path failure.

## Selection interaction optimization handoff (2026-08-01)

The card-selection repair replaces the competing whole-card SwiftUI tap gesture
and global modifier sampling with an AppKit-backed control that captures the
originating event. The 18 pt selector remains visually compact while its native
hit target is 28 pt; collapsed text belongs to the card control, expanded text
remains selectable above a non-text chrome control, and contextual commands use
`WorkbenchModel.prepareContext(for:)` before operating.

- Three consecutive final `swift run EmbercueChecks` runs passed. The retained
  checks route down/up events through an offscreen `NSWindow`, cover plain,
  Command and Shift selection, stale-modifier cleanup, 20 rapid clicks, circle
  single-toggle, all four 28 pt edge points, accessibility values, and contextual
  selection followed by Move.
- `swift build -c release`, `swift test --parallel`, `git diff --check`,
  `scripts/package-app.sh`, and `scripts/verify-local.sh` all exited 0. On this
  Command Line Tools host, `swift test` is build-only evidence.
- The final isolated launch artifact at
  `/tmp/embercue-selection-final-v2-20260801/` records a visible 364×640 window;
  only its exact PID 2120 was terminated. The independent QA artifact root is
  `/tmp/embercue-selection-runtime-qa.c8jVIo/`.
- Independent code and clone-fidelity reviews report no P1/P2/P3 findings. See
  `.omo/evidence/embercue-selection-interaction-code-review.md` and
  `.omo/evidence/embercue-selection-interaction-runtime-qa.md`.

At this earlier selection handoff, Computer Use permission was unavailable.
The current Computer Use repair replay above supersedes the secondary-click,
menu enablement, and expanded-text/chrome gaps. Mouse-down drag-out behavior,
inactive-panel first click, VoiceOver speech, Full Keyboard Access system
settings, and Reduce Motion remain explicit packaged manual gates. No
AppleScript, CGEvent, or Accessibility injection was used as a substitute.

Date: 2026-08-01 (Asia/Shanghai)

This is a read-only QA pass against the post-security-remediation tree. No
product, source, test, or packaging files were changed by this pass. The only
repository artifact written is this report. Fresh evidence is under
`/tmp/embercue-qa-security.pTGym5/` plus the fresh durable-recovery artifacts
under `/tmp/embercue-qa-durable-final.cMMHet/`. The startup-visibility
remediation was independently rechecked under
`/tmp/embercue-manual-qa-20260801-094400/`.

## Target environment

- macOS 15.7.4 (24G517), arm64
- Swift 6.2.3 (`swift-driver 1.127.14.1`)
- SDK: `/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk`
- Package minimum: macOS 14.0
- No valid code-signing identity
- Full Xcode/XCTest and Swift Testing are unavailable. Conditional XCTest
  targets compile but do not execute framework-backed cases here; the expanded
  `EmbercueChecks` executable and focused Core harnesses provide runnable proof.

## Command evidence

| Surface | Exact invocation | Exit | Result | Artifact |
| --- | --- | ---: | --- | --- |
| Package topology | `swift package describe` | 0 | PASS — four products, two test targets; `swift-markdown` 0.8.0 is the only direct external package dependency and resolves `swift-cmark` 0.8.0 transitively. | A1 |
| Available tests | `swift test --parallel` | 0 | PASS at build level; no XCTest cases execute on this host. | A2 |
| Core test filter | `swift test --filter EmbercueCoreTests` | 0 | PASS at build level; conditional XCTest suite unavailable at runtime. | A3 |
| macOS test filter | `swift test --filter EmbercueMacTests` | 0 | PASS at build level; conditional XCTest suite unavailable at runtime. | A4 |
| Expanded behavior executable | `swift run EmbercueChecks` | 0 | PASS — adapter fakes, clipboard policy, validation boundaries, revision overflow, rollback, durable unreadable-backup/dual-quarantine recovery, export, explicit data-root validation, symlink handling, restrictive umask, lock/reserved-destination integrity, and cross-process writer conflict. | A5 |
| Repeatability | three consecutive `swift run EmbercueChecks` runs | all 0 | PASS — every run passed, including the cross-process writer regression. | A6 |
| Release build | `swift build -c release` | 0 | PASS. | A7 |
| Packaging | `bash scripts/package-app.sh` | 0 | PASS — release binary, deterministic iconset/ICNS, plist, and ad-hoc signature. | A8 |
| Local verification | `bash scripts/verify-local.sh` | 0 | PASS — bundle, expanded checks, static guard, and positive probes. | A9 |
| Plist/signature | `plutil -lint .../Info.plist`; `codesign --verify --strict --verbose=4 ...` | both 0 | PASS — valid local ad-hoc signature, no TeamIdentifier. | A10 |
| Public release assessment | `spctl --assess --type execute --verbose=4 dist/Embercue.app` | 3 | EXPECTED LIMIT — ad-hoc artifact rejected; no Developer ID/notarization claim. | A10 |
| Icon dimensions | `sips -g pixelWidth -g pixelHeight` over source/iconset PNGs; `file AppIcon.icns` | 0 | PASS — all generated/source/iconset dimensions are exact and ICNS is recognized. | A10 |
| Static privacy boundary | corrected `rg` scan for network, Accessibility, synthetic input, WebKit, event monitor, and global clipboard APIs | 1 (no matches) | PASS — no prohibited implementation references; pasteboard access confined to `SystemClipboard.swift`. | A11 |
| Static positive probes | `printf ... | rg` for dotted `Network.connection`, `CGEvent.post`, and `NSPasteboard.general` | 0 | PASS — guard detects prohibited spellings. | A11 |
| Diff hygiene | `git diff --check` | 0 | PASS. | A12 |
| Durable recovery focused harness | disposable Core dynamic-module harness covering first launch, missing-primary+unreadable-backup, corrupt-primary+unreadable-backup, valid-backup restore, quarantine bytes/modes, two mutations, and relaunch | 0 | PASS — all named notices, preservation, active-backup rotation, and revision-2 relaunch assertions pass. | A17 |
| Lock inode focused harness | compile Core sources as a disposable dynamic module, save/load twice, compare `.library.lock` inode | 0 | PASS — lock inode remains identical across operations. | A13 |
| Export destination focused harness | compile Core sources as disposable dynamic module; attempt direct, normalized, parent-normalized, and symlink aliases | 0 | PASS — all managed/resolved destinations rejected as `reservedExportDestination`. | A14 |
| Isolated packaged launch | `EMBERCUE_DATA_DIRECTORY=<unique absolute /tmp dir> dist/Embercue.app/Contents/MacOS/Embercue` for 5 seconds, then targeted kill | 143 intentional kill | PASS for process-start/isolation — only `.library.lock` under disposable root; real Application Support store absent before/after. | A15 |
| Copied bundle | copy app to unique `/tmp`, strict verify, launch copied executable with disposable data root for 3 seconds | 0 verification; 143 intentional kill | PASS — expected files only, no symlinks, valid signature, process remains alive. | A16 |
| LaunchServices startup visibility | `make verify-startup-ui` | 0 | Historical PASS — the cited artifact predates the current 364×640 rail; rerun this independent gate before treating it as current interaction evidence. | A18 |
| Startup-check concurrency | two simultaneous `bash scripts/verify-startup-ui.sh` invocations | 0 and 75 | PASS — one launch was verified; the competing run failed fast with `EX_TEMPFAIL`, and no exact packaged-executable process remained. | A19 |

The supported GUI isolation control is absolute `EMBERCUE_DATA_DIRECTORY`;
`HOME` is not used as isolation evidence.

## `manualQa` matrix

### `surfaceEvidence`

| Scenario | Criterion reference | Surface and exact invocation | Verdict | Artifact refs |
| --- | --- | --- | --- | --- |
| S1 | package topology | Terminal: `swift package describe` | PASS | A1 |
| S2 | available Swift checks | Terminal: full Swift test and both filters | PASS (build-only; no runtime XCTest cases) | A2, A3, A4 |
| S3 | core/security behavior | Terminal: `swift run EmbercueChecks` | PASS | A5 |
| S4 | repeatability/concurrency | Terminal: three repeated expanded-check runs | PASS | A6 |
| S5 | build/package/verify | Terminal: release build, package script, local verify | PASS (local/ad hoc) | A7, A8, A9 |
| S6 | plist/signature/icon | Terminal: `plutil`, `codesign`, `sips`, `file` | PASS (ad hoc only) | A10 |
| S7 | static privacy boundary | Terminal: corrected scan and positive probes | PASS | A11 |
| S8 | lock inode integrity | Focused disposable Core harness | PASS | A13 |
| S9 | export destination boundary | Focused disposable Core harness | PASS | A14 |
| S10 | package self-containment/data isolation | OS process: copied bundle and direct bundle with disposable data roots | PASS | A15, A16 |
| S11 | composer, visible recovery, history, relaunch, menu/hotkey UI | Packaged GUI action surface | FAIL — no safe interactive GUI automation/manual surface was available. Missing prerequisite: interactive macOS GUI harness. | A15 |
| S12 | durable recovery notices and preservation | Focused disposable Core harness | PASS | A17 |
| S13 | launch response | LaunchServices startup plus WindowServer ownership/visibility probe | HISTORICAL PASS — the cited `420×680` artifact predates the current 364×640 rail. It remains visibility-only evidence, not interaction evidence. | A18 |

### `adversarialCases`

| Scenario | Criterion reference | Adversarial class | Expected behavior | Verdict | Artifact refs |
| --- | --- | --- | --- | --- | --- |
| A1 | persistence recovery | missing primary + valid backup | Restore backup, show distinct recovery notice, allow mutation, and observe revision after relaunch | PASS | A5, A17 |
| A2 | persistence recovery | missing primary + unreadable backup | Return named quarantine notice; preserve bytes at mode-0600 quarantine path; leave active backup and primary absent; two mutations rotate valid backup and relaunch at revision 2 | PASS | A5, A17 |
| A3 | export safety | direct reserved destination | Reject primary, backup, and lock destinations before writing | PASS | A5 |
| A4 | export safety | normalized/parent-normalized reserved destination | Reject `./library.json` and `sub/../library.json` after normalization | PASS | A14 |
| A5 | export safety | symlink alias to managed file | Reject alias without changing managed file | PASS | A5, A14 |
| A6 | locking | lock inode integrity | Managed lock remains the same regular-file inode across saves/loads | PASS | A5, A13 |
| A7 | file safety | managed document symlink | Do not follow or modify symlink target | PASS | A5 |
| A8 | size boundary | primary larger than 64 MiB | Quarantine oversized primary and recover to a valid empty/backup state | PASS | A5 |
| A9 | permissions | restrictive `umask` | Export still has mode `0600`; root remains owner-only | PASS | A5 |
| A10 | adapter boundary | hot-key failure/menu fallback, foreground target, placement | Fakes prove cleanup, fallback, target filtering, one-shot activation, and deterministic placement | PASS | A5 |
| A11 | clipboard policy | implicit reads and copy/complete conflation | Queueing reads zero times; explicit Keep Clipboard reads once; copy failure/success never completes | PASS | A5 |
| A12 | revision safety | `Int.max` direct/on-disk/engine mutation | Reject or quarantine without wraparound | PASS | A5 |
| A13 | concurrency | two writers at same revision | One succeeds, one exits conflict status 75 | PASS | A5, A6 |
| A14 | static boundary | prohibited dotted APIs | Source scan is clean and positive probes match guard | PASS | A9, A11 |
| A15 | GUI privacy | launch/show/search/tab clipboard behavior | Source boundary is clean, but GUI interaction was not runnable. Blocker: missing interactive GUI harness. | FAIL | A11, A15 |
| A16 | integration | actual hotkey collision/menu invocation | Adapter fake covers failure/fallback semantics; actual GUI invocation unavailable. Blocker: missing interactive GUI harness. | FAIL | A5, A15 |
| A17 | release | Developer ID/hardened runtime/notarization/Gatekeeper | Outside local ad-hoc scope; `spctl` rejection is recorded | NOT_APPLICABLE | A10 |
| A18 | persistence recovery | true first launch | Both primary and backup missing yields empty document with no recovery notice | PASS | A17 |
| A19 | startup-check ownership | two concurrent verifier instances | Exactly one verifier owns the app launch; the other exits temporarily unavailable without launching or cleaning another process | PASS | A19 |

## Artifact references

| ID | Kind | Description | Path |
| --- | --- | --- | --- |
| A1 | terminal transcript | Package description | `/tmp/embercue-qa-security.pTGym5/package-describe.log` |
| A2 | terminal transcript | Full SwiftPM test run | `/tmp/embercue-qa-security.pTGym5/swift-test.log` |
| A3 | terminal transcript | Core test filter | `/tmp/embercue-qa-security.pTGym5/swift-core-filter.log` |
| A4 | terminal transcript | macOS test filter | `/tmp/embercue-qa-security.pTGym5/swift-mac-filter.log` |
| A5 | executable transcript | Expanded adapter/core/security/persistence/concurrency checks | `/tmp/embercue-qa-durable-final.cMMHet/behavior-check.log` |
| A6 | executable transcript | Three repeated expanded-check runs | `/tmp/embercue-qa-security.pTGym5/repeated-checks.log` |
| A7 | terminal transcript | Release build | `/tmp/embercue-qa-security.pTGym5/release-build.log` |
| A8 | terminal transcript | Deterministic package command | `/tmp/embercue-qa-durable-final.cMMHet/package-app.log` |
| A9 | terminal transcript | Full local verification script | `/tmp/embercue-qa-durable-final.cMMHet/local-verify.log` |
| A10 | terminal transcript | Current plist and strict-signature checks; prior bundle/icon inventory retained | `/tmp/embercue-qa-durable-final.cMMHet/plist-check.log`, `/tmp/embercue-qa-durable-final.cMMHet/codesign-check.log`, `/tmp/embercue-qa-security.pTGym5/bundle-icon.log` |
| A11 | static-scan transcript | Correct source scan, pasteboard ownership, and positive probes | `/tmp/embercue-qa-security.pTGym5/static.log` |
| A12 | terminal transcript | Current full `git diff --check` | `/tmp/embercue-qa-durable-final.cMMHet/diff-check.log` |
| A13 | focused harness transcript | Disposable Core dynamic-module lock inode check | `/tmp/embercue-qa-security.pTGym5/lock-inode.log` |
| A14 | focused harness transcript | Direct/normalized/symlink export rejection check | `/tmp/embercue-qa-security.pTGym5/export-destinations.log` |
| A15 | OS/process transcript | Disposable data-root launch, lock tree, mode, real-store check, stdout/stderr | `/tmp/embercue-qa-security.pTGym5/gui-run.log`, `/tmp/embercue-qa-security.pTGym5/gui.stdout`, `/tmp/embercue-qa-security.pTGym5/gui.stderr` |
| A16 | OS/process transcript | Copied bundle inventory, symlink check, signature, and bounded launch | `/tmp/embercue-qa-security.pTGym5/package-copy.log` |
| A17 | focused harness transcript | Durable unreadable-backup/dual-quarantine/first-launch/valid-backup recovery with two mutations and relaunch | `/tmp/embercue-qa-durable-final.cMMHet/recovery-focused.log` |
| A18 | LaunchServices/WindowServer transcript | Final packaged startup visibility and process cleanup | `/tmp/embercue-manual-qa-20260801-094400/21-final-normal-startup.txt` |
| A19 | concurrent verifier transcripts | One successful launch, one lock conflict, and final exact-process inventory | `/tmp/embercue-manual-qa-20260801-094400/22-concurrent-a.txt`, `/tmp/embercue-manual-qa-20260801-094400/23-concurrent-b.txt`, `/tmp/embercue-manual-qa-20260801-094400/24-concurrent-wrapper.txt` |

## Proof boundary

This pass establishes executable adapter/core behavior, missing-primary and
invalid-backup recovery, recovery→mutate→relaunch, reserved direct/normalized/
symlink export rejection, lock inode stability, no-follow managed symlink
behavior, the >64 MiB boundary, restrictive-umask `0600` enforcement,
permissions, cross-process conflict handling, package self-containment, local
ad-hoc signing, static privacy boundaries, safe data-root isolation, and a
LaunchServices-owned on-screen startup window. It does not establish complete
GUI interaction, Developer ID signing, hardened runtime, notarization, stapling,
Gatekeeper on a downloaded artifact, Mac App Store compliance, clean macOS 14
behavior, VoiceOver/Full Keyboard Access, multi-display placement, or complete
interactive composer/history/menu/hotkey/clipboard workflows. No release
approval or notarization claim is made.
