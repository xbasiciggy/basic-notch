# Desktop buddy — 1.3.0 preview

Enable Settings → Buddy or use Show / Hide Desktop Buddy in the sparkle menu. The regular app includes its existing 18 Pokémon and 16 shiny variants. Search by name and select your buddy. The personal Dev sprite collection and private features are not part of this release.

## Roaming and appearance

Your buddy walks in eight directions toward random destinations on its current display, with brief rests. Hovering, dragging, the care menu, sleep, Pause buddy and Reduce Motion stop roaming. Drag it to another display to explore there. Position is saved on arrival, hide and quit; removed displays trigger recovery to an available screen. Roaming is enabled by default, but the buddy itself is opt-in.

The size slider now reaches 10.5, 250% larger than its previous maximum of 3 (3.5×). The sprite region expands with it so the name tag and care controls remain separate. Actual displayed size is limited by the screen. Settings also includes walking speed and 100–300% magnification (200% doubles the rendered size). Magnification is limited to the display's usable area so the panel remains reachable. Idle, walk, attack/play, hurt, and available faint/lie-down poses can be selected. Pikachu additionally offers Shock. Picking up shows a front-facing hurt pose. Missing poses fall back to idle/walk.

## Name tag, XP and care

The name tag shows a nickname or species name, level and XP bar. Click it, hold the sprite for about half a second, right-click → Food, play & sleep, or use Settings → Buddy → Open food, play & sleep menu. Dragging more than a few points cancels the hold gesture.

- Food: berries or an apple, with a food prop and an eating pose where present.
- Play: tennis/beach ball bounce, petting, and Pikachu's Shock action.
- Sleep: put the buddy down for a nap, then use Wake up when ready. Sleeping pauses travel and survives relaunch. Sleep sprites are available for Pikachu and Sylveon; other species use their idle pose with a Zzz indicator.
- Rename: save a nickname of up to 24 characters.

Food grants 10 XP, ball play 15, pet/Shock 5, and waking after a nap of at least one minute grants 5. XP has a shared 10-second reward cooldown; care still works during it. Each 100 XP earns a level, capped at 100. There are no neglect penalties, purchases, or loss of XP. Normal/shiny appearances of the same species share progress. Different species retain separate profiles.

Care state is local, stored under desktopBuddyCare.v1 in the app's existing preferences. It does not replace notch party/Pokédex progress or clear other settings. Transient comments and play actions are not persisted.

## Comments and live activities

Occasional comments appear roughly every 90–150 seconds after an initial delay. Weather remarks use the existing WeatherService report and selected units, with an unavailable message if it has no usable report. No new location permission or network service is added. Turn comments off in Buddy settings. Comments do not announce while paused, sleeping or interacting.

Lightroom and card readouts share the existing services and General → Live activities preferences. Lightroom requires the companion export action. Card progress covers imports performed in BasicNotch. Tethered capture, PTP cameras and transfers performed by other apps remain planned.

## Artwork

Existing roster credits and licenses are retained. Eight additional original sheets were imported unchanged from pinned SpriteCollab revision f663e2331a5f83504d1e7a01573dc53a6708f4c7: normal/shiny Pikachu Shock, Eat and Sleep; normal/shiny Sylveon Sleep. Animation metadata comes from the existing pinned XML and credits cover these actions. Run tools/import_spritecollab.py with that revision to reproduce the curated import.

Source: https://github.com/PMDCollab/SpriteCollab/tree/f663e2331a5f83504d1e7a01573dc53a6708f4c7
Policy: https://github.com/PMDCollab/SpriteCollab#submission-and-use-policy
License: https://creativecommons.org/licenses/by-nc/4.0/

SpriteCollab custom contributions permit noncommercial use with attribution. Original CHUNSOFT/Unspecified records retain their underlying rights; contributor licenses do not grant Pokémon trademark or other third-party rights. No endorsement is implied. Reassess rights before commercial distribution. Full artist credits and license links are in Buddy settings and Mons.bundle.

## Validation and release limits

Run tools/run-checks.sh for existing core checks, display placement, eight-direction sprite decoding, movement speed/arrival/sleep recovery, synthetic row selection and care-state persistence/rewards. Lua integration checks require Lua to be installed.

Validation on October 27, 2026: universal Release build succeeded on Xcode 27.2; 5,358 automated checks passed (278 core, 1,493 placement/sprite, 3,563 movement/directional animation, 24 care/layout). Lua checks were skipped because Lua is unavailable. An isolated app launched, Buddy settings and care controls rendered, nickname editing saved, and feeding visibly advanced XP to 10%. Physical display/Spaces behavior, hold-versus-drag interactions, live weather/device integration and long-running energy use still require hands-on validation. The existing Dev 1.2.3 installation is separate. Local preview packages are ad-hoc signed, not notarized.
