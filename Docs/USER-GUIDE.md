# BasicNotch 1.1.0 — User Guide & Features

A free notch companion for macOS 14 Sonoma or later. This universal app contains both Apple Silicon and Intel executables. It works on a MacBook with a notch, on a Mac without a notch, and on an external display.

## Install and start

1. Open BasicNotch-1.1.0.dmg.
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
- Automatic built-in display selection, a specific display setting, Move to Next Screen, or simultaneous notches on all connected displays. Each has independent hover/tab/pin state and Pokémon; background services are shared.
- Configurable tab visibility and side-wing width.
- Glass, black and other available theme choices, album-color glow, adjustable neon color and intensity.
- Optional opening haptics on supported hardware.
- Optional Launch at login in Settings; errors are shown if macOS rejects registration.
- Version and build number at the bottom of Settings → General, read from the installed app metadata.
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
- Configurable party size (1–6 per display), random party rotation and respawn.
- Whole-sprite movement boundaries plus clipping keep Pokémon, bubbles and battle/catching effects away from closed-notch activity icons and text. Reserved space follows the activity label width.
- Occasional battles, music reactions, speech bubbles and click-to-throw catching behavior.
- Catch history/Pokédex, reset, shiny odds, weather-influenced types and generation filters. Filters apply to the included roster; this is not a complete national Pokédex sprite pack.
- SpriteCollab source revision and individual original contributor logs are bundled under Mons.bundle/CREDITS.md, with the name directory and license. An accessible Credits link is included in the HTML guide.
- The source repository lists CC BY-NC 4.0 terms. This package is prepared for free, noncommercial use with attribution; no endorsement by Nintendo, Game Freak, The Pokémon Company, Chunsoft or contributors is implied. Underlying character/game rights remain with their owners.

## Lightroom Classic export monitor



Requires Lightroom **Classic** on Mac and BasicNotch 1.1.0 or later. This companion is an export post-process action, not a cloud Lightroom plug-in.

### Install once

1. Install and open BasicNotch.
2. Get `BasicNotchExport.lrplugin` from the disk image, extract the separate Lightroom plug-in ZIP, or open the notch → Lightroom → Save Plug-in. Put the entire `.lrplugin` folder somewhere permanent, such as Documents/Lightroom Plug-ins. Keep the Lua files inside it together.
3. In Lightroom Classic choose **File → Plug-in Manager → Add**, select `BasicNotchExport.lrplugin`, and enable it. Some Lightroom versions may show a third-party plug-in notice.
4. Select photos and open Lightroom’s **Export** dialog. Keep your usual **Export To** destination and all image/file settings.
5. Under **Post-Process Actions**, select **BasicNotch Export Monitor** and click **Insert**. Put this action last in the list. Save an export preset with this action included if you want it on future exports.
6. Click **Export**. The closed notch shows a progress ring and processed/total count. Open the notch’s **Lightroom** tab to inspect active/recent jobs or choose **Show Folder**.

### What is monitored

Only exports with this action inserted are monitored. The action reports photos reaching it in Lightroom’s render/post-processing pipeline. It does not rewrite photos or alter export settings. It does not observe every Lightroom task, and cannot prove completion of later cloud uploads/publishing steps or filters placed after it. Its completion means the monitored rendering stage ended.

Multiple jobs can run at once; the compact indicator combines their processed/total counts. The Lightroom tab lists individual jobs with rendered counts, failures and status. Failed renditions continue to report their failure to Lightroom. Cancelled/incomplete jobs are shown as stopped. If updates cease for 45 seconds, BasicNotch shows connection lost instead of reporting success. A new heartbeat can resume the job.

Export completion/failure banners and compact progress can be switched off in BasicNotch Settings. Clear Finished hides completed/stopped history for the current app session; it does not delete photos or the Lightroom records.

### Privacy and troubleshooting

Status snapshots stay on your Mac in `~/Library/Application Support/BasicNotch/LightroomExports/`. They contain a job ID, timestamps, counts, last rendered filename, output folder and an error/status message. They contain no image pixels and the monitor uploads nothing. Other BasicNotch widgets have their own documented providers.

If progress does not appear, check that BasicNotch is running, the plug-in is enabled, and the action was inserted into this export (not just installed in Plug-in Manager). Try a new export after installation. If the status directory cannot be written, the monitor silently stops reporting so it does not break your export. Check Lightroom’s own export results and file access permissions.

Show Folder uses the most recently reported destination folder; a job can export to several folders. Progress counts rendered photos, not bytes or estimated remaining time. Old status files are ignored after seven days; they may be manually deleted after exports finish. The app reads at most the latest 128 snapshots and displays up to 24 jobs.

The plug-in uses Adobe’s documented export filter interface: https://developer.adobe.com/lightroom-classic . Verified on one Mac in Lightroom Classic with a real 63-photo JPEG export, advancing closed-notch Live Activity progress and a completed 63/63 status using the same monitor code in Basic Notch Dev. Other versions and configurations remain preview testing.

### Multiple screens

In BasicNotch Settings → General turn on **Show notch on all connected displays**, or choose **Show on Screen → All Connected Displays** from its sparkle menu. Each screen has independent hovering, tabs, pinning and Pokémon. Export progress, music, files and settings are shared, with one set of background services.

When a display disconnects, its panel and Pokémon timer are removed. In single-screen mode an unavailable selected screen falls back to the automatic display; reconnecting restores that saved choice. Switching to a particular screen turns all-displays mode off.

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

## Desktop buddy (1.3.0 preview)

Enable Settings → Buddy. Choose your Pokémon/shiny appearance, roaming speed, size and magnification. The name tag shows level and XP. Hold the sprite or click its name tag for feeding, ball play, petting, sleep/wake and a nickname. Pikachu has a Shock action. Each species keeps separate local progress; normal and shiny appearances share it.

Optional comments use the existing weather report. Lightroom/card status shares existing services and preferences. Tethered capture and third-party transfers remain planned. See Docs/DESKTOP-BUDDY.md for complete controls, attribution and validation limits.
