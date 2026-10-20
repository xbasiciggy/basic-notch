# BasicNotch 1.1.1 validation — October 20, 2026

## Checks performed

- Universal Release build with Xcode 27: arm64 and x86_64, minimum macOS 14.0, version 1.1.1/build 4.
- Local ad-hoc signature with hardened runtime and camera/Automation entitlements.
- 282 Swift core checks: all-display selection, individual selection, missing-display fallback, empty/deduplicated display lists, whole-sprite bounds under varied sprite sizes and asymmetric activity reservations, snapshot validation, corrupt/oversized input, stale heartbeat handling, historical/duplicate notification suppression, concurrent export counts/progress, finished-job clearing and Lua-to-Swift fixture decoding.
- Nine Lua 5.1 checks using Lightroom SDK test doubles: plug-in identity, successful renders, XML escaping, failed renditions propagated to Lightroom, incomplete/cancelled jobs, exception recording/rethrow, and monitor write failures that leave exports unaffected. The action emits real plist fixtures which the Swift monitor decodes.
- Native UI checks in an isolated test app: welcome/open notch, Lightroom tab empty state and setup buttons, all ten tab settings, all-displays toggle disabling the single-screen picker, and the General footer reporting Version 1.1.0 · Build 3. The user's installed app was not replaced for these checks.
- Screen panels share one set of app services and polling loops. Hover, pin, tabs, cursor, geometry and Pokémon are local to each panel. Removal cancels closing work, stops its Pokémon timer and releases its hosted content.
- Closed-notch boundaries use measured activity widths, conservative initial reservations, full animation width/center-offset margins and a horizontal rendering mask to contain sprites, bubbles, battle HUD and catch effects.
- Previous artwork resource checks: 18 species, 34 normal/shiny forms, 163 PNG animation sheets with compatible dimensions/durations; original credits and license retained. Sprite PNGs are unchanged by this update.

## Lightroom connection fix

- Lightroom appData points inside Adobe/Lightroom. Resolve the shared macOS snapshot directory from the home folder instead.
- Lightroom omits Lua os.rename. Close the temporary file, then publish with SDK delete/move. Tests now remove os.rename/os.remove and model move refusing existing destinations.
- Compact Live Activity identifies the count as `Lr processed/total`, with an accessible Lightroom label. Existing Live Activity preferences remain respected.
- Public build keeps its existing identity, curated sprites and removal of Gallery Manager. Personal Dev features and settings are not included.

## Preview limits

- A real Lightroom Classic 63-photo JPEG export verified advancing Live Activity counts, shared snapshots and completed 63/63 with zero errors on one Mac using the same monitor code in Basic Notch Dev. Other Lightroom versions/configurations remain untested.
- Progress reports the monitored rendering/post-processing stage only. Later publish/upload steps and exports without this action are not observed. Interrupted jobs need a new heartbeat to resume.
- Physical multi-monitor use, unplug/replug, different scaling arrangements and every fullscreen/Spaces configuration still need hardware checks. Selection/fallback is covered by automated checks; the setting itself was checked through the UI.
- Intel hardware, every supported macOS release, all optional account/device integrations and long-running operation have not all been tested.
- The public preview is locally signed, not Apple notarized. No Developer ID identity is installed on this Mac. The signed/notarized packaging branch remains untested with real credentials.
- Upstream code, weather-image provenance and underlying Pokémon/game rights are not established by these build checks. SpriteCollab attribution and its published noncommercial terms are included separately; free distribution is not proof of all underlying rights.

## Reproduce

Run `tools/run-checks.sh` on a Mac with Xcode installed. To include the Lua checks, set `LUA_BIN` to a Lua 5.1 executable. Build/install artifacts with `tools/package-release.sh`. Plugin setup is in `Docs/LIGHTROOM-SETUP.md`.
