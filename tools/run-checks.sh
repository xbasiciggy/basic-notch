#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
mkdir -p .build/checks
RUN="$(mktemp -d "$ROOT/.build/checks/run.XXXXXX")"
mkdir -p "$RUN/appData/Library/Application Support/BasicNotch/LightroomExports"
LUA_RUNTIME="${LUA_BIN:-}"
if [[ -z "$LUA_RUNTIME" ]] && command -v lua >/dev/null; then LUA_RUNTIME="$(command -v lua)"; fi
LUA_ARGS=()
if [[ -n "$LUA_RUNTIME" ]]; then
    "$LUA_RUNTIME" Tests/LightroomPluginChecks.lua "$ROOT/BasicNotch/Resources/Lightroom.bundle/BasicNotchExport.lrplugin" "$RUN/appData"
    LUA_ARGS=("$RUN/appData/Library/Application Support/BasicNotch/LightroomExports")
else
    echo 'Lua integration checks skipped; set LUA_BIN to a Lua 5.1 executable to run them.'
fi
swiftc -parse-as-library -module-cache-path "$ROOT/.build/ModuleCache" \
    Tests/CoreChecks.swift BasicNotch/App/DisplaySelection.swift BasicNotch/Pokemon/PokemonBounds.swift \
    BasicNotch/Services/LightroomExportService.swift -o "$RUN/CoreChecks"
if [[ ${#LUA_ARGS[@]} -gt 0 ]]; then
    "$RUN/CoreChecks" "$RUN/snapshots" "${LUA_ARGS[@]}"
else
    "$RUN/CoreChecks" "$RUN/snapshots"
fi
swiftc -parse-as-library -module-cache-path "$ROOT/.build/ModuleCache" \
    Tests/BuddyChecks.swift BasicNotch/Buddy/BuddyPlacement.swift BasicNotch/Pokemon/PokeBrawlSprites.swift \
    -o "$RUN/BuddyChecks"
"$RUN/BuddyChecks" "$ROOT/BasicNotch/Resources/Mons.bundle"
