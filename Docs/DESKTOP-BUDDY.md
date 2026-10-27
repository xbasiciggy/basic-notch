# Desktop buddy preview — 1.2.0

Enable Settings → Buddy → Show Sylveon on the desktop, or use the sparkle menu's Show / Hide Desktop Buddy command. The buddy starts disabled so existing installations retain their layout.

Drag the sprite to move it between displays. The full panel stays within a display's usable area when released, and its position survives relaunch. A removed display causes the buddy to return to an available display. Reset position places it at the lower-right of the main display. It floats above normal windows and follows Spaces.

Right-click for pause/resume, settings, reset and hide. Settings includes idle/walk/react-to-activity, size, and activity visibility. Reduce Motion disables animation. Hiding destroys the panel and its animation timeline. The buddy is independent of the existing notch Pokémon and their game state.

## Live activities

The panel observes the same LightroomExportService and CardIngestService as the notch; it starts no extra scanning or monitoring services. It can display simultaneous Lightroom rendering and card-import progress. General → Live activities preferences also apply. React-to-activity uses the walk animation while either service reports work.

Lightroom requires the existing export action: see LIGHTROOM-SETUP.md. Card detection requires a mounted volume containing DCIM. Progress represents imports initiated in BasicNotch, not copies performed by other applications. A mounted USB camera may qualify if exposed as such a volume; tethered capture, PTP camera connections and third-party transfer monitoring remain planned. This feature does not start camera capture or automatically copy files.

## Artwork verification

No new asset download is required: the existing Mons.bundle contains Sylveon (0700), with a credit record explicitly marked CC_BY-NC_4 for Idle and Walk, dated 2024-07-04, contributor 544245909639397378, resolved to baronessfaron in credit_names.txt. The source revision is f663e2331a5f83504d1e7a01573dc53a6708f4c7:
https://github.com/PMDCollab/SpriteCollab/tree/f663e2331a5f83504d1e7a01573dc53a6708f4c7/sprite/0700

Upstream submission/use policy checked October 27, 2026:
https://github.com/PMDCollab/SpriteCollab/blob/master/README.md
https://creativecommons.org/licenses/by-nc/4.0/

Use is noncommercial with attribution. Original PNG sheets and credit logs remain unchanged; the existing renderer crops frames at runtime. Attribution and license links appear in Buddy settings. Full credits and license remain bundled. The buddy deliberately selects custom Sylveon artwork rather than expanding use of the roster's CHUNSOFT/Unspecified original-game assets. The existing roster is unchanged. Contributor licenses do not grant underlying Pokémon trademark or other third-party rights; no endorsement is implied. Reassess rights before commercial distribution.

## Validation and remaining hardware checks

Automated checks cover multi-display position containment, negative display coordinates, disconnected-screen recovery, an empty display list, and loading/timing the selected sprite sheets with their explicit credit record. Existing core regression checks run alongside these.

Manual preview checks still required: drag across physical displays, disconnect/reconnect, Spaces/fullscreen behavior, VoiceOver, long-running energy use, and actual Lightroom/card activity in the buddy UI. No new physical-camera or Lightroom export was initiated during this implementation. The existing Lightroom host verification predates this feature.

The packaged preview is locally ad-hoc signed, not Apple notarized. Intel compilation does not constitute testing on Intel hardware.

Validation performed October 27, 2026: Debug build succeeded; universal Release build succeeded for arm64 and x86_64 with Xcode 27.2. 278 existing Swift core checks and 1,493 buddy checks passed. Lua checks were skipped because Lua was unavailable. The release script verified the ad-hoc signature and produced app ZIP, DMG, companion Lightroom plug-in ZIP and SHA-256 checksums. The local baseline was confirmed against GitHub main at 1568fa066cc92cc20cf4a75c9b79ee315613afda. A pre-existing Bash 3 empty-array failure in run-checks.sh was corrected so the no-Lua check path works.
