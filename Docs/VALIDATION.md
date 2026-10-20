# BasicNotch 1.0.1 validation — October 20, 2026

## Passed

- Universal Release build with Xcode 27 / Swift 6.4: arm64 and x86_64 slices; minimum macOS 14.0.
- Local ad-hoc code signature verification with hardened runtime, camera and Automation entitlements.
- App metadata: stable com.basiciggy.BasicNotch identifier, version 1.0.1/build 2, native icon and menu-bar utility behavior.
- Native UI smoke checks: welcome layout and Open My Notch, all nine tabs, Focus preset/start/reset, Shelf empty state, settings Weather section without portfolio integration, 18-species Pokédex, and visible animated Pokémon.
- The final preview warning change compiled successfully; the package has BasicNotchLocalPreview=true. The warning is conditional so a completed notarized packaging flow can omit it.
- Sprite import checked 18 species, 34 normal/shiny forms and 163 PNG animation sheets, with positive durations and compatible frame/sheet dimensions. Source revision f663e2331a5f83504d1e7a01573dc53a6708f4c7.
- Original sprite credit logs, contributor directory and license included in Mons.bundle. PNG sheets copied unchanged.
- GalleryManagerInbox and PortfolioCompose deleted; source audit found no GalleryManager/PortfolioCompose references in Swift source. Removed its Shelf/card buttons and weather-library reader/settings.
- Installer disk-image checksum verified. Read-only mount confirmed app files match the packaged build and the Applications shortcut points to /Applications.
- Packaging/launcher shell syntax and git diff whitespace checks passed.

## Not established by these checks

- Apple notarization/Gatekeeper approval. No Developer ID signing identity is installed on this Mac. The signed/notarized script branch is prepared but has not been exercised with real credentials.
- Full end-to-end Sony/Tumblr login and publishing, Calendar/camera/location permissions, live music controls, a physical camera card, AirPods, compatible downloads and recorder detection.
- Intel hardware, every macOS 14+ release, every external-display arrangement, long-running performance or every Pokémon animation/catching/battle sequence.
- Redistribution rights for upstream app code and bundled weather photographs. The upstream app had no LICENSE file at revision e85da1a0f5e1e4242d2b01fc51ece5a2e2dbcc8b. Sprite terms and original-game credits are recorded separately; free distribution does not by itself resolve every underlying right.

This is an installable local preview/release candidate, not a claim of completed public-release certification. The user's installed /Applications/BasicNotch.app was not overwritten.
