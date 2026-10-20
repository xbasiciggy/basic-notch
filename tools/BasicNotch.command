#!/bin/bash
# Source checkout helper. Most people should install the prebuilt DMG instead.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [[ "${1:-}" == '--update' || ! -d "$ROOT/dist/preview/BasicNotch.app" ]]; then
    "$ROOT/tools/package-release.sh"
fi
open "$ROOT/dist/preview/BasicNotch.app"
