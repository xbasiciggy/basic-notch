# BasicNotch Lightroom Classic Export Monitor

Requires Lightroom **Classic** on Mac and BasicNotch 1.1.0 or later. This companion is an export post-process action, not a cloud Lightroom plug-in.

## Install once

1. Install and open BasicNotch.
2. Get `BasicNotchExport.lrplugin` from the disk image, extract the separate Lightroom plug-in ZIP, or open the notch → Lightroom → Save Plug-in. Put the entire `.lrplugin` folder somewhere permanent, such as Documents/Lightroom Plug-ins. Keep the Lua files inside it together.
3. In Lightroom Classic choose **File → Plug-in Manager → Add**, select `BasicNotchExport.lrplugin`, and enable it. Some Lightroom versions may show a third-party plug-in notice.
4. Select photos and open Lightroom’s **Export** dialog. Keep your usual **Export To** destination and all image/file settings.
5. Under **Post-Process Actions**, select **BasicNotch Export Monitor** and click **Insert**. Put this action last in the list. Save an export preset with this action included if you want it on future exports.
6. Click **Export**. The closed notch shows a progress ring and processed/total count. Open the notch’s **Lightroom** tab to inspect active/recent jobs or choose **Show Folder**.

## Updating from 1.1.0

Replace both the app and companion plug-in with 1.1.1. In Lightroom Plug-in Manager, expand Plug-in Author Tools and click Reload Plug-in, then run a new export. This fixes the shared status folder and a file operation unavailable inside Lightroom. In BasicNotch Settings → General → Live activities, enable **Lightroom Classic export progress** to see the cyan progress ring and `Lr processed/total` count.

## What is monitored

Only exports with this action inserted are monitored. The action reports photos reaching it in Lightroom’s render/post-processing pipeline. It does not rewrite photos or alter export settings. It does not observe every Lightroom task, and cannot prove completion of later cloud uploads/publishing steps or filters placed after it. Its completion means the monitored rendering stage ended.

Multiple jobs can run at once; the compact indicator combines their processed/total counts. The Lightroom tab lists individual jobs with rendered counts, failures and status. Failed renditions continue to report their failure to Lightroom. Cancelled/incomplete jobs are shown as stopped. If updates cease for 45 seconds, BasicNotch shows connection lost instead of reporting success. A new heartbeat can resume the job.

Export completion/failure banners and compact progress can be switched off in BasicNotch Settings. Clear Finished hides completed/stopped history for the current app session; it does not delete photos or the Lightroom records.

## Privacy and troubleshooting

Status snapshots stay on your Mac in `~/Library/Application Support/BasicNotch/LightroomExports/`. They contain a job ID, timestamps, counts, last rendered filename, output folder and an error/status message. They contain no image pixels and the monitor uploads nothing. Other BasicNotch widgets have their own documented providers.

If progress does not appear, check that BasicNotch is running, the plug-in is enabled, and the action was inserted into this export (not just installed in Plug-in Manager). Try a new export after installation. If the status directory cannot be written, the monitor silently stops reporting so it does not break your export. Check Lightroom’s own export results and file access permissions.

Show Folder uses the most recently reported destination folder; a job can export to several folders. Progress counts rendered photos, not bytes or estimated remaining time. Old status files are ignored after seven days; they may be manually deleted after exports finish. The app reads at most the latest 128 snapshots and displays up to 24 jobs.

The plug-in uses Adobe’s documented export filter interface: https://developer.adobe.com/lightroom-classic . Verified on a Mac in Lightroom Classic with a 63-photo JPEG export, advancing closed-notch Live Activity progress and a completed 63/63 status. Other Lightroom versions and configurations remain preview testing.

## Multiple screens

In BasicNotch Settings → General turn on **Show notch on all connected displays**, or choose **Show on Screen → All Connected Displays** from its sparkle menu. Each screen has independent hovering, tabs, pinning and Pokémon. Export progress, music, files and settings are shared, with one set of background services.

When a display disconnects, its panel and Pokémon timer are removed. In single-screen mode an unavailable selected screen falls back to the automatic display; reconnecting restores that saved choice. Switching to a particular screen turns all-displays mode off.
