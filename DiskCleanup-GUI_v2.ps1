<# 
    DiskCleanup-GUI.ps1
    GUI-based cleaner for Windows

    Profiles:
      - Safe: Temp, LocalApp Temp, Windows Temp, old Downloads
      - Aggressive: + browser caches, Windows / app logs & caches
      - Ultra (opt-in): crash dumps, Windows.old, etc.

    UI:
      - Top: Safe / Aggressive profile + Ultra toggle
      - Left: filter buttons:
          * All
          * Temp + Downloads
          * Temp only
          * Downloads only
          * Browser Cache
          * Logs / Caches
          * Windows Update
          * Ultra only
      - Grid: single list with checkboxes & delete
        * Column headers clickable to sort
      - Bottom: log/output area showing actions and errors
      - Overlay panel with "Loading..." + marquee progress during heavy work

    Performance:
      - Get-CleanupCandidates only scans locations for the active profile:
        * Safe  -> Safe locations only
        * Agg   -> Safe + Aggressive (+ Ultra if enabled)
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

#-------------------------
# Helper: format size
#-------------------------
function Format-Size {
    param([long]$Bytes)

    if     ($Bytes -ge 1GB) { return ("{0:N2} GB" -f ($Bytes / 1GB)) }
    elseif ($Bytes -ge 1MB) { return ("{0:N2} MB" -f ($Bytes / 1MB)) }
    elseif ($Bytes -ge 1KB) { return ("{0:N2} KB" -f ($Bytes / 1KB)) }
    else                    { return ("{0} B"    -f  $Bytes) }
}

