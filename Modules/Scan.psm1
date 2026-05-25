$Global:UM_ScanStart = Get-Date

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

function Get-UMFilesToScan {
    param(
        [string]$RootPath,
        [string]$LibraryType,
        [ref]$ScanAllEpisodesRef
    )

    $videoExtensions = UM-VideoExtensions

    if ($LibraryType -eq "Movies") {
        $ScanAllEpisodesRef.Value = $true
        return Get-ChildItem -Path $RootPath -Recurse -File -Include $videoExtensions
    }

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

# =====================================================================
# WORKER: Scans a single file, writes result to a temp file
# =====================================================================
function Invoke-UMScanWorker {
    param(
        [int]   $WorkerID,
        [string]$FilePath,
        [string]$Library,
        [string]$TempDir,
        [string]$StatusFile   # worker writes its current folder here
    )

    # Update status file so the main job can report which folder this worker is on
    $folderName = Split-Path (Split-Path $FilePath -Parent) -Leaf
    $statusEntry = @{ WorkerID = $WorkerID; Folder = $folderName } | ConvertTo-Json -Compress
    [System.IO.File]::WriteAllText($StatusFile, $statusEntry)

    $errors = Invoke-UMScanFile -FilePath $FilePath

    $result = [ordered]@{
        Path      = $FilePath
        Library   = $Library
        Errors    = $errors
        ScannedAt = (Get-Date).ToString("s")
        NeedsRepair = ($errors.Count -gt 0)
    }

    # Append result to this worker's temp file (one JSON line per result)
    $json = $result | ConvertTo-Json -Compress -Depth 5
    $tmpFile = Join-Path $TempDir "Worker_$WorkerID.tmp"
    Add-Content -Path $tmpFile -Value ($json + "`n")
}

# =====================================================================
# SHOW ESCALATION (single-threaded, called after parallel scan)
# =====================================================================
function Invoke-UMShowEscalation {
    param(
        [object]$Context,
        [System.IO.FileInfo]$File,
        [ref]$ScanLog,
        [ref]$RunningTotal
    )

    if ($Context.LibraryType -ne "Shows" -or $Context.ScanAllEpisodes) {
        return
    }

    $videoExtensions = UM-VideoExtensions
    $showDir = Split-Path $File.FullName -Parent

    $allEpisodes = Get-ChildItem -Path $showDir -Recurse -File -Include $videoExtensions |
                   Sort-Object Name

    $newEpisodes = $allEpisodes | Where-Object {
        -not (UM-IsScanned -Path $_.FullName -ScanLog $ScanLog.Value)
    }

    $RunningTotal.Value += $newEpisodes.Count
    $Global:UM_TotalFiles = $RunningTotal.Value

    foreach ($ep in $allEpisodes) {

        if (UM-IsScanned -Path $ep.FullName -ScanLog $ScanLog.Value) {
            continue
        }

        $epErrors = Invoke-UMScanFile -FilePath $ep.FullName

        $entry = [PSCustomObject]@{
            Path      = $ep.FullName
            Library   = $Context.LibraryType
            Errors    = $epErrors
            ScannedAt = (Get-Date).ToString("s")
        }

        $ScanLog.Value += $entry

        UM-LogScan `
            -Path      $entry.Path `
            -Library   $entry.Library `
            -Errors    $entry.Errors

        if ($epErrors.Count -gt 0) {
            UM-LogToRepair `
                -Path         $entry.Path `
                -Library      $entry.Library `
                -Errors       $entry.Errors `
                -RepairStatus "Pending" `
                -AddedAt      (Get-Date).ToString("s")
        }

        $Global:UM_ScanFile     = $ep.FullName
        $Global:UM_ScannedCount = $ScanLog.Value.Count
        $Global:UM_ScanTotal    = $RunningTotal.Value
        $Global:UM_Mode         = $Context.Mode

        UM-PhaseTwoConsole
    }
}

