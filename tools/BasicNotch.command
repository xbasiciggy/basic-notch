#!/bin/zsh
# Double-click to open BasicNotch.
# Hold Option while double-clicking (or run with --update) to rebuild from the source first.

PROJECT="$HOME/Documents/GitHub/BasicNotch"
APP="/Applications/BasicNotch.app"
XCODE_DEV="$(xcode-select -p)"
OUT="$HOME/Library/Developer/Xcode/DerivedData/BasicNotch-cli"

option_held() {
  /usr/bin/osascript -l JavaScript -e 'ObjC.import("AppKit"); ($.NSEvent.modifierFlags & $.NSEventModifierFlagOption) ? "1" : "0"' 2>/dev/null
}

if [[ "$1" == "--update" || "$(option_held)" == "1" || ! -d "$APP" ]]; then
  echo "Building BasicNotch from $PROJECT …"
  if DEVELOPER_DIR="$XCODE_DEV" xcodebuild -project "$PROJECT/BasicNotch.xcodeproj" -target BasicNotch \
      -configuration Release SYMROOT="$OUT" OBJROOT="$OUT/obj" build -quiet; then
    pkill -x BasicNotch 2>/dev/null
    sleep 0.5
    ditto "$OUT/Release/BasicNotch.app" "$APP"
    echo "Updated $APP"
  else
    echo "Build failed — opening the existing app instead."
  fi
fi

# Restart so you always get exactly one copy.
pkill -x BasicNotch 2>/dev/null && sleep 0.5
open "$APP"

# Close the Terminal window this script opened.
osascript -e 'tell application "Terminal" to close (every window whose name contains "BasicNotch.command")' >/dev/null 2>&1 &
exit 0