#-------------------------
# Get candidate files
#-------------------------
function Get-CleanupCandidates {
    param(
        [int]$DownloadsMinAgeDays = 30,
        [string]$ProfileMode = "Safe",   # "Safe" or "Aggressive"
        [bool]$IncludeUltra = $false
    )

    $now = Get-Date
    $cutoffDownloads = $now.AddDays(-$DownloadsMinAgeDays)

    $locations = @()

    # --- SAFE: temp + downloads ---
    $locations += @(
        # Temp
        [PSCustomObject]@{
            Path         = $env:TEMP
            Category     = "User Temp"
            Group        = "Temp"
            Profile      = "Safe"
            Ultra        = $false
            AgeCutoff    = $null
            LocationType = "Directory"
            Recurse      = $true
        },
        [PSCustomObject]@{
            Path         = "$env:LOCALAPPDATA\Temp"
            Category     = "LocalApp Temp"
            Group        = "Temp"
            Profile      = "Safe"
            Ultra        = $false
            AgeCutoff    = $null
            LocationType = "Directory"
            Recurse      = $true
        },
        [PSCustomObject]@{
            Path         = (Join-Path $env:WINDIR "Temp")
            Category     = "Windows Temp"
            Group        = "Temp"
            Profile      = "Safe"
            Ultra        = $false
            AgeCutoff    = $null
            LocationType = "Directory"
            Recurse      = $true
        },
        # Old Downloads
        [PSCustomObject]@{
            Path         = "$env:USERPROFILE\Downloads"
            Category     = "Downloads (old)"
            Group        = "Downloads"
            Profile      = "Safe"
            Ultra        = $false
            AgeCutoff    = $cutoffDownloads
            LocationType = "Directory"
            Recurse      = $true
        }
    )

    # --- AGGRESSIVE: Browser caches ---
    $locations += @(
        [PSCustomObject]@{
            Path         = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache"
            Category     = "Chrome Cache"
            Group        = "Browser"
            Profile      = "Aggressive"
            Ultra        = $false
            AgeCutoff    = $null
            LocationType = "Directory"
            Recurse      = $true
        },
        [PSCustomObject]@{
            Path         = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache"
            Category     = "Edge Cache"
            Group        = "Browser"
            Profile      = "Aggressive"
            Ultra        = $false
            AgeCutoff    = $null
            LocationType = "Directory"
            Recurse      = $true
        },
        [PSCustomObject]@{
            Path         = "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data\Default\Cache"
            Category     = "Brave Cache"
            Group        = "Browser"
            Profile      = "Aggressive"
            Ultra        = $false
            AgeCutoff    = $null
            LocationType = "Directory"
            Recurse      = $true
        },
        [PSCustomObject]@{
            Path         = "$env:LOCALAPPDATA\Vivaldi\User Data\Default\Cache"
            Category     = "Vivaldi Cache"
            Group        = "Browser"
            Profile      = "Aggressive"
            Ultra        = $false
            AgeCutoff    = $null
            LocationType = "Directory"
            Recurse      = $true
        },
        [PSCustomObject]@{
            Path         = "$env:APPDATA\Opera Software\Opera GX Stable\Cache"
            Category     = "Opera GX Cache"
            Group        = "Browser"
            Profile      = "Aggressive"
            Ultra        = $false
            AgeCutoff    = $null
            LocationType = "Directory"
            Recurse      = $true
        }
    )

    # Firefox caches (per-profile cache2 folders)
    $ffProfilesRoot = Join-Path $env:APPDATA "Mozilla\Firefox\Profiles"
    if (Test-Path -LiteralPath $ffProfilesRoot) {
        try {
            $ffProfiles = Get-ChildItem -LiteralPath $ffProfilesRoot -Directory -ErrorAction SilentlyContinue
            foreach ($p in $ffProfiles) {
                $cachePath = Join-Path $p.FullName "cache2"
                if (Test-Path -LiteralPath $cachePath) {
                    $locations += [PSCustomObject]@{
                        Path         = $cachePath
                        Category     = "Firefox Cache ($($p.Name))"
                        Group        = "Browser"
                        Profile      = "Aggressive"
                        Ultra        = $false
                        AgeCutoff    = $null
                        LocationType = "Directory"
                        Recurse      = $true
                    }
                }
            }
        } catch { }
    }

    # --- AGGRESSIVE: Logs / caches ---
    $locations += @(
        # Windows Update cache (Download folder only – safe-ish)
        [PSCustomObject]@{
            Path         = (Join-Path $env:WINDIR "SoftwareDistribution\Download")
            Category     = "Windows Update Cache"
            Group        = "WinUpdate"
            Profile      = "Aggressive"
            Ultra        = $false
            AgeCutoff    = $null
            LocationType = "Directory"
            Recurse      = $true
        },
        # Windows Error Reporting
        [PSCustomObject]@{
            Path         = "$env:LOCALAPPDATA\Microsoft\Windows\WER"
            Category     = "Windows Error Reporting"
            Group        = "Logs"
            Profile      = "Aggressive"
            Ultra        = $false
            AgeCutoff    = $null
            LocationType = "Directory"
            Recurse      = $true
        },
        # Discord cache
        [PSCustomObject]@{
            Path         = "$env:APPDATA\discord\Cache"
            Category     = "Discord Cache"
            Group        = "Logs"
            Profile      = "Aggressive"
            Ultra        = $false
            AgeCutoff    = $null
            LocationType = "Directory"
            Recurse      = $true
        },
        # Steam logs (non-recursive: usually shallow)
        [PSCustomObject]@{
            Path         = "${env:PROGRAMFILES(x86)}\Steam\logs"
            Category     = "Steam Logs"
            Group        = "Logs"
            Profile      = "Aggressive"
            Ultra        = $false
            AgeCutoff    = $null
            LocationType = "Directory"
            Recurse      = $false
        },
        # NVIDIA installer cache
        [PSCustomObject]@{
            Path         = "$env:ProgramData\NVIDIA Corporation\Downloader"
            Category     = "NVIDIA Installer Cache"
            Group        = "Logs"
            Profile      = "Aggressive"
            Ultra        = $false
            AgeCutoff    = $null
            LocationType = "Directory"
            Recurse      = $true
        }
    )

    # --- ULTRA (opt-in) ---
    $locations += @(
        [PSCustomObject]@{
            Path         = (Join-Path $env:WINDIR "MEMORY.DMP")
            Category     = "Memory Dump"
            Group        = "Ultra"
            Profile      = "Ultra"
            Ultra        = $true
            AgeCutoff    = $null
            LocationType = "File"
            Recurse      = $false
        },
        [PSCustomObject]@{
            Path         = (Join-Path $env:WINDIR "Minidump")
            Category     = "Minidumps"
            Group        = "Ultra"
            Profile      = "Ultra"
            Ultra        = $true
            AgeCutoff    = $null
            LocationType = "Directory"
            Recurse      = $true
        },
        [PSCustomObject]@{
            Path         = "C:\Windows.old"
            Category     = "Windows.old"
            Group        = "Ultra"
            Profile      = "Ultra"
            Ultra        = $true
            AgeCutoff    = $null
            LocationType = "Directory"
            Recurse      = $true
        }
    )

    $result = @()

    foreach ($loc in $locations) {

        # --- Skip locations not in active profile ---
        $includeLoc = $false

        switch ($ProfileMode) {
            "Safe" {
                if ($loc.Profile -eq "Safe") { $includeLoc = $true }
            }
            "Aggressive" {
                if ($loc.Profile -eq "Safe" -or $loc.Profile -eq "Aggressive") {
                    $includeLoc = $true
                }
                if ($IncludeUltra -and $loc.Profile -eq "Ultra") {
                    $includeLoc = $true
                }
            }
            default {
                $includeLoc = $true
            }
        }

        if (-not $includeLoc) { continue }

        # --- Actual scanning ---

        if ($loc.LocationType -eq "File") {
            if (-not (Test-Path -LiteralPath $loc.Path -PathType Leaf)) { continue }
            try {
                $file = Get-Item -LiteralPath $loc.Path -ErrorAction Stop
            } catch { continue }

            $result += [PSCustomObject]@{
                Select     = $false
                Name       = $file.Name
                FullPath   = $file.FullName
                SizeBytes  = [int64]$file.Length
                Size       = Format-Size $file.Length
                LastWrite  = $file.LastWriteTime
                Category   = $loc.Category
                Group      = $loc.Group
                Profile    = $loc.Profile
            }
            continue
        }

        if (-not (Test-Path -LiteralPath $loc.Path -PathType Container)) { continue }

        try {
            $files = Get-ChildItem -LiteralPath $loc.Path -File -Recurse:$loc.Recurse -ErrorAction SilentlyContinue
        } catch {
            continue
        }

        if ($loc.AgeCutoff) {
            $files = $files | Where-Object { $_.LastWriteTime -lt $loc.AgeCutoff }
        }

        foreach ($f in $files) {
            $result += [PSCustomObject]@{
                Select     = $false
                Name       = $f.Name
                FullPath   = $f.FullName
                SizeBytes  = [int64]$f.Length
                Size       = Format-Size $f.Length
                LastWrite  = $f.LastWriteTime
                Category   = $loc.Category
                Group      = $loc.Group
                Profile    = $loc.Profile
            }
        }
    }

    return $result
}