# =====================================================================
# MAIN SCAN FUNCTION
# =====================================================================
function Invoke-UMScan {

    $Context = $Global:Context

    if (-not $Context.RootPath) {
        UM-Output "Scan requires a valid root path. Exiting."
        return
    }

    UM-ResetTimers
    UM-StartTimer

    $Global:UM_CurrentScanFile    = ""
    $Global:UM_CurrentScanElapsed = [timespan]::Zero
    $Global:UM_CurrentFileElapsed = [timespan]::Zero
    $Global:UM_ScannedFiles       = 0
    $Global:UM_TotalFiles         = 0

    # Initialize worker status globals
    $Global:UM_WorkerFolders = @("", "", "", "")

    UM-PhaseOneConsole -Context $Context

    $unifiedLog = UM-ReadUnifiedLog
    $scanLog    = @()

    if ($unifiedLog) {
        $scanLog = $unifiedLog |
            Where-Object {
                $_.Type -eq "Scan" -and
                $_.Path -like "$($Context.RootPath)*"
            }
    }

    $existing = $scanLog | Where-Object { $_.Path -like "$($Context.RootPath)*" }
    $Global:UM_AlreadyScanned = ($existing.Count -gt 0)

    $scanAllRef = [ref]$false
    $allFiles   = Get-UMFilesToScan `
                    -RootPath           $Context.RootPath `
                    -LibraryType        $Context.LibraryType `
                    -ScanAllEpisodesRef $scanAllRef

    $Context | Add-Member -NotePropertyName ScanAllEpisodes -NotePropertyValue $scanAllRef.Value -Force

    # Filter out already-scanned files
    $filesToScan = $allFiles | Where-Object {
        -not (UM-IsScanned -Path $_.FullName -ScanLog $scanLog)
    }

    $totalFiles     = $allFiles.Count
    $Global:UM_TotalFiles = $totalFiles

    $scannedFiles   = $scanLog.Count   # previously scanned count


    # -------------------------[ Worker pool scan ]------------------------ #

    $Global:UM_ScanLog        = $scanLog
    $Global:UM_ScanCount      = $scannedFiles
    $Global:UM_ScanTotal2     = $totalFiles
    $Global:UM_EscalatedShows = @{}
    $Global:UM_ScanTempDir    = Join-Path (Split-Path $Global:UnifiedMachineLogPath -Parent) "ScanTemp"

    $scanWorkScript = {
        param($filePath, $extra, $statusFile, $workerID)
        $errors = Invoke-UMScanFile -FilePath $filePath
        return [PSCustomObject]@{
            Path        = $filePath
            Library     = $extra.Library
            Errors      = $errors
            ScannedAt   = (Get-Date).ToString("s")
            NeedsRepair = ($errors.Count -gt 0)
        }
    }

    $onResult = {
        param($result)

        $Global:UM_ScanLog   += $result
        $Global:UM_ScanCount++

        UM-LogScan `
            -Path    $result.Path `
            -Library $result.Library `
            -Errors  $result.Errors

        if ($result.NeedsRepair) {
            UM-LogToRepair `
                -Path         $result.Path `
                -Library      $result.Library `
                -Errors       $result.Errors `
                -RepairStatus "Pending" `
                -AddedAt      (Get-Date).ToString("s")

            if ($Global:Context.LibraryType -eq "Shows" -and -not $Global:Context.ScanAllEpisodes) {

                $showDirFull = Split-Path $result.Path -Parent

                if (-not $Global:UM_EscalatedShows.ContainsKey($showDirFull)) {
                    $Global:UM_EscalatedShows[$showDirFull] = $true

                    $videoExtensions = UM-VideoExtensions
                    $allEpisodes     = Get-ChildItem -Path $showDirFull -Recurse -File -Include $videoExtensions |
                                       Sort-Object Name

                    $newEpisodes = $allEpisodes | Where-Object {
                        -not (UM-IsScanned -Path $_.FullName -ScanLog $Global:UM_ScanLog)
                    }

                    if ($newEpisodes.Count -gt 0) {
                        $Global:UM_ScanTotal2  += $newEpisodes.Count
                        $Global:UM_TotalFiles   = $Global:UM_ScanTotal2

                        $queuePath = Join-Path $Global:UM_ScanTempDir "Queue.json"
                        $queueRaw = Get-Content $queuePath -Raw -ErrorAction SilentlyContinue
                        $currentQueue = @()
                        if ($queueRaw -and $queueRaw.Trim() -ne "" -and $queueRaw.Trim() -ne "null") {
                            try { $currentQueue = $queueRaw | ConvertFrom-Json } catch { }
                        }
                        $merged = @($currentQueue) + @($newEpisodes | ForEach-Object { $_.FullName })
                        $merged | ConvertTo-Json -Depth 2 | Set-Content $queuePath -Encoding UTF8
                    }
                }
            }
        }

        $Global:UM_ScannedCount = $Global:UM_ScanCount
        $Global:UM_ScanTotal    = $Global:UM_ScanTotal2
        $Global:UM_Mode         = $Global:Context.Mode
    }

    $onProgress = {
        UM-PhaseTwoConsole
    }

    Invoke-UMWorkerPool `
        -Files      $filesToScan `
        -Workers    $Context.Workers `
        -TempDir    $Global:UM_ScanTempDir `
        -ModuleRoot $moduleRoot `
        -Modules    @("Common.psm1", "Logging.psm1", "Scan.psm1") `
        -WorkScript $scanWorkScript `
        -Extra      @{ Library = $Context.LibraryType } `
        -OnResult   $onResult `
        -OnProgress $onProgress

    # ---- Final progress emit ---- #
    $Global:UM_ScannedCount  = $Global:UM_ScanTotal2
    $Global:UM_ScanTotal     = $Global:UM_ScanTotal2
    $Global:UM_Mode          = $Context.Mode

    UM-PhaseTwoConsole
    Start-Sleep -Milliseconds 500

    return $null
}