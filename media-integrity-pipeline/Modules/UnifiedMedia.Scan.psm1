function UM-IsScanned {
    param(
        [string]$Path,
        [array]$ScanLog
    )
    return $ScanLog | Where-Object { $_.Path -eq $Path }
}

function Invoke-UMScanFile {
    param([string]$FilePath)

    $probe = & ffprobe -v error -select_streams v -show_entries stream=codec_type -of csv=p=0 $FilePath
    if ($probe -ne "video") {
        return @("No video stream detected")
    }

    $raw = & ffmpeg -v error -i $FilePath -hide_banner 2>&1 | Out-String
    $lines = $raw -split "`n"

    $patterns = @(
        "sps_id .* out of range",
        "Invalid NAL unit size .*",
        "missing picture in access unit .*"
    )

    $errors = @()
    foreach ($line in $lines) {
        if ($line -match "missing picture in access unit with size (\d+)" -and [int]$matches[1] -lt 100) {
            continue
        }
        foreach ($p in $patterns) {
            if ($line -match $p) {
                $errors += $line.Trim()
            }
        }
    }

    return $errors
}

# =====================================================================
# UPDATED: Get-UMFilesToScan — GUI-SAFE VERSION
# =====================================================================
function Get-UMFilesToScan {
    param(
        [string]$RootPath,
        [string]$LibraryType,
        [ref]$ScanAllEpisodesRef
    )

    $videoExtensions = @("*.mkv","*.mp4","*.avi","*.mov","*.wmv","*.flv","*.mpeg","*.ts","*.webm")

    # MOVIES always scan all files
    if ($LibraryType -eq "Movies") {
        $ScanAllEpisodesRef.Value = $true
        return Get-ChildItem -Path $RootPath -Recurse -File -Include $videoExtensions
    }

    # SHOWS — NEW LOGIC:
    if ($Global:Context -and
        $Global:Context.PSObject.Properties.Name -contains 'ScanAllEpisodes') {

        $ScanAllEpisodesRef.Value = [bool]$Global:Context.ScanAllEpisodes
    }
    else {
        $ScanAllEpisodesRef.Value = $false
    }

    if ($ScanAllEpisodesRef.Value) {
        return Get-ChildItem -Path $RootPath -Recurse -File -Include $videoExtensions
    }

    # Otherwise: scan only first episode of each season
    $allFiles = @()
    $showDirs = Get-ChildItem -Path $RootPath -Directory

    if ($showDirs.Count -eq 0) {
        $showDirs = @(Get-Item $RootPath)
    }

    foreach ($showDir in $showDirs) {

        $episodeFiles = Get-ChildItem -Path $showDir.FullName -Recurse -File -Include $videoExtensions
        $seasonGroups = @{ }

        foreach ($file in $episodeFiles) {
            if ($file.Name -match "S(\d{2,4})E(\d{2})") {
                $seasonNumber = [int]$matches[1]
                if (-not $seasonGroups.ContainsKey($seasonNumber)) {
                    $seasonGroups[$seasonNumber] = @()
                }
                $seasonGroups[$seasonNumber] += $file
            }
        }

        foreach ($seasonNumber in ($seasonGroups.Keys | Sort-Object)) {
            $seasonFiles = $seasonGroups[$seasonNumber] | Sort-Object Name
            if ($seasonFiles.Count -gt 0) {
                $allFiles += $seasonFiles[0]
            }
        }
    }

    return $allFiles
}