#-------------------------
# Build GUI
#-------------------------

$form               = New-Object System.Windows.Forms.Form
$form.Text          = "Disk Cleanup (PowerShell)"
$form.Size          = New-Object System.Drawing.Size(950, 640)
$form.StartPosition = "CenterScreen"
$form.MinimumSize   = New-Object System.Drawing.Size(800, 600)

# ToolTip provider (hover descriptions)
$toolTip = New-Object System.Windows.Forms.ToolTip

# Top labels / controls
$lblInfo = New-Object System.Windows.Forms.Label
$lblInfo.AutoSize = $true
$lblInfo.Location = New-Object System.Drawing.Point(10, 10)
$lblInfo.Text = "Scan temp locations, old Downloads, caches and logs, then select files to delete."

$lblAge = New-Object System.Windows.Forms.Label
$lblAge.AutoSize = $true
$lblAge.Location = New-Object System.Drawing.Point(10, 35)
$lblAge.Text = "Downloads: older than (days):"

$numAge = New-Object System.Windows.Forms.NumericUpDown
$numAge.Location = New-Object System.Drawing.Point(200, 30)
$numAge.Width    = 60
$numAge.Minimum  = 1
$numAge.Maximum  = 365
$numAge.Value    = 30

# Profile selector (Safe / Aggressive)
$rbSafe = New-Object System.Windows.Forms.RadioButton
$rbSafe.AutoSize = $true
$rbSafe.Location = New-Object System.Drawing.Point(300, 32)
$rbSafe.Text = "Safe"
$rbSafe.Checked = $true

$rbAggressive = New-Object System.Windows.Forms.RadioButton
$rbAggressive.AutoSize = $true
$rbAggressive.Location = New-Object System.Drawing.Point(360, 32)
$rbAggressive.Text = "Aggressive"

# Ultra checkbox
$chkUltra = New-Object System.Windows.Forms.CheckBox
$chkUltra.AutoSize = $true
$chkUltra.Location = New-Object System.Drawing.Point(460, 32)
$chkUltra.Text = "Ultra (dangerous)"

# Left filter panel
$panelLeft = New-Object System.Windows.Forms.Panel
$panelLeft.Location = New-Object System.Drawing.Point(10, 60)
$panelLeft.Size     = New-Object System.Drawing.Size(150, 430)
$panelLeft.BorderStyle = 'FixedSingle'
$panelLeft.Anchor   = "Top,Bottom,Left"

