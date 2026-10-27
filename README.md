# BasicNotch

Free native Mac notch companion. macOS 14 or later; universal Apple Silicon + Intel build.

## Download for Mac

[Download the Mac installer (.dmg)](https://github.com/xbasiciggy/basic-notch/releases/download/v1.1.1-preview.1/BasicNotch-1.1.1.dmg) · [All preview downloads and release notes](https://github.com/xbasiciggy/basic-notch/releases/tag/v1.1.1-preview.1)

Open the DMG, drag BasicNotch into Applications, then launch it. This free preview supports macOS 14+ on Apple Silicon and Intel. It is locally signed and **not Apple notarized**, so macOS may show a security warning. Read the release notes and included installation notice before installing.

## Install

Open `dist/preview/BasicNotch-1.1.1.dmg`, drag BasicNotch to Applications and launch it. Use the sparkle menu in the menu bar to access Settings, Getting Started, the full User Guide, or Quit. There is no Dock icon.

The local package is ad-hoc signed, not notarized. A Developer ID signed and Apple-notarized build is needed for the usual warning-free internet download flow.

## Features

Lightroom Classic export monitoring, simultaneous notches on multiple displays, Pokémon boundaries that protect activity text, Music/Spotify controls and lyrics, sports scores, optional PlayStation friends, crypto charts and alerts, weather and golden hour, file Shelf, in-memory clipboard history, local camera-card imports, optional Tumblr posts, focus timer, system stats, battery and AirPods status, calendar reminders, camera mirror, compatible download progress, best-effort recording timer, local Claude Code usage estimates, and Pokémon companions with catching, battles and Pokédex.

Includes 18 Pokémon and 16 shiny variants from SpriteCollab, with unchanged PNG sheets, original credit logs, contributor names, license and a pinned source revision. Artwork terms are noncommercial and attribution is required; see [credits](Docs/SPRITE-CREDITS.md). No endorsement is implied.

Gallery Manager/Basiciggy portfolio upload and portfolio weather-library access have been removed.

See [User Guide](Docs/USER-GUIDE.md) for all features, setup, privacy, limits and troubleshooting, and [Validation](Docs/VALIDATION.md) for checks actually performed.

## Build and package

Requires Xcode with a compatible macOS SDK (tested with Xcode 27). No third-party Swift dependencies.

```sh
tools/package-release.sh
```

Creates a universal `.app`, ZIP, drag-to-Applications DMG, user guide and SHA-256 checksums in `dist/preview/` (or `dist/release/` for notarized builds).

For a public notarized build, import your Developer ID Application certificate and configure a notarytool Keychain profile first, then run:

```sh
SIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)' NOTARY_PROFILE=BasicNotch tools/package-release.sh
```

The script signs with hardened runtime and camera/Automation entitlements, submits to Apple, staples and validates tickets, and assesses the app. It does not publish, install into Applications or modify an existing app. Do not put signing secrets in the source tree.

## Lightroom export monitor

Install the companion `BasicNotchExport.lrplugin` from the DMG or separate plug-in ZIP. In Lightroom Classic, add it with File → Plug-in Manager, then insert its action under Export → Post-Process Actions. It reports rendering progress locally without changing export settings or image files. Only exports with this action are tracked; later publishing/upload steps are not tracked. See [setup guide](Docs/LIGHTROOM-SETUP.md).

## Multiple displays

Settings → General → Show notch on all connected displays enables simultaneous notches. Each display has independent hover, pin, tab and Pokémon state. Music, export progress and other app services are shared. Display removal closes that panel and stops its Pokémon timer.

Version and build appear at the bottom of Settings → General.

## Checks

```sh
tools/run-checks.sh
```

Set `LUA_BIN` to a Lua 5.1 executable to include the Lightroom action tests and Lua-to-Swift snapshot checks. Pure Swift checks cover display selection/fallback, sprite boundaries, malformed snapshots, stale heartbeats, concurrent jobs and completion notifications. A real 63-photo Lightroom Classic export verified Live Activity progress and completion on one Mac. Other Lightroom versions and physical multi-monitor testing remain preview checks.

## Artwork refresh

```sh
python3 tools/import_spritecollab.py f663e2331a5f83504d1e7a01573dc53a6708f4c7
```

Imports the curated roster, validates sheet dimensions/timing and retains credits. Omit the SHA only to intentionally update to the upstream master revision. The older `import_pokebrawl_sprites.py` supports its original separate sprite-project format and can replace this roster; retain the appropriate credits for any replacement artwork.

Original source: https://github.com/xbasiciggy/basic-notch . Artwork source: https://github.com/PMDCollab/SpriteCollab . See the guide for release/rights notes and third-party service dependencies.

## Desktop buddy preview (1.3.0)

Settings → Buddy adds eight-direction roaming, Pokémon/shiny selection, pickup reactions, animation and magnification controls. A name tag shows level/XP. Hold the buddy or click its tag for food, ball play, petting and sleep; each species keeps its own nickname and progress. Pikachu has its actual Shock animation. Optional comments use the existing weather report, and Lightroom/card status shares the existing services.

See [setup, attribution and validation limits](Docs/DESKTOP-BUDDY.md). The regular app uses its existing 18-species roster; private Dev artwork and data are excluded. The public download linked above still points to the older release. Universal 1.3.0 preview builds and 5,358 automated checks pass; the guide lists remaining manual UI/device checks.
