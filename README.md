# BasicNotch

Free native Mac notch companion. macOS 14 or later; universal Apple Silicon + Intel build.

## Install

Open `dist/preview/BasicNotch-1.0.1.dmg`, drag BasicNotch to Applications and launch it. Use the sparkle menu in the menu bar to access Settings, Getting Started, the full User Guide, or Quit. There is no Dock icon.

The local package is ad-hoc signed, not notarized. A Developer ID signed and Apple-notarized build is needed for the usual warning-free internet download flow.

## Features

Music/Spotify controls and lyrics, sports scores, optional PlayStation friends, crypto charts and alerts, weather and golden hour, file Shelf, in-memory clipboard history, local camera-card imports, optional Tumblr posts, focus timer, system stats, battery and AirPods status, calendar reminders, camera mirror, compatible download progress, best-effort recording timer, local Claude Code usage estimates, and Pokémon companions with catching, battles and Pokédex.

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

## Artwork refresh

```sh
python3 tools/import_spritecollab.py f663e2331a5f83504d1e7a01573dc53a6708f4c7
```

Imports the curated roster, validates sheet dimensions/timing and retains credits. Omit the SHA only to intentionally update to the upstream master revision. The older `import_pokebrawl_sprites.py` supports its original separate sprite-project format and can replace this roster; retain the appropriate credits for any replacement artwork.

Original source: https://github.com/xbasiciggy/basic-notch . Artwork source: https://github.com/PMDCollab/SpriteCollab . See the guide for release/rights notes and third-party service dependencies.
