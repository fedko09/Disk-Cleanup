Disk Cleanup GUI – PowerShell Edition
=====================================

Overview
--------
Disk Cleanup GUI is a portable Windows 10/11 utility built in PowerShell
with a WinForms interface. It scans common junk locations and shows you
a sortable list of candidate files so you can safely reclaim disk space.

The tool is designed to be technician-friendly:
- No installer required
- Can be run as a .ps1 or wrapped as an .exe
- Visual feedback while scanning and deleting (loading overlay + log window)

What it Does
------------
- Scans user and system temp folders
- Finds old files in Downloads (older than X days)
- Cleans browser caches (Chrome, Edge, Brave, Vivaldi, Opera, Firefox)
- Cleans Windows and application log/cache locations
- Optionally removes heavy crash/rollback data (Ultra mode)

You can review everything in a grid, select individual items or “Select All
(visible)”, and delete with a single click. A log pane at the bottom shows
what was scanned, what was deleted, and any failures (with error messages).

Profiles / Levels
-----------------
The tool uses 3 levels of aggressiveness:

1. Safe
   - User temp folder
   - LocalAppData temp folder
   - Windows temp folder
   - Downloads older than N days (configurable)

2. Aggressive
   - Everything in Safe
   - Browser caches:
     * Chrome, Edge, Brave, Vivaldi, Opera GX, Firefox profiles
   - Common app/system logs & caches:
     * Windows Error Reporting
     * Windows Update cache (SoftwareDistribution\Download)
     * Discord cache
     * Steam logs
     * NVIDIA installer cache

3. Ultra (dangerous)
   - Crash dump files (MEMORY.DMP, Minidump)
   - Windows.old (previous OS install)
   - Intended for machines that no longer need rollback or crash analysis
   - Explicit warning is shown before enabling

UI Layout and Controls
----------------------
Top area:
- Downloads: older than (days)
  * Numeric control; only Downloads older than this are included.
- Profile:
  * Safe / Aggressive radio buttons
- Ultra (dangerous)
  * Checkbox to include Ultra locations

Left sidebar filters:
- All                  -> Show everything for the chosen profile/level
- Temp + Downloads     -> Only temp & old Downloads
- Temp only            -> Only temp locations
- Downloads only       -> Only old Downloads
- Browser Cache        -> Only browser caches
- Logs / Caches        -> App/system logs and caches
- Windows Update       -> Windows Update cache only
- Ultra only           -> Ultra locations only (dumps, Windows.old)

Main grid:
- Columns:
  * [ ] Select  – Checkbox per file
  * Name        – File name
  * Category    – Logical source (e.g. “Chrome Cache”)
  * Level       – Safe / Aggressive / Ultra
  * Size        – Human-readable size
  * Last Modified
  * Full Path
- Features:
  * Click column headers to sort (ascending/descending)
  * Filters and profile changes automatically clear selections
  * Selections are limited to visible rows when using the sidebar filters

Bottom area:
- Select All (visible)   -> Toggles checkboxes for the currently filtered view
- Delete Selected        -> Deletes all selected files
- Rescan                 -> Re-runs the scan with current settings
- Close                  -> Closes the application
- Selected size:         -> Shows total size of all selected files

Log pane:
- Timestamped entries for:
  * Scan start / end and counts
  * Profile/filter changes
  * Deleted files (summary)
  * Failures with exception messages

Loading Overlay
---------------
During heavy actions (large scans or bulk deletes), the tool shows an overlay
panel on top of the grid:

- Text: “Working, please wait…”
- Marquee progress bar
- Wait cursor

This makes it clear the app is busy even if the UI message loop is blocked
by the scan or delete operation.

Running the Tool
----------------
Option 1: PowerShell script
- Right-click PowerShell and choose “Run as administrator”.
- Navigate to the script folder.
- Run:
  powershell.exe -ExecutionPolicy Bypass -File .\DiskCleanup-GUI.ps1

Option 2: EXE wrapper
- Use a PS-to-EXE packager (e.g. PS2EXE) to build DiskCleanup.exe that
  embeds DiskCleanup-GUI.ps1.
- Keep the original .ps1 and a small launcher .cmd in the same folder for
  troubleshooting or environments where EXE execution is restricted.

Notes & Recommendations
-----------------------
- For system-wide cleanup (Windows temp, Windows Update cache, Ultra mode),
  running as administrator is strongly recommended.
- Ultra mode is intended for systems that no longer need:
  * Crash analysis
  * Previous Windows installation rollbacks
- Always review items before deleting. The tool gives you granular control:
  you can filter by category and sort by size/date/path.

--------------------------------------------------------
Script & Utility by:
Bogdan Fedko
TechBootUp
--------------------------------------------------------
