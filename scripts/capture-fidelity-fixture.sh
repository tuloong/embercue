#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/dist/Embercue.app"
EXECUTABLE="$APP/Contents/MacOS/Embercue"

usage() { echo "usage: $0 --launch <absolute-artifact-dir> | --attach --pid <pid> --window-id <id> <absolute-artifact-dir>" >&2; exit 64; }
[[ $# -ge 2 ]] || usage
MODE="$1"; shift

capture_window() {
  local pid="$1" window_id="$2" artifact="$3"
  swift - "$pid" "$window_id" "$artifact/window-metrics.json" <<'SWIFT'
import CoreGraphics
import Foundation
let arguments = CommandLine.arguments
guard arguments.count == 4, let pid = Int32(arguments[1]), let wanted = UInt32(arguments[2]) else { exit(64) }
let windows = (CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]]) ?? []
guard let window = windows.first(where: { ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid && ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value == wanted }) else { fputs("window is not owned by PID\n", stderr); exit(1) }
let bounds = window[kCGWindowBounds as String] as? [String: Any] ?? [:]
func n(_ key: String) -> Double { (bounds[key] as? NSNumber)?.doubleValue ?? 0 }
let display = CGDisplayBounds(CGMainDisplayID())
let result: [String: Any] = ["pid": Int(pid), "windowID": Int(wanted), "x": n("X"), "y": n("Y"), "width": n("Width"), "height": n("Height"), "screenWidth": display.width, "screenHeight": display.height]
try! JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted]).write(to: URL(fileURLWithPath: arguments[3]))
SWIFT
  # `-o` omits the WindowServer shadow. This gives the overlay tool the actual
  # rounded rail pixels rather than an arbitrary shadow margin.
  /usr/sbin/screencapture -o -l "$window_id" "$artifact/window.png"
  local region
  region="$(python3 - "$artifact/window-metrics.json" <<'PY'
import json,sys
m=json.load(open(sys.argv[1])); print(f"{max(0,int(m['x'])-80)},{max(0,int(m['y'])-80)},{int(m['width'])+160},{int(m['height'])+160}")
PY
)"
  /usr/sbin/screencapture -R "$region" "$artifact/screen-region.png"
}

if [[ "$MODE" == "--attach" ]]; then
  [[ $# == 5 && "$1" == "--pid" && "$3" == "--window-id" ]] || usage
  PID="$2"; WINDOW_ID="$4"; ARTIFACT="$5"
  [[ "$ARTIFACT" == /* && ! -e "$ARTIFACT" ]] || { echo "artifact directory must be a new absolute path" >&2; exit 64; }
  COMMAND="$(ps -p "$PID" -o command= 2>/dev/null || true)"
  [[ "$COMMAND" == "$EXECUTABLE"* ]] || { echo "PID does not run packaged Embercue executable" >&2; exit 1; }
  mkdir -p "$ARTIFACT"
  capture_window "$PID" "$WINDOW_ID" "$ARTIFACT"
  echo "attached pid=$PID windowID=$WINDOW_ID artifact=$ARTIFACT"
  exit 0
fi

[[ "$MODE" == "--launch" && $# == 1 ]] || usage
ARTIFACT="$1"
[[ "$ARTIFACT" == /* && ! -e "$ARTIFACT" ]] || { echo "artifact directory must be a new absolute path" >&2; exit 64; }
mkdir -p "$ARTIFACT"
make -C "$ROOT" package >"$ARTIFACT/package.log" 2>&1
[[ -x "$EXECUTABLE" ]] || { echo "packaged executable is missing" >&2; exit 1; }
DATA="$ARTIFACT/data"
swift run --package-path "$ROOT" EmbercueChecks --write-visual-fixture "$DATA" >"$ARTIFACT/fixture.log" 2>&1
LOCK="${TMPDIR:-/tmp}/embercue-fidelity-$(printf '%s' "$APP" | shasum -a 256 | cut -c1-16).lock"
exec 9>>"$LOCK"; /usr/bin/lockf -s -t 0 9 || { echo "another fidelity launch owns this app path" >&2; exit 75; }
# Direct executable launch receives isolated state at process start, so it never
# reads or mutates the default user library.
env EMBERCUE_DATA_DIRECTORY="$DATA" EMBERCUE_QA_APPEARANCE="${EMBERCUE_QA_APPEARANCE:-light}" "$EXECUTABLE" >"$ARTIFACT/stdout.log" 2>"$ARTIFACT/stderr.log" &
PID=$!
echo "$PID" >"$ARTIFACT/pid"
WINDOW_ID="$(swift - "$PID" <<'SWIFT'
import CoreGraphics
import Darwin
import Foundation
let pid = Int32(CommandLine.arguments[1]); let end = Date().addingTimeInterval(10)
while Date() < end {
 let rows = (CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]]) ?? []
 if let row = rows.first(where: { ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid && (($0[kCGWindowLayer as String] as? NSNumber)?.intValue ?? -1) == 3 && (($0[kCGWindowIsOnscreen as String] as? NSNumber)?.intValue ?? 0) == 1 }), let id = row[kCGWindowNumber as String] as? NSNumber { print(id.uint32Value); exit(0) }
 Thread.sleep(forTimeInterval: 0.2)
}; exit(1)
SWIFT
)"
echo "$WINDOW_ID" >"$ARTIFACT/window-id"
# WindowServer publishes the panel before SwiftUI has necessarily committed its
# first transaction.  Give the native hierarchy one short turn, without sending
# the app input or changing its state.
sleep 1
capture_window "$PID" "$WINDOW_ID" "$ARTIFACT"
kill "$PID" 2>/dev/null || true
wait "$PID" 2>/dev/null || true
echo "cleanup: terminated isolated pid $PID" >"$ARTIFACT/cleanup.log"
echo "launch artifact=$ARTIFACT pid=$PID windowID=$WINDOW_ID"