function Invoke-UMShowEscalation {
    param(
        [object]$Context,
        [System.IO.FileInfo]$File,
        [ref]$ScanLog
    )

    #
    # Only applies to Shows AND only when ScanAllEpisodes = $false
    #
    if ($Context.LibraryType -ne "Shows" -or $Context.ScanAllEpisodes) {
        return
    }

    # Video extensions
    $videoExtensions = @(
        "*.mkv","*.mp4","*.avi","*.mov","*.wmv",
        "*.flv","*.mpeg","*.ts","*.webm"
    )

    # Show directory
    $showDir = Split-Path $File.FullName -Parent

    # All episodes in this show folder
    $allEpisodes = Get-ChildItem -Path $showDir -Recurse -File -Include $videoExtensions |
                   Sort-Object Name

    #
    # ⭐ FIX: Update total files for GUI progress
    # Count already scanned + remaining unscanned episodes
    #
    $remaining = $allEpisodes | Where-Object {
        -not (UM-IsScanned -Path $_.FullName -ScanLog $ScanLog.Value)
    }

    $Global:UM_TotalFiles = $ScanLog.Value.Count + $remaining.Count

    #
    # Scan each unscanned episode
    #
    foreach ($ep in $allEpisodes) {

        if (UM-IsScanned -Path $ep.FullName -ScanLog $ScanLog.Value) {
            continue
        }

        # Perform scan
        $epErrors = Invoke-UMScanFile -FilePath $ep.FullName

        # Build entry
        $entry = [PSCustomObject]@{
            Path      = $ep.FullName
            Library   = $Context.LibraryType
            Errors    = $epErrors
            ScannedAt = (Get-Date).ToString("s")
        }

        # Add to scan log
        $ScanLog.Value += $entry

        # Log scan
        UM-LogScan `
            -Path      $entry.Path `
            -Library   $entry.Library `
            -Errors    $entry.Errors `
            -ScannedAt $entry.ScannedAt

        # Add to repair queue if needed
        if ($epErrors.Count -gt 0) {
            UM-LogToRepair `
                -Path         $entry.Path `
                -Library      $entry.Library `
                -Errors       $entry.Errors `
                -RepairStatus "Pending" `
                -AddedAt      (Get-Date).ToString("s")
        }

        #
        # Emit ScanProgress for GUI (critical for Phase 2 updates)
        #
		Write-Output ([pscustomobject]@{
			Type    = "ScanProgress"
			File    = $file.FullName      # or $file.FullName / $null
			Elapsed = (UM-GetElapsed).ToString("hh\:mm\:ss")
			Scanned = $ScanLog.Value.Count  # or $scannedFiles / $ScanLog.Count
			Total   = $Global:UM_TotalFiles
		})
    }
}

# =====================================================================
# MAIN SCAN FUNCTION — OPTION B (TRUE 1-SECOND LIVE UPDATES)
# =====================================================================
function Invoke-UMScan {

    $Context = $Global:Context

    if (-not $Context.RootPath) {
        UM-Output "Scan requires a valid root path. Exiting."
        return
    }

    # Reset timers
    UM-ResetTimers
    UM-StartTimer

    # Initialize global progress state
    $Global:UM_CurrentScanFile     = ""
    $Global:UM_CurrentScanElapsed  = [timespan]::Zero
    $Global:UM_CurrentFileElapsed  = [timespan]::Zero
    $Global:UM_ScannedFiles        = 0
    $Global:UM_TotalFiles          = 0

    # Phase 1 output (static)
    UM-OutputPhaseOne -Context $Context

    # Read unified log
	$unifiedLog = UM-ReadUnifiedLog
	$scanLog = @()

	if ($unifiedLog) {
		$scanLog = $unifiedLog |
			Where-Object {
				$_.Type -eq "Scan" -and
				$_.Path -like "$($Context.RootPath)*"
			}
	}

    # Detect if this library was already scanned
    $existing = $scanLog | Where-Object { $_.Path -like "$($Context.RootPath)*" }

    # NEW: store the flag
    $Global:UM_AlreadyScanned = ($existing.Count -gt 0)

    # Determine files to scan
    $scanAllRef = [ref]$false
    $allFiles = Get-UMFilesToScan -RootPath $Context.RootPath -LibraryType $Context.LibraryType -ScanAllEpisodesRef $scanAllRef

    $Context | Add-Member -NotePropertyName ScanAllEpisodes -NotePropertyValue $scanAllRef.Value -Force

    $totalFiles = $allFiles.Count
    $Global:UM_TotalFiles = $totalFiles

    $previouslyScanned = $scanLog.Count
	$scannedFiles = $previouslyScanned

    foreach ($file in $allFiles) {

        # Skip files already scanned
        if (UM-IsScanned -Path $file.FullName -ScanLog $scanLog) {
            continue
        }

        # Start per-file timer
        UM-StartFileTimer

        # update counters
        $scannedFiles++

        # emit ONE progress object
		Write-Output ([pscustomobject]@{
			Type    = "ScanProgress"
			File    = $file.FullName      # or $file.FullName / $null
			Elapsed = (UM-GetElapsed).ToString("hh\:mm\:ss")
			Scanned = $ScanLog.Value.Count  # or $scannedFiles / $ScanLog.Count
			Total   = $Global:UM_TotalFiles
		})


        # Perform scan
        $errors = Invoke-UMScanFile -FilePath $file.FullName

        $scanEntry = [PSCustomObject]@{
            Path      = $file.FullName
            Library   = $Context.LibraryType
            Errors    = $errors
            ScannedAt = (Get-Date).ToString("s")
        }

        $scanLog += $scanEntry

        UM-LogScan -Path $scanEntry.Path -Library $scanEntry.Library -Errors $scanEntry.Errors -ScannedAt $scanEntry.ScannedAt

        if ($errors.Count -gt 0) {

            UM-LogToRepair `
                -Path $scanEntry.Path `
                -Library $scanEntry.Library `
                -Errors $scanEntry.Errors `
                -RepairStatus "Pending" `
                -AddedAt (Get-Date).ToString("s")

            if ($Context.LibraryType -eq "Shows" -and -not $Context.ScanAllEpisodes) {
                Invoke-UMShowEscalation -Context $Context -File $file -ScanLog ([ref]$scanLog)
            }
        }
    }

    # Emit final progress update
	Write-Output ([pscustomobject]@{
		Type    = "ScanProgress"
		File    = $file.FullName      # or $file.FullName / $null
		Elapsed = (UM-GetElapsed).ToString("hh\:mm\:ss")
		Scanned = $ScanLog.Value.Count  # or $scannedFiles / $ScanLog.Count
		Total   = $Global:UM_TotalFiles
	})
	
    Start-Sleep -Milliseconds 200

    # Final output
    UM-OutputScanComplete
	return $null
}
