#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${EMBERCUE_APP:-$ROOT/dist/Embercue.app}"
EXECUTABLE="$APP/Contents/MacOS/Embercue"
TIMEOUT_SECONDS="${EMBERCUE_STARTUP_UI_TIMEOUT_SECONDS:-10}"

if [[ "$APP" != /* || ! "$TIMEOUT_SECONDS" =~ ^[1-9][0-9]*$ ]]; then
  echo "EMBERCUE_APP must be absolute and EMBERCUE_STARTUP_UI_TIMEOUT_SECONDS must be a positive integer" >&2
  exit 64
fi
if [[ ! -x "$EXECUTABLE" ]]; then
  echo "Packaged executable is missing or not executable: $EXECUTABLE" >&2
  exit 66
fi

LOCK_ID="$(printf '%s' "$APP" | shasum -a 256 | awk '{ print substr($1, 1, 16) }')"
LOCK_FILE="${TMPDIR:-/tmp}/embercue-startup-ui-${LOCK_ID}.lock"
# BSD locks are held by this shared file descriptor, not by lock-file existence.
# Keep the file so a stale file never implies ownership or changes lock ordering.
exec 9>>"$LOCK_FILE"
if ! /usr/bin/lockf -s -t 0 9; then
  echo "Another startup UI check already holds $LOCK_FILE; refusing to launch a second Embercue instance." >&2
  exit 75
fi

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/embercue-startup-ui.XXXXXX")"
TMP_ROOT="$(cd "$TMP_ROOT" && pwd)"
DATA_DIRECTORY="$TMP_ROOT/data"
LOG_FILE="$TMP_ROOT/Embercue.stderr.log"
STDOUT_LOG="$TMP_ROOT/Embercue.stdout.log"
PROBE_LOG="$TMP_ROOT/WindowServer-probe.log"
BEFORE_PIDS="$TMP_ROOT/Embercue.before-pids"
AFTER_PIDS="$TMP_ROOT/Embercue.after-pids"
APP_PID=""
PROBE_PID=""

app_pids() {
  local candidate command
  while IFS= read -r candidate; do
    command="$(ps -p "$candidate" -o command= 2>/dev/null || true)"
    command="${command#"${command%%[![:space:]]*}"}"
    if [[ "$command" == "$EXECUTABLE"* ]]; then
      printf '%s\n' "$candidate"
    fi
  done < <(pgrep -x Embercue 2>/dev/null || true) | sort -n
}

cleanup() {
  if [[ -z "$APP_PID" && -f "$BEFORE_PIDS" ]]; then
    app_pids >"$AFTER_PIDS" 2>/dev/null || true
    cleanup_new_pids="$(comm -13 "$BEFORE_PIDS" "$AFTER_PIDS")"
    cleanup_new_pid_count="$(printf '%s\n' "$cleanup_new_pids" | awk 'NF { count += 1 } END { print count + 0 }')"
    if [[ "$cleanup_new_pid_count" == "1" ]]; then
      APP_PID="$cleanup_new_pids"
    fi
  fi
  if [[ -n "$PROBE_PID" ]] && kill -0 "$PROBE_PID" 2>/dev/null; then
    kill "$PROBE_PID" 2>/dev/null || true
    wait "$PROBE_PID" 2>/dev/null || true
  fi
  if [[ -n "$APP_PID" ]] && kill -0 "$APP_PID" 2>/dev/null; then
    kill "$APP_PID" 2>/dev/null || true
    wait "$APP_PID" 2>/dev/null || true
  fi
  rm -rf "$TMP_ROOT" || true
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

mkdir "$DATA_DIRECTORY"
app_pids >"$BEFORE_PIDS"
echo "Launching packaged Embercue through LaunchServices with isolated data directory: $DATA_DIRECTORY"
open -n --env "EMBERCUE_DATA_DIRECTORY=$DATA_DIRECTORY" --stdout "$STDOUT_LOG" --stderr "$LOG_FILE" "$APP"

STARTUP_DEADLINE=$((SECONDS + 5))
NEW_PIDS=""
while (( SECONDS < STARTUP_DEADLINE )); do
  app_pids >"$AFTER_PIDS"
  NEW_PIDS="$(comm -13 "$BEFORE_PIDS" "$AFTER_PIDS")"
  if [[ -n "$NEW_PIDS" ]]; then
    break
  fi
  sleep 0.1
done

NEW_PID_COUNT="$(printf '%s\n' "$NEW_PIDS" | awk 'NF { count += 1 } END { print count + 0 }')"
if [[ "$NEW_PID_COUNT" != "1" ]]; then
  echo "Expected exactly one new Embercue PID from LaunchServices, observed: ${NEW_PIDS:-none}" >&2
  exit 1
fi
APP_PID="$NEW_PIDS"
echo "Checking WindowServer visibility for PID $APP_PID (timeout: ${TIMEOUT_SECONDS}s)"

swift - "$APP_PID" "$TIMEOUT_SECONDS" >"$PROBE_LOG" 2>&1 <<'SWIFT' &
import CoreGraphics
import Darwin
import Foundation

let expectedWidth = 364.0
let expectedHeight = 640.0
let widthTolerance = 24.0
let heightTolerance = 24.0

let arguments = CommandLine.arguments
guard arguments.count == 3,
      let processIdentifier = Int32(arguments[1]),
      let timeoutSeconds = TimeInterval(arguments[2]) else {
    fputs("Window probe received invalid arguments.\n", stderr)
    exit(64)
}

func number(_ dictionary: [String: Any], _ key: CFString) -> Double {
    (dictionary[key as String] as? NSNumber)?.doubleValue ?? 0
}

func description(of window: [String: Any]) -> String {
    let bounds = window[kCGWindowBounds as String] as? [String: Any] ?? [:]
    let width = number(bounds, "Width" as CFString)
    let height = number(bounds, "Height" as CFString)
    return "layer=\(Int(number(window, kCGWindowLayer))), on-screen=\(Int(number(window, kCGWindowIsOnscreen))), alpha=\(number(window, kCGWindowAlpha)), width=\(width), height=\(height)"
}

let deadline = Date().addingTimeInterval(timeoutSeconds)
var lastWindowDescriptions: [String] = []

while Date() < deadline {
    if kill(processIdentifier, 0) == -1 && errno == ESRCH {
        fputs("Embercue PID \(processIdentifier) exited before a visible WindowServer window appeared.\n", stderr)
        exit(1)
    }

    let windows = (CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]]) ?? []
    let ownedWindows = windows.filter { ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == processIdentifier }
    lastWindowDescriptions = ownedWindows.map(description)
    let visibleWindows = ownedWindows.filter {
        let bounds = $0[kCGWindowBounds as String] as? [String: Any] ?? [:]
        return number($0, kCGWindowIsOnscreen) > 0 &&
            number($0, kCGWindowAlpha) > 0 &&
            number(bounds, "Width" as CFString) > 0 &&
            number(bounds, "Height" as CFString) > 0
    }

    let railWindows = visibleWindows.filter {
        let bounds = $0[kCGWindowBounds as String] as? [String: Any] ?? [:]
        let width = number(bounds, "Width" as CFString)
        let height = number(bounds, "Height" as CFString)
        return abs(width - expectedWidth) <= widthTolerance && abs(height - expectedHeight) <= heightTolerance
    }

    if !railWindows.isEmpty {
        print("Visible Ember Rail observed for PID \(processIdentifier) within \(widthTolerance)×\(heightTolerance) pt geometry tolerance: \(railWindows.map(description).joined(separator: "; "))")
        exit(0)
    }
    Thread.sleep(forTimeInterval: 0.2)
}

fputs("Timed out waiting for a visible WindowServer window for PID \(processIdentifier). Last rows: \(lastWindowDescriptions.joined(separator: "; "))\n", stderr)
exit(1)
SWIFT
PROBE_PID=$!

if wait "$PROBE_PID"; then
  PROBE_PID=""
  sed -n '1,200p' "$PROBE_LOG"
  echo "Startup UI visibility check passed."
else
  probe_status=$?
  PROBE_PID=""
  echo "Startup UI visibility check failed for PID $APP_PID (exit $probe_status)." >&2
  if [[ -s "$PROBE_LOG" ]]; then
    echo "--- WindowServer probe output ---" >&2
    sed -n '1,200p' "$PROBE_LOG" >&2
  else
    echo "WindowServer probe produced no output." >&2
  fi
  if [[ -s "$LOG_FILE" ]]; then
    echo "--- Embercue process output ---" >&2
    tail -n 80 "$LOG_FILE" >&2
  else
    echo "Embercue process produced no stderr output." >&2
  fi
  if [[ -s "$STDOUT_LOG" ]]; then
    echo "--- Embercue process stdout ---" >&2
    tail -n 80 "$STDOUT_LOG" >&2
  fi
  exit "$probe_status"
fi