$btnFilterAll = New-Object System.Windows.Forms.Button
$btnFilterAll.Text = "All"
$btnFilterAll.Width = 120
$btnFilterAll.Location = New-Object System.Drawing.Point(15, 15)

$btnFilterTempBoth = New-Object System.Windows.Forms.Button
$btnFilterTempBoth.Text = "Temp + Downloads"
$btnFilterTempBoth.Width = 120
$btnFilterTempBoth.Location = New-Object System.Drawing.Point(15, 55)

$btnFilterTempOnly = New-Object System.Windows.Forms.Button
$btnFilterTempOnly.Text = "Temp only"
$btnFilterTempOnly.Width = 120
$btnFilterTempOnly.Location = New-Object System.Drawing.Point(15, 95)

$btnFilterDownloadsOnly = New-Object System.Windows.Forms.Button
$btnFilterDownloadsOnly.Text = "Downloads only"
$btnFilterDownloadsOnly.Width = 120
$btnFilterDownloadsOnly.Location = New-Object System.Drawing.Point(15, 135)

$btnFilterBrowser = New-Object System.Windows.Forms.Button
$btnFilterBrowser.Text = "Browser Cache"
$btnFilterBrowser.Width = 120
$btnFilterBrowser.Location = New-Object System.Drawing.Point(15, 175)

$btnFilterLogs = New-Object System.Windows.Forms.Button
$btnFilterLogs.Text = "Logs / Caches"
$btnFilterLogs.Width = 120
$btnFilterLogs.Location = New-Object System.Drawing.Point(15, 215)

$btnFilterWU = New-Object System.Windows.Forms.Button
$btnFilterWU.Text = "Windows Update"
$btnFilterWU.Width = 120
$btnFilterWU.Location = New-Object System.Drawing.Point(15, 255)

$btnFilterUltra = New-Object System.Windows.Forms.Button
$btnFilterUltra.Text = "Ultra only"
$btnFilterUltra.Width = 120
$btnFilterUltra.Location = New-Object System.Drawing.Point(15, 295)

$panelLeft.Controls.AddRange(@(
    $btnFilterAll,
    $btnFilterTempBoth, $btnFilterTempOnly, $btnFilterDownloadsOnly,
    $btnFilterBrowser, $btnFilterLogs, $btnFilterWU, $btnFilterUltra
))

# DataGridView
$grid = New-Object System.Windows.Forms.DataGridView
$grid.Location              = New-Object System.Drawing.Point(170, 60)
$grid.Size                  = New-Object System.Drawing.Size(750, 360)
$grid.AllowUserToAddRows    = $false
$grid.AllowUserToDeleteRows = $false
$grid.ReadOnly              = $false
$grid.MultiSelect           = $false
$grid.SelectionMode         = "FullRowSelect"
$grid.AutoGenerateColumns   = $false
$grid.RowHeadersVisible     = $false
$grid.Anchor                = "Top,Left,Right"

# Columns
$colSelect                 = New-Object System.Windows.Forms.DataGridViewCheckBoxColumn
$colSelect.Name            = "Select"
$colSelect.HeaderText      = ""
$colSelect.Width           = 40
$colSelect.DataPropertyName = "Select"
$colSelect.SortMode        = 'NotSortable'

$colName                 = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$colName.Name            = "Name"
$colName.HeaderText      = "Name"
$colName.Width           = 180
$colName.DataPropertyName = "Name"
$colName.SortMode        = 'Programmatic'

$colCategory                 = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$colCategory.Name            = "Category"
$colCategory.HeaderText      = "Category"
$colCategory.Width           = 140
$colCategory.DataPropertyName = "Category"
$colCategory.SortMode        = 'Programmatic'

$colProfile                 = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$colProfile.Name            = "Profile"
$colProfile.HeaderText      = "Level"
$colProfile.Width           = 70
$colProfile.DataPropertyName = "Profile"
$colProfile.SortMode        = 'Programmatic'

$colSize                 = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$colSize.Name            = "Size"
$colSize.HeaderText      = "Size"
$colSize.Width           = 80
$colSize.DataPropertyName = "Size"
$colSize.SortMode        = 'Programmatic'

$colLastWrite                 = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$colLastWrite.Name            = "LastWrite"
$colLastWrite.HeaderText      = "Last Modified"
$colLastWrite.Width           = 150
$colLastWrite.DataPropertyName = "LastWrite"
$colLastWrite.SortMode        = 'Programmatic'

