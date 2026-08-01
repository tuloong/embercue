# MR review 2 — selection interaction responsiveness

Date: 2026-08-01 (Asia/Shanghai)

Target: `main`, starting at `d537d44197b97faa95454c50c547437459816a44`

## Scope and risk

Risk class: R1, bounded macOS interaction change. The diff changes card pointer
ownership, event-time modifier capture, contextual selection, accessibility
metadata, and focused regression coverage. It does not change persistence,
schema, network/privacy boundaries, clipboard policy, hot-key ownership, panel
geometry, or product branding.

## Review passes

| Pass | Result | Notes |
| --- | --- | --- |
| Code quality | CLEAR / APPROVE | No remaining P1/P2/P3; the final context/Move regression uses the production `WorkbenchModel.prepareContext(for:)` contract. |
| Clone/design fidelity | APPROVE / CLEAR | No remaining P1/P2/P3; compact layout and event behavior remain token-driven rather than screenshot-hardcoded. |
| Runtime QA | PASS for automated/build/package/isolated-render scope | Six real OS-input scenarios remain MANUAL because Computer Use permission was unavailable. |
| Root verification | PASS | Checks ×3, release build, test-target build, diff check, package, local verify, and isolated 364×640 capture. |

## Resolved review history

- Added a collapsed-card body control and an expanded non-text chrome control,
  while retaining selectable expanded Markdown text.
- Replaced callback-time global modifiers with modifiers captured from the
  originating AppKit mouse-down event.
- Scoped pointer state to one native button transaction and cleared it for
  `performClick`/keyboard paths.
- Kept the visible circle at 18 pt but proved a 28 pt native target at all four
  added outer edges without body double activation.
- Separated completion check/fill from selected outline/surface and removed the
  selection animation that delayed settled feedback.
- Centralized contextual selection in `WorkbenchModel.prepareContext(for:)`,
  then proved selected-card preservation, unselected-card replacement, and the
  subsequent Move target.
- Added contextual accessibility labels, selected state, and combined
  active/completed plus selected/not-selected values.
- Removed a tautological completion test seam rather than retaining
  implementation-mirroring coverage.

## Remaining manual gates

These are evidence boundaries, not unresolved P1/P2/P3 findings: live
secondary-click menu scope and enablement, expanded text drag versus chrome
click, mouse-down appearance and drag-away cancellation, inactive-panel first
click, VoiceOver, Full Keyboard Access, and Reduce Motion.

## Recommendation

Approve the bounded local-app change. Do not claim complete packaged GUI or
accessibility validation until the manual gates run on a host with permitted
Computer Use access.
