# BasicNotch 1.0.1 — User Guide & Features

A free notch companion for macOS 14 Sonoma or later. This universal app contains both Apple Silicon and Intel executables. It works on a MacBook with a notch, on a Mac without a notch, and on an external display.

## Install and start

1. Open BasicNotch-1.0.1.dmg.
2. Drag BasicNotch into Applications. Eject the disk image.
3. Open BasicNotch from Applications. Look for the sparkle icon in the menu bar; this utility does not show a Dock icon.
4. Read the welcome window and choose Open My Notch. Hover at the top center of your selected display to open it again.
5. Use the pin button to hold the panel open. Move the pointer away to close an unpinned panel.

This release uses the stable bundle ID com.basiciggy.BasicNotch; settings and optional sign-ins are separate from the old com.local developer prototype.

This supplied build is locally signed, not Apple notarized. macOS may block an app downloaded from the internet. For a copy you trust, try opening it once, then use System Settings → Privacy & Security → Open Anyway and authenticate if macOS offers that option. Organization policies can prohibit this. Do not disable Gatekeeper. A future Developer ID signed and notarized release should use the normal open flow.

## Complete feature list

### Notch and appearance

- Hover to expand; pin to keep open; drag a file onto the notch to open the Shelf.
- Floating panel across Spaces, with support for fullscreen apps where macOS permits.
- Automatic built-in display selection, a specific display setting, and Move to Next Screen.
- Configurable tab visibility and side-wing width.
- Glass, black and other available theme choices, album-color glow, adjustable neon color and intensity.
- Optional opening haptics on supported hardware.
- Optional Launch at login in Settings; errors are shown if macOS rejects registration.
- Menu-bar access to Settings, Getting Started, the User Guide, About, Pokémon respawn and Quit.

### Now Playing

- Apple Music and Spotify track title, artist, album, artwork and progress.
- Play/pause, previous/next, seeking, shuffle and repeat controls.
- Apple Music favorite toggle and Spotify track-link sharing where supported.
- System output volume, with player-volume fallback for fixed-volume outputs such as HDMI.
- Synced lyrics through LRCLIB when a matching song is available.
- Album artwork glow, visualizer and compact closed-notch music activity.
- Requires the installed player and macOS Automation approval for full control and metadata. This app does not stream or download music.

### Sports

- ESPN scoreboards for NFL, NBA, MLB, NHL, college football, WNBA, English Premier League and MLS.
- Favorite teams pinned and highlighted using comma-separated abbreviations in Settings.
- Optional favorite-team scoring and final-score notch alerts.
- Requires internet access; availability, refresh timing and completeness depend on ESPN.

### Gaming

- Optional PlayStation sign-in, friends and current game activity.
- Recent game information where returned by Sony.
- Friend-starts-game alerts.
- Uses unofficial PlayStation mobile endpoints; these can stop working if Sony changes them. Privacy settings can limit visible activity.

### Crypto

- CoinGecko market prices and daily moves; configurable coin list and coin search.
- Detailed coin charts in a separate chart window and price alerts.
- Optional daily movement and price-target notch alerts.
- Quotes and charts depend on CoinGecko availability and rate limits. These are informational widgets, not trading tools.

### Weather and photography

- Open-Meteo current conditions and forecast, saved-city lookup or optional current location.
- Fahrenheit/Celsius setting, weather-matched photo backgrounds and animated rain/snow.
- Sunrise/sunset information, photography suggestions and heuristic sunset-color forecasts.
- Golden-hour countdown in the closed notch and optional sunset alerts.
- Ships with weather backgrounds; no Gallery Manager library or account is needed.
- Sunset-color scores are estimates rather than guarantees of actual conditions.

### File Shelf and clipboard

- Drag files onto the notch, select items, open them, reveal them in Finder and drag them into other apps.
- AirDrop Shelf items through the system sharing interface.
- Remove Shelf references or clear the Shelf without deleting the original files.
- Shelf references persist between launches; they are not backup copies. Moving or deleting the original file can make a reference unavailable.
- Recent copied text: up to 30 items, capped at 5,000 characters each, with click-to-copy, remove, clear and pause controls.
- Clipboard text stays in process memory until quit. Copies marked concealed/transient by supported password managers are skipped; ordinary copied text can still contain sensitive information.
- Optional Tumblr photo posts with caption and other compose controls. Configure your own Tumblr application key/secret and sign in from Settings → Accounts. The redirect URL is shown there.
- No Basiciggy/Gallery Manager upload, portfolio composer, portfolio library access or portfolio weather-photo integration remains.

### Camera-card import

- Detects mounted camera volumes containing a DCIM folder and counts new photos/videos.
- One-click local copy into Pictures → Card Imports, with progress, cancellation, Finder reveal and card eject.
- Handles common JPEG, HEIC, PNG, TIFF, RAW and video extensions.
- Records imports by name, size and modification date to reduce duplicates. This is not a content-hash deduplication or verified-backup system; check your copies before erasing a card.
- Compact import/card activity and optional inserted/imported alerts.
- Import stays local; Tumblr posting is a separate, explicit action from the Shelf.