$colFullPath                 = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$colFullPath.Name            = "FullPath"
$colFullPath.HeaderText      = "Full Path"
$colFullPath.Width           = 260
$colFullPath.DataPropertyName = "FullPath"
$colFullPath.SortMode        = 'Programmatic'

$grid.Columns.AddRange(
    [System.Windows.Forms.DataGridViewColumn[]]@(
        $colSelect,
        $colName,
        $colCategory,
        $colProfile,
        $colSize,
        $colLastWrite,
        $colFullPath
    )
)

# ---------- Overlay panel (loading) ----------
$overlayPanel = New-Object System.Windows.Forms.Panel
$overlayPanel.Location = $grid.Location
$overlayPanel.Size     = $grid.Size
$overlayPanel.Anchor   = $grid.Anchor
$overlayPanel.BackColor = [System.Drawing.Color]::FromArgb(180, 240, 240, 240)
$overlayPanel.BorderStyle = 'FixedSingle'
$overlayPanel.Visible  = $false

$overlayLabel = New-Object System.Windows.Forms.Label
$overlayLabel.AutoSize = $true
$overlayLabel.Font     = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
$overlayLabel.Text     = "Working, please wait..."
$overlayLabel.Location = New-Object System.Drawing.Point(20, 30)

$overlayProgress = New-Object System.Windows.Forms.ProgressBar
$overlayProgress.Style = 'Marquee'
$overlayProgress.MarqueeAnimationSpeed = 30
$overlayProgress.Width  = 250
$overlayProgress.Height = 20
$overlayProgress.Location = New-Object System.Drawing.Point(20, 65)

# Center roughly within panel when resized
$overlayPanel.Add_Resize({
    $overlayLabel.Left    = [Math]::Max( ( $overlayPanel.Width  - $overlayLabel.Width ) / 2, 10 )
    $overlayLabel.Top     = [Math]::Max( ( $overlayPanel.Height - 60 ) / 2, 10 )
    $overlayProgress.Left = [Math]::Max( ( $overlayPanel.Width  - $overlayProgress.Width ) / 2, 10 )
    $overlayProgress.Top  = $overlayLabel.Bottom + 10
})

$overlayPanel.Controls.AddRange(@($overlayLabel, $overlayProgress))

# Log / output area
$txtLog = New-Object System.Windows.Forms.TextBox
$txtLog.Location  = New-Object System.Drawing.Point(170, 430)
$txtLog.Size      = New-Object System.Drawing.Size(750, 70)
$txtLog.Multiline = $true
$txtLog.ReadOnly  = $true
$txtLog.ScrollBars = 'Vertical'
$txtLog.Font      = New-Object System.Drawing.Font("Consolas", 8)
$txtLog.Anchor    = "Bottom,Left,Right"

# Bottom panel
$panelBottom = New-Object System.Windows.Forms.Panel
$panelBottom.Location = New-Object System.Drawing.Point(10, 510)
$panelBottom.Size     = New-Object System.Drawing.Size(910, 60)
$panelBottom.Anchor   = "Bottom,Left,Right"

$chkSelectAll = New-Object System.Windows.Forms.CheckBox
$chkSelectAll.Text     = "Select All (visible)"
$chkSelectAll.AutoSize = $true
$chkSelectAll.Location = New-Object System.Drawing.Point(10, 20)

$btnDelete = New-Object System.Windows.Forms.Button
$btnDelete.Text     = "Delete Selected"
$btnDelete.Location = New-Object System.Drawing.Point(160, 15)
$btnDelete.Width    = 130

$btnRescan = New-Object System.Windows.Forms.Button
$btnRescan.Text     = "Rescan"
$btnRescan.Location = New-Object System.Drawing.Point(300, 15)
$btnRescan.Width    = 90

$btnClose = New-Object System.Windows.Forms.Button
$btnClose.Text     = "Close"
$btnClose.Location = New-Object System.Drawing.Point(400, 15)
$btnClose.Width    = 80

$lblTotal = New-Object System.Windows.Forms.Label
$lblTotal.AutoSize = $true
$lblTotal.Location = New-Object System.Drawing.Point(500, 20)
$lblTotal.Text = "Selected size: 0 B"

$panelBottom.Controls.AddRange(@(
    $chkSelectAll, $btnDelete, $btnRescan, $btnClose, $lblTotal
))

