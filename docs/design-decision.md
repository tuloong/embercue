# Embercue Interface Design Decision

- Status: superseded by the Copper-video fidelity decision (2026-08-01)
- Decision date: 2026-08-01
- Product line: **Catch the thought. Queue the next move.**

## Requirements used for all designs

Embercue must capture manually entered or explicitly pasted text, keep reusable snippets, queue prompts, copy them back to any text-capable app, and let the user explicitly complete or restore work. It must remain useful without Accessibility permission, avoid background clipboard monitoring, use local versioned storage, and stay reachable from a global shortcut and the menu bar.

## Design A: three-command capture palette

This design exposes a single focused text field and three semantic commands: `Queue`, `Keep`, and `Copy Next`. A separate Library window owns browsing and recovery.

The caller-facing interface is intentionally small:

```swift
enum PrimaryCommand {
    case queuePrompt(String)
    case keep(KeepSource)
    case copyNext
}

protocol EmbercueCommanding {
    func execute(_ command: PrimaryCommand) throws -> CommandOutcome
    func snapshot() throws -> LibrarySnapshot
}
```

Typical use is shortcut → type → Return to queue, or shortcut → explicit Keep Clipboard. Persistence, hot-key tokens, clipboard conversion, and previous-app activation stay behind the command boundary.

Its strength is speed and ease of correct use. Its weakness is that it hides the queue that motivated the product and requires a second window for ordinary triage.

## Design B: persistent edge workbench

This design anchors a compact workbench to the right edge. It shows one current prompt, the next prompts, a Keep view, history, and an always-available composer. The full exploration included named Runs, tags, reordering, auto-paste, and a collapsed edge handle.

Its interface is command-oriented:

```swift
protocol WorkbenchClient {
    func start() throws -> WorkbenchSnapshot
    func perform(_ command: WorkbenchCommand) throws -> WorkbenchEffect
}
```

A caller adds a prompt, explicitly copies the current prompt, and later performs a separate `finishCurrent` command. The interface hides queue invariants, JSON revisions, backup/recovery, hot-key registration, and transient source-app activation.

Its strength is direct visibility of the user's working queue and a good spatial fit beside an AI app. Its weakness is scope: named Runs, tags, an edge handle, and automation make a first release unnecessarily complex and harder to verify.

## Design C: menu-bar “Pocket Stage”

This design treats the queue as a stack. The menu-bar popover exposes only the cue “on stage,” with waiting count, a snippet shelf, search, completion, and recovery. A normal Library window handles bulk work.

The UI receives one state stream and sends intents through one gateway:

```swift
protocol CueDesk {
    func states() -> AsyncStream<DeskState>
    func handle(_ action: DeskAction) async -> DeskEffect
}
```

Copy, keep, completion, restore, and delivery preparation remain different actions. Storage, search, undo, Services intake, clipboard policy, and permission handling stay internal.

Its strength is calm focus and precise state semantics. Its weakness is reduced queue visibility and reliance on a popover plus another window for power use.

## Comparison

The palette has the smallest surface and the lowest misuse risk, but on its own feels like a launcher rather than the promised companion beside ongoing work. The full edge workbench best matches the spatial problem and makes state visible, but its multi-run and automation ideas increase retained code before there is evidence that users need them. Pocket Stage provides the strongest distinction between “copied” and “completed” and the best recovery semantics, but a one-card stack slows reordering and hides context.

All three agree on the deepest product boundary: SwiftUI should send semantic commands; views should never manipulate JSON, the pasteboard, global registration tokens, or other applications directly.

## Selected synthesis

Embercue uses the edge workbench's right-side panel and the palette's explicit capture actions, now reshaped against frame-by-frame observations from the public Copper demo. The result is a native, local Embercue rail with independent branding and explicit safety boundaries; it is not Copper branding, copy, assets, or automation.

The panel has:

- a white search pill and one circular overflow menu, with no in-panel wordmark;
- durable named sections with compact Markdown cards, leading selection circles, multi-selection, and History as a secondary page;
- a pinned single-line composer whose leading circle selects the capture section;
- one native context-menu command surface: Copy, Copy as List, Mark as Done, Expand, Edit, Edit in New Window, Merge Notes, and Move to;
- inline dismissible notices that do not discard a failed draft or replace the authoritative model state.

The default floating panel is 364×640 pt, starts 64 pt from the active display’s right edge, and remains visible when another app activates. It has no visual title, traffic lights, or revision footer. Closing it, Escape, and Hide Embercue order it out without clearing draft, search, or page. The app stays as an accessory process with a template menu-bar item and Control-Command-J; only the explicit Quit menu item terminates it.

The selected implementation deliberately excludes continuous selection capture, launch-time permission requests, keyboard logging, auto-paste, automatic Return/submit, and project-specific AI integrations. It permits one narrow synthetic-input exception: after the single explicit **Enable Double-Shift Capture…** consent and Accessibility approval, an exact selected-text unavailable result can send one Command-C to the current frontmost non-Embercue application. The sender never activates, pastes, submits, clears, or restores; it waits only briefly while that same PID remains frontmost, then accepts only a general-pasteboard count exactly one higher than its pre-copy snapshot. It rejects focus loss, count jumps, and old clipboard text. Paired local and global monitors observe modifier-flag transitions; only Shift presses count toward the gesture, while other command modifiers cancel it. An uninterrupted double Shift first reads the focused element's selected text. Manual entry and `Keep Clipboard` remain available when permission is denied or the focused app exposes no selection.

## Independent brand and visual direction

The app uses **Embercue**, not Copper, and does not reuse Copper assets, marketing copy, icon, or product name. The visual system uses semantic cool materials, system fonts, native focus rings, and system blue selection accents. Light is used only as an isolated QA reference appearance; normal Light, Dark, Increase Contrast and Reduce Transparency behavior stays native.

System fonts, native focus rings, semantic colors, text labels beside icons, reduced-motion behavior, and keyboard equivalents take precedence over ornamental resemblance.

## Ease-of-correct-use rules

- Opening Embercue never reads the clipboard.
- `Keep Clipboard` reads the clipboard only after its explicit command; double-Shift capture reads it only after its own Command-C produces one guarded post-copy pasteboard change.
- `Copy`, `Copy as List`, and `Copy & Return` are the only clipboard-write commands.
- Copy and Copy & Return never complete an item; Copy as List completes the
  selection only after its clipboard write succeeds.
- `Done` and `Archive` remain reversible through History.
- A failed save retains the draft or restores the prior durable state and shows an error.
- A corrupt or future-version file is quarantined and never silently overwritten.
- The menu bar remains a fallback if the shortcut cannot register.
- No success message says “sent” or “delivered”; Embercue can only prove “copied.”

## Deferred decisions

- Configurable shortcuts beyond the documented default.
- Multiple named runs/workspaces.
- Tags, rich text, and link previews.
- macOS Services and any capture beyond the explicit, permission-gated double-Shift selected-text action.
- Auto-paste and any automated prompt submission.
- Cloud sync, accounts, licensing, payments, and update checks.