### Focus and everyday tools

- Focus timer with 5, 15, 25, 45 and 60 minute presets, start/pause/reset, compact progress and completion sound/alert.
- CPU usage and history, RAM usage, network transfer rates/history and top memory-using apps on hover.
- Mac battery level and charging state.
- AirPods/Bluetooth headphone battery information when macOS reports it, with optional connection alerts.
- Upcoming Calendar event chip and five-minute reminders, with Calendar permission.
- Camera mirror with Camera permission; the camera stops when the mirror view is dismissed.
- Download/AirDrop progress and completion alerts for transfers that publish compatible macOS file-progress data.
- Best-effort screen-recording timer for Apple's recorder/QuickTime; it does not start or save recordings and does not detect every recorder.
- Local Claude Code token-usage summaries from this Mac's session logs: current estimated five-hour window, today, last week and top model. The usage bar is a local estimate against a configured budget or recent peak, not an authoritative account quota.

### Pokémon companions

- 18 bundled species: Bulbasaur, Charmander, Squirtle, Pikachu, Jigglypuff, Gengar, Eevee, Dratini, Cyndaquil, Mudkip, Turtwig, Lucario, Glaceon, Zorua, Sylveon, Rowlet, Mimikyu and Snom.
- 16 shiny variants, walking/idle animations and supported battle/hurt/faint animations.
- Configurable party size (1–6), random party rotation and respawn.
- Occasional battles, music reactions, speech bubbles and click-to-throw catching behavior.
- Catch history/Pokédex, reset, shiny odds, weather-influenced types and generation filters. Filters apply to the included roster; this is not a complete national Pokédex sprite pack.
- SpriteCollab source revision and individual original contributor logs are bundled under Mons.bundle/CREDITS.md, with the name directory and license. An accessible Credits link is included in the HTML guide.
- The source repository lists CC BY-NC 4.0 terms. This package is prepared for free, noncommercial use with attribution; no endorsement by Nintendo, Game Freak, The Pokémon Company, Chunsoft or contributors is implied. Underlying character/game rights remain with their owners.

## Permissions, accounts and privacy

- Automation: Music/Spotify metadata and controls. Manage it in System Settings → Privacy & Security → Automation.
- Calendar: upcoming events/reminders. Declining disables those integrations.
- Camera: requested when using the mirror.
- Location: optional; use a saved city if you prefer.
- Files and folders/removable volumes: macOS can ask for access when monitoring Downloads or importing camera media.
- Launch at login: managed in Settings and macOS Login Items.
- Optional Sony/Tumblr tokens and the Tumblr consumer secret are stored in Keychain. Tumblr consumer key and selected blog, preferences, file references and import bookkeeping use local preferences/Application Support.
- Music lookup/artwork, ESPN, CoinGecko, Open-Meteo/geocoding, LRCLIB and optional Sony/Tumblr connections use their respective online services. Images may load from provider/CDN URLs. Song metadata is sent for lyric matching; city or location coordinates are sent for weather. There is no custom BasicNotch analytics/backend in this source.
- Local Claude Code usage scanning reads local logs to calculate summaries; it is not an upload feature.
- Closing the notch leaves this menu-bar app running. Choose Quit BasicNotch to stop it.

## Troubleshooting

- No window or Dock icon: use the sparkle menu → Open Notch or Getting Started.
- Wrong display: use Show on Screen or Settings → General → Screen.
- No music controls: play a song in Music or Spotify and check Automation permission.
- No online data: check connectivity and provider availability. Public services can rate-limit requests.
- Empty PlayStation/Tumblr: complete the optional account setup; the core app needs neither account.
- No camera/calendar/location: check the relevant macOS permission; permission denial does not imply app failure.
- Camera/card progress: keep the card connected until copying finishes, reveal the destination, and verify files before erasing originals.
- Pokémon do not appear: enable them in Settings and choose Respawn Pokémon from the menu bar.
- Clipboard privacy: use Pause or Clear in Shelf, or quit to discard the history.
- Uninstall: turn off Launch at login, quit the app, then move BasicNotch from Applications to Trash. System preferences, import bookkeeping and Keychain records may remain; log out of optional accounts first if desired.

## Release status

This is a locally signed universal release candidate, not a notarized public release. Compile/resource/signature checks are recorded separately in VALIDATION.md. Live account, physical device, Intel-hardware and all supported macOS-version flows have not all been end-to-end tested. There is no auto-updater: replace the app manually with future versions.

For warning-free public downloads, the maintainer must supply a Developer ID Application identity, enable hardened runtime with camera/Automation entitlements, submit to Apple notary service and staple the ticket. tools/package-release.sh supports that flow using SIGN_IDENTITY and NOTARY_PROFILE. No private credentials are included in the app.

The upstream app repository contained no LICENSE file at the recorded revision. Confirm the owner's redistribution terms before publishing a modified source or binary release; the SpriteCollab asset license is recorded separately. Bundled weather-image provenance also needs confirmation before a broad public release.
