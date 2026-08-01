#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/dist/Embercue.app"
test -x "$APP/Contents/MacOS/Embercue"
plutil -lint "$APP/Contents/Info.plist"
codesign --verify --strict --verbose=4 "$APP"
cmp -s "$ROOT/THIRD_PARTY_NOTICES.md" "$APP/Contents/Resources/THIRD_PARTY_NOTICES.md"
cmp -s "$ROOT/ThirdParty/swift-markdown/LICENSE.txt" "$APP/Contents/Resources/Licenses/swift-markdown/LICENSE.txt"
cmp -s "$ROOT/ThirdParty/swift-markdown/NOTICE.txt" "$APP/Contents/Resources/Licenses/swift-markdown/NOTICE.txt"
cmp -s "$ROOT/ThirdParty/swift-cmark/COPYING" "$APP/Contents/Resources/Licenses/swift-cmark/COPYING"
swift package --package-path "$ROOT" describe >/dev/null
swift package --package-path "$ROOT" resolve >/dev/null
if ! rg -q '"identity" : "swift-markdown"' "$ROOT/Package.resolved" || ! rg -q '"version" : "0.8.0"' "$ROOT/Package.resolved"; then
  echo "Pinned swift-markdown 0.8.0 dependency is missing from Package.resolved" >&2
  exit 1
fi
if ! rg -q '"identity" : "swift-cmark"' "$ROOT/Package.resolved" || ! rg -q '"version" : "0.8.0"' "$ROOT/Package.resolved"; then
  echo "Resolved swift-cmark 0.8.0 dependency is missing from Package.resolved" >&2
  exit 1
fi
swift run --package-path "$ROOT" EmbercueChecks >/dev/null
FORBIDDEN='URLSession|Network[.]|NWConnection|CGEvent[.]post|AXUIElement|addGlobalMonitorForEvents|addLocalMonitorForEvents|WebKit|NSAppleScript'
if rg -n --glob '*.swift' --glob '!SelectedTextCapture.swift' "$FORBIDDEN" "$ROOT/Sources"; then
  echo "Forbidden API reference found" >&2
  exit 1
fi
CAPTURE_ADAPTER="$ROOT/Sources/EmbercueMac/SelectedTextCapture.swift"
if ! rg -q 'addGlobalMonitorForEvents\(matching: \.flagsChanged\)' "$CAPTURE_ADAPTER" || ! rg -q 'addLocalMonitorForEvents\(matching: \.flagsChanged\)' "$CAPTURE_ADAPTER" || ! rg -q 'return event' "$CAPTURE_ADAPTER" || rg -n 'characters|keyCode|NSPasteboard|activate\(' "$CAPTURE_ADAPTER"; then
  echo "Selected-text capture boundary is not modifier-only outside the explicitly consented copy seam" >&2
  exit 1
fi
if ! rg -q 'keyDown.postToPid\(target.processIdentifier\)' "$CAPTURE_ADAPTER" || ! rg -q 'keyUp.postToPid\(target.processIdentifier\)' "$CAPTURE_ADAPTER" || ! rg -q 'AutomaticSelectionCopyTarget.isStillFrontmost' "$CAPTURE_ADAPTER" || ! rg -q 'AutomaticSelectionCopyPasteboardChange.classify' "$CAPTURE_ADAPTER" || ! rg -q 'cancelPendingCopy' "$CAPTURE_ADAPTER" || ! rg -q 'AutomaticSelectionCopyTarget.isEligible' "$CAPTURE_ADAPTER"; then
  echo "Automatic copy must remain a guarded one-shot Command-C with a bounded changed-pasteboard wait" >&2
  exit 1
fi
if ! rg -q 'doubleShiftCaptureEnabled' "$CAPTURE_ADAPTER" || ! rg -q 'DoubleShiftCaptureConsentAlert' "$CAPTURE_ADAPTER" || ! rg -q 'catch SelectedTextCaptureError\.unavailable' "$CAPTURE_ADAPTER" || ! rg -q 'automaticSelectionCopier\.copySelection' "$CAPTURE_ADAPTER" || [ "$(rg -c 'clipboard\.readPlainText' "$CAPTURE_ADAPTER")" -ne 1 ] || rg -n 'clipboardFallback|automaticCopySelection|selectedTextCaptureEnabled' "$ROOT/Sources/EmbercueMac" || ! rg -q 'Enable Double-Shift Capture' "$CAPTURE_ADAPTER"; then
  echo "Double-Shift capture must have one explicit consent and no stale clipboard fallback" >&2
  exit 1
fi
if rg -n --glob '*.swift' 'NSPasteboard[.]general' "$ROOT/Sources/EmbercueMac" | grep -v 'SystemClipboard.swift'; then
  echo "Pasteboard access escaped SystemClipboard" >&2
  exit 1
fi
if ! printf '%s\n' 'Network.connection' 'CGEvent.post' 'AXUIElement' | rg -q "$FORBIDDEN"; then
  echo "Forbidden API guard probe failed" >&2
  exit 1
fi
if ! printf '%s\n' 'NSPasteboard.general' | rg -q 'NSPasteboard[.]general'; then
  echo "Pasteboard guard probe failed" >&2
  exit 1
fi
echo "Local bundle and static boundary checks passed. This is ad-hoc validation, not release notarization."