$form.Controls.AddRange(@(
    $lblInfo, $lblAge, $numAge,
    $rbSafe, $rbAggressive, $chkUltra,
    $panelLeft, $grid, $overlayPanel, $txtLog, $panelBottom
))

#-------------------------
# Tooltips (hover help)
#-------------------------
$toolTip.SetToolTip($rbSafe,       "Safe: Temp folders + old Downloads only. Lowest risk.")
$toolTip.SetToolTip($rbAggressive, "Aggressive: Includes Safe + browser caches + app/system caches.")
$toolTip.SetToolTip($chkUltra,     "Ultra: Includes crash dumps and Windows.old. Can remove rollback/debug data.")

$toolTip.SetToolTip($btnFilterAll,            "Show all items currently included by the selected profile.")
$toolTip.SetToolTip($btnFilterTempBoth,       "Show Temp folders and old Downloads.")
$toolTip.SetToolTip($btnFilterTempOnly,       "Show only Temp folders.")
$toolTip.SetToolTip($btnFilterDownloadsOnly,  "Show only old Downloads.")
$toolTip.SetToolTip($btnFilterBrowser,        "Show only browser cache files.")
$toolTip.SetToolTip($btnFilterLogs,           "Show log and cache files from Windows and apps.")
$toolTip.SetToolTip($btnFilterWU,             "Show Windows Update cache files (SoftwareDistribution\\Download).")
$toolTip.SetToolTip($btnFilterUltra,          "Show only Ultra-level items (crash dumps, Windows.old).")

$toolTip.SetToolTip($numAge, "Only Downloads older than this many days are listed.")

#-------------------------
# Data + filtering + sort state
#-------------------------

$script:allItems  = New-Object System.Collections.Generic.List[object]
$script:viewItems = New-Object "System.ComponentModel.BindingList[System.Object]"

$script:CurrentProfile       = "Safe"      # Safe or Aggressive
$script:CurrentFilter        = "All"       # All / TempBoth / TempOnly / DownloadsOnly / Browser / Logs / WinUpdate / Ultra
$script:CurrentSortColumn    = $null       # Name, Category, Profile, Size, LastWrite, FullPath
$script:CurrentSortDirection = "Asc"       # Asc / Desc

$grid.DataSource = $script:viewItems

function Write-Log {
    param([string]$Message)
    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    $txtLog.AppendText("$timestamp  $Message`r`n")
}

function Show-Overlay {
    param([string]$Message)

    if ($Message) { $overlayLabel.Text = $Message }
    $overlayPanel.Visible = $true
    $overlayPanel.BringToFront()
    $form.UseWaitCursor = $true
    $form.Refresh()   # force paint before heavy work
}

function Hide-Overlay {
    $overlayPanel.Visible = $false
    $form.UseWaitCursor = $false
}

function Update-SelectedSize {
    $totalBytes = 0
    foreach ($item in $script:allItems) {
        if ($item.Select) {
            $totalBytes += [int64]$item.SizeBytes
        }
    }
    $lblTotal.Text = "Selected size: " + (Format-Size $totalBytes)
}

function Clear-Selections {
    foreach ($item in $script:allItems) {
        $item.Select = $false
    }
    $chkSelectAll.Checked = $false
    Update-SelectedSize
}

function Apply-Sort {
    if (-not $script:CurrentSortColumn) { return }

    $prop = switch ($script:CurrentSortColumn) {
        "Name"      { "Name"; break }
        "Category"  { "Category"; break }
        "Profile"   { "Profile"; break }
        "Size"      { "SizeBytes"; break }
        "LastWrite" { "LastWrite"; break }
        "FullPath"  { "FullPath"; break }
        default     { $null }
    }

    if (-not $prop) { return }

    $descending = ($script:CurrentSortDirection -eq "Desc")

    $sorted = if ($descending) {
        $script:viewItems | Sort-Object -Property $prop -Descending
    } else {
        $script:viewItems | Sort-Object -Property $prop
    }

    $newList = New-Object "System.ComponentModel.BindingList[System.Object]"
    foreach ($item in $sorted) {
        $newList.Add($item) | Out-Null
    }

    $script:viewItems = $newList
    $grid.DataSource = $script:viewItems
}

