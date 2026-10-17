# BasicNotch

A notch companion for MacBooks. It sits over the camera notch, opens when you hover it, and shows whatever you care about: music, sports scores, PlayStation friends, crypto prices, weather, a file shelf, and a party of Pokémon that wander along the bar and sometimes battle each other.

Built with SwiftUI and AppKit. macOS 14 or later. No third-party packages.

## Features

- **Now Playing**: Spotify and Apple Music with artwork, controls, volume, synced lyrics (from [LRCLIB](https://lrclib.net)), and a glow in the album's colors.
- **Sports**: live scores from ESPN for NFL, NBA, MLB, NHL, college football, WNBA, Premier League and MLS, with favorite teams pinned and alerts when they score.
- **Gaming**: your PlayStation friends and what they're playing.
- **Crypto**: prices and charts from CoinGecko, add any coin, price alerts.
- **Weather**: forecast from [Open-Meteo](https://open-meteo.com), current location or a saved city, golden-hour and sunset-quality hints.
- **Shelf**: drop files to keep them handy, recently copied text, and posting images to Tumblr.
- **Focus timer, system stats, AirPods battery, calendar heads-up, camera mirror.**
- **Pokémon**: they walk, catch Poké Balls, battle and fill a Pokédex.

## Build

You need Xcode 16 or later.

```bash
git clone <this repo>
cd BasicNotch
open BasicNotch.xcodeproj    # then Run (⌘R)
```

It builds with ad-hoc signing out of the box. Because an ad-hoc signature changes with every build, macOS will keep asking for Keychain and privacy permissions after each update. To avoid that, create `Config/Local.xcconfig` (untracked) with your own developer identity:

```
CODE_SIGN_IDENTITY = Apple Development
CODE_SIGN_STYLE = Manual
DEVELOPMENT_TEAM = YOUR_TEAM_ID
```

`tools/BasicNotch.command` rebuilds and installs the app to `/Applications`.

## Pokémon sprites

The sprites are not included, because they are Nintendo/Game Freak artwork. Without them the app works normally and the Pokémon simply don't appear. To add them, run the importer against a project that has PMD-style sprite sheets and a `public/data.js` roster:

```bash
python3 tools/import_pokebrawl_sprites.py /path/to/your/sprite-project
```

It writes `BasicNotch/Resources/Mons.bundle`, which is git-ignored.

## Services and permissions

| What | Needs |
|---|---|
| Music, Spotify | macOS Automation permission, asked on first use |
| Calendar, camera, location | Asked on first use |
| PlayStation friends | Signing in on Sony's own page. This uses the PlayStation mobile app's unofficial endpoints, which Sony can change at any time |
| Tumblr | Your own Tumblr app: register one at tumblr.com/oauth/apps, set its redirect URL to the one shown in Settings, and paste its key and secret |
| Portfolio upload | Optional hand-off to a companion app called Gallery Manager; ignore the Portfolio button if you don't use it |

Logins and API secrets are stored in the macOS Keychain. Nothing is sent anywhere except the services listed above.

## Not affiliated

Not affiliated with or endorsed by Nintendo, Game Freak, The Pokémon Company, Sony, Spotify, Apple, or Tumblr. Names and artwork belong to their owners.