function Apply-Filter {
    $script:viewItems.Clear()

    foreach ($item in $script:allItems) {

        # Profile gating (for view, matches scanning logic)
        $includeProfile = $false
        switch ($item.Profile) {
            "Safe"      { $includeProfile = $true }
            "Aggressive"{
                if ($script:CurrentProfile -eq "Aggressive") { $includeProfile = $true }
            }
            "Ultra"     {
                if ($script:CurrentProfile -eq "Aggressive" -and $chkUltra.Checked) { $includeProfile = $true }
            }
            default     { $includeProfile = $true }
        }
        if (-not $includeProfile) { continue }

        # Filter gating
        $includeFilter = $true
        switch ($script:CurrentFilter) {
            "All"           { $includeFilter = $true }
            "TempBoth"      { $includeFilter = ($item.Group -in @("Temp","Downloads")) }
            "TempOnly"      { $includeFilter = ($item.Group -eq "Temp") }
            "DownloadsOnly" { $includeFilter = ($item.Group -eq "Downloads") }
            "Browser"       { $includeFilter = ($item.Group -eq "Browser") }
            "Logs"          { $includeFilter = ($item.Group -eq "Logs") }
            "WinUpdate"     { $includeFilter = ($item.Group -eq "WinUpdate") }
            "Ultra"         { $includeFilter = ($item.Group -eq "Ultra") }
        }
        if (-not $includeFilter) { continue }

        [void]$script:viewItems.Add($item)
    }

    $grid.DataSource = $null
    $grid.DataSource = $script:viewItems

    Apply-Sort
    Update-SelectedSize
}

function Refresh-Grid {
    Show-Overlay "Scanning files, please wait..."

    try {
        $script:allItems.Clear()
        $script:viewItems.Clear()
        Clear-Selections

        $age          = [int]$numAge.Value
        $profileMode  = $script:CurrentProfile
        $includeUltra = $chkUltra.Checked

        Write-Log "Scanning cleanup locations (Downloads older than $age days, profile=$profileMode, ultra=$includeUltra)..."

        $files = Get-CleanupCandidates -DownloadsMinAgeDays $age -ProfileMode $profileMode -IncludeUltra:$includeUltra

        foreach ($f in $files) {
            [void]$script:allItems.Add($f)
        }

        Write-Log ("Scan complete: {0} candidate file(s) found." -f $script:allItems.Count)

        Apply-Filter
    }
    finally {
        Hide-Overlay
    }
}

#-------------------------
# Event handlers
#-------------------------

# Profile radio buttons
$rbSafe.Add_CheckedChanged({
    if ($rbSafe.Checked) {
        $script:CurrentProfile = "Safe"
        Write-Log "Profile changed to SAFE (Temp + old Downloads only)."
        Clear-Selections
        Apply-Filter
    }
})

$rbAggressive.Add_CheckedChanged({
    if ($rbAggressive.Checked) {
        $script:CurrentProfile = "Aggressive"
        Write-Log "Profile changed to AGGRESSIVE (includes caches and logs)."
        Clear-Selections
        Apply-Filter
    }
})

# Ultra checkbox
$chkUltra.Add_CheckedChanged({
    if ($chkUltra.Checked) {
        [System.Windows.Forms.MessageBox]::Show(
            "Ultra mode includes crash dumps and Windows.old. These can free lots of space but may remove data useful for debugging or rollback.",
            "Ultra mode warning",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        ) | Out-Null
        Write-Log "Ultra mode ENABLED."
    } else {
        Write-Log "Ultra mode disabled."
    }
    Clear-Selections
    Apply-Filter
})

# Sidebar filters
$btnFilterAll.Add_Click({
    $script:CurrentFilter = "All"
    Write-Log "Filter: All items."
    Clear-Selections
    Apply-Filter
})
$btnFilterTempBoth.Add_Click({
    $script:CurrentFilter = "TempBoth"
    Write-Log "Filter: Temp + Downloads."
    Clear-Selections
    Apply-Filter
})
$btnFilterTempOnly.Add_Click({
    $script:CurrentFilter = "TempOnly"
    Write-Log "Filter: Temp only."
    Clear-Selections
    Apply-Filter
})
$btnFilterDownloadsOnly.Add_Click({
    $script:CurrentFilter = "DownloadsOnly"
    Write-Log "Filter: Downloads only."
    Clear-Selections
    Apply-Filter
})
$btnFilterBrowser.Add_Click({
    $script:CurrentFilter = "Browser"
    Write-Log "Filter: Browser cache only."
    Clear-Selections
    Apply-Filter
})
$btnFilterLogs.Add_Click({
    $script:CurrentFilter = "Logs"
    Write-Log "Filter: Logs / caches."
    Clear-Selections
    Apply-Filter
})
$btnFilterWU.Add_Click({
    $script:CurrentFilter = "WinUpdate"
    Write-Log "Filter: Windows Update cache (SoftwareDistribution\\Download)."
    Clear-Selections
    Apply-Filter
})
$btnFilterUltra.Add_Click({
    $script:CurrentFilter = "Ultra"
    Write-Log "Filter: Ultra-only items."
    Clear-Selections
    Apply-Filter
})

# Select All toggle (only visible rows)
$chkSelectAll.Add_CheckedChanged({
    $checked = $chkSelectAll.Checked
    foreach ($item in $script:viewItems) {
        $item.Select = $checked
    }
    $grid.Refresh()
    Update-SelectedSize
})

# Commit checkbox changes
$grid.Add_CurrentCellDirtyStateChanged({
    if ($grid.IsCurrentCellDirty) {
        $grid.CommitEdit([System.Windows.Forms.DataGridViewDataErrorContexts]::Commit)
    }
})

$grid.Add_CellValueChanged({
    param($sender, $e)
    if ($e.ColumnIndex -ge 0 -and $grid.Columns[$e.ColumnIndex].Name -eq "Select") {
        Update-SelectedSize
    }
})

# Column header click for sorting
$grid.Add_ColumnHeaderMouseClick({
    param($sender, $e)

    $col = $grid.Columns[$e.ColumnIndex]
    $colName = $col.Name

    if ($colName -eq "Select") { return }

    if ($script:CurrentSortColumn -eq $colName) {
        if ($script:CurrentSortDirection -eq "Asc") {
            $script:CurrentSortDirection = "Desc"
        } else {
            $script:CurrentSortDirection = "Asc"
        }
    } else {
        $script:CurrentSortColumn    = $colName
        $script:CurrentSortDirection = "Asc"
    }

    Apply-Sort
})

# Rescan button
$btnRescan.Add_Click({
    Write-Log "Manual rescan requested."
    Clear-Selections
    Refresh-Grid
})

# Close button
$btnClose.Add_Click({
    Write-Log "Closing application."
    $form.Close()
})

# Delete button
$btnDelete.Add_Click({
    $selectedItems = @($script:allItems | Where-Object { $_.Select })

    if (-not $selectedItems -or $selectedItems.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show(
            "No files selected to delete.",
            "Info",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        ) | Out-Null
        Write-Log "Delete requested, but no items were selected."
        return
    }

    $count     = $selectedItems.Count
    $sizeBytes = ($selectedItems | Measure-Object -Property SizeBytes -Sum).Sum
    $sizeText  = Format-Size $sizeBytes

    $confirm = [System.Windows.Forms.MessageBox]::Show(
        "Delete $count file(s) totaling $sizeText?" + [Environment]::NewLine +
        "Some files may require admin rights.",
        "Confirm Deletion",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Warning
    )

    if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) {
        Write-Log "Deletion cancelled by user."
        return
    }

    Show-Overlay "Deleting selected files..."

    try {
        Write-Log "Deleting $count file(s) totaling $sizeText..."

        $deleted = 0
        $failed  = 0

        # Iterate backwards through allItems
        for ($i = $script:allItems.Count - 1; $i -ge 0; $i--) {
            $item = $script:allItems[$i]
            if (-not $item.Select) { continue }

            try {
                if (Test-Path -LiteralPath $item.FullPath) {
                    Remove-Item -LiteralPath $item.FullPath -Force -ErrorAction Stop
                }
                $deleted++
                $script:allItems.RemoveAt($i)
            } catch {
                $failed++
                Write-Log ("FAILED: {0} -> {1}" -f $item.FullPath, $_.Exception.Message)
            }
        }

        Apply-Filter  # rebuild viewItems based on new allItems
        Clear-Selections

        Write-Log ("Deletion complete. Deleted: {0}, Failed: {1}, Freed: {2}." -f $deleted, $failed, $sizeText)

        [System.Windows.Forms.MessageBox]::Show(
            "Deleted: $deleted file(s)`nFailed: $failed file(s)",
            "Cleanup Result",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        ) | Out-Null
    }
    finally {
        Hide-Overlay
    }
})

#-------------------------
# Initial load
#-------------------------
[System.Windows.Forms.Application]::EnableVisualStyles()
Write-Log "Disk Cleanup GUI started."

# Run initial scan after the form is shown so the window appears immediately
$form.Add_Shown({
    Refresh-Grid
})

[void]$form.ShowDialog()
