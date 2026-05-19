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

    # -------------------------[ Temp dir setup ]--------------------------- #

    $tempDir = Join-Path $Context.RepairedRoot "ScanTemp"
    if (-not (Test-Path $tempDir)) {
        New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
    }

    # Clean up any leftover temp files from a previous run
    1..4 | ForEach-Object {
        $f = Join-Path $tempDir "Worker_$_.tmp"
        if (Test-Path $f) { Remove-Item $f -Force }
        $s = Join-Path $tempDir "Status_$_.json"
        if (Test-Path $s) { Remove-Item $s -Force }
    }

    # -------------------------[ Queue file ]------------------------------- #

    $queuePath = Join-Path $tempDir "ScanQueue.json"
    $queueItems = $filesToScan | ForEach-Object {
        [ordered]@{ Path = $_.FullName; Library = $Context.LibraryType }
    }
    $queueItems | ConvertTo-Json -Depth 3 | Set-Content -Path $queuePath -Encoding UTF8

    # -------------------------[ Mutex for queue ]-------------------------- #

    $mutexName = "Global\UMScanQueue"
    $mutex = New-Object System.Threading.Mutex($false, $mutexName)

    # -------------------------[ Spin up 4 worker jobs ]------------------- #

    $numWorkers = 4
    $workerJobs = @()

    for ($w = 1; $w -le $numWorkers; $w++) {

        $workerJobs += Start-Job -ScriptBlock {
            param($workerID, $queuePath, $tempDir, $moduleRoot, $mutexName)

            # Load modules
            $modules = @(
                "UnifiedMedia.Common.psm1",
                "UnifiedMedia.Logging.psm1",
                "UnifiedMedia.Scan.psm1"
            )
            foreach ($m in $modules) {
                Import-Module (Join-Path $moduleRoot $m) -Force
            }

            $statusFile = Join-Path $tempDir "Status_$workerID.json"
            $tmpFile    = Join-Path $tempDir "Worker_$workerID.tmp"

            $workerMutex = [System.Threading.Mutex]::OpenExisting($mutexName)

            while ($true) {

                # ---- Grab next item from queue (mutex protected) ---- #
                $workerMutex.WaitOne() | Out-Null

                $queueRaw = Get-Content $queuePath -Raw -ErrorAction SilentlyContinue
                $queue    = @()
                if ($queueRaw -and $queueRaw.Trim() -ne "" -and $queueRaw.Trim() -ne "null") {
                    try { $queue = $queueRaw | ConvertFrom-Json } catch { }
                }

				if (-not $queue -or $queue.Count -eq 0) {
                    $workerMutex.ReleaseMutex()
                    $retries = 0
                    $foundWork = $false
                    while ($retries -lt 6) {
                        Start-Sleep -Milliseconds 500
                        $retries++
                        $workerMutex.WaitOne() | Out-Null
                        $recheckRaw = Get-Content $queuePath -Raw -ErrorAction SilentlyContinue
                        $recheckQueue = @()
                        if ($recheckRaw -and $recheckRaw.Trim() -ne "" -and $recheckRaw.Trim() -ne "null") {
                            try { $recheckQueue = $recheckRaw | ConvertFrom-Json } catch { }
                        }
                        if ($recheckQueue -and $recheckQueue.Count -gt 0) {
                            $workerMutex.ReleaseMutex()
                            $foundWork = $true
                            break  # new work appeared, go back to main loop
                        }
                        $workerMutex.ReleaseMutex()
                    }
                    if (-not $foundWork) { break }  # truly empty after retries
                    continue  # loop back to grab the new work
                }

                # Take first item
                $item      = $queue[0]
                $remaining = $queue | Select-Object -Skip 1
                
                # Write remaining queue back
                if ($remaining) {
                    $remaining | ConvertTo-Json -Depth 3 | Set-Content -Path $queuePath -Encoding UTF8
                } else {
                    "" | Set-Content -Path $queuePath -Encoding UTF8
                }

                $workerMutex.ReleaseMutex()

                # ---- Update status file ---- #
                $folderName = Split-Path (Split-Path $item.Path -Parent) -Leaf
                @{ WorkerID = $workerID; Folder = $folderName } |
                    ConvertTo-Json -Compress |
                    Set-Content -Path $statusFile -Encoding UTF8

                # ---- Scan the file ---- #
                $errors = Invoke-UMScanFile -FilePath $item.Path

                $result = [ordered]@{
                    Path        = $item.Path
                    Library     = $item.Library
                    Errors      = $errors
                    ScannedAt   = (Get-Date).ToString("s")
                    NeedsRepair = ($errors.Count -gt 0)
                }

                $json = $result | ConvertTo-Json -Compress -Depth 5
                Add-Content -Path $tmpFile -Value ($json + "`n")
            }

            # Signal done
            @{ WorkerID = $workerID; Folder = "Done" } |
                ConvertTo-Json -Compress |
                Set-Content -Path $statusFile -Encoding UTF8

        } -ArgumentList $w, $queuePath, $tempDir, $moduleRoot, $mutexName
    }

	# -------------------------[ Main thread: poll + write ]---------------- #

    $processedPaths  = @{}
    $escalatedShows  = @{}   # track which show dirs we've already escalated

    while ($true) {

        $anyRunning = $workerJobs | Where-Object { $_.State -eq "Running" }

        # ---- Read worker status files ---- #
        $folders = @("", "", "", "")
        for ($w = 1; $w -le $numWorkers; $w++) {
            $statusFile = Join-Path $tempDir "Status_$w.json"
            if (Test-Path $statusFile) {
                try {
                    $s = Get-Content $statusFile -Raw | ConvertFrom-Json
                    $folders[$w - 1] = $s.Folder
                } catch { }
            }
        }
        $Global:UM_WorkerFolders = $folders

        # ---- Flush completed results from tmp files ---- #
        for ($w = 1; $w -le $numWorkers; $w++) {
            $tmpFile = Join-Path $tempDir "Worker_$w.tmp"
            if (-not (Test-Path $tmpFile)) { continue }

            $lines = Get-Content $tmpFile -ErrorAction SilentlyContinue
            foreach ($line in $lines) {
                $trim = $line.Trim()
                if ($trim -eq "") { continue }

                try { $result = $trim | ConvertFrom-Json } catch { continue }

                if ($processedPaths.ContainsKey($result.Path)) { continue }
                $processedPaths[$result.Path] = $true

                $scanLog += [PSCustomObject]@{
                    Path      = $result.Path
                    Library   = $result.Library
                    Errors    = $result.Errors
                    ScannedAt = $result.ScannedAt
                }

                $scannedFiles++

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

                    # ---- Escalation: feed new episodes back into the queue ---- #
                    if ($Context.LibraryType -eq "Shows" -and -not $Context.ScanAllEpisodes) {

                        $showDir = Split-Path (Split-Path $result.Path -Parent) -Leaf
                        $showDirFull = Split-Path $result.Path -Parent

                        if (-not $escalatedShows.ContainsKey($showDirFull)) {
                            $escalatedShows[$showDirFull] = $true

                            $videoExtensions = UM-VideoExtensions
                            $allEpisodes = Get-ChildItem -Path $showDirFull -Recurse -File -Include $videoExtensions |
                                           Sort-Object Name

                            $newEpisodes = $allEpisodes | Where-Object {
                                -not $processedPaths.ContainsKey($_.FullName) -and
                                -not (UM-IsScanned -Path $_.FullName -ScanLog $scanLog)
                            }

                            if ($newEpisodes.Count -gt 0) {

                                # Grow the total
                                $totalFiles += $newEpisodes.Count
                                $Global:UM_TotalFiles = $totalFiles

                                # Append new episodes to the queue (mutex protected)
                                $mutex.WaitOne() | Out-Null

                                $queueRaw = Get-Content $queuePath -Raw -ErrorAction SilentlyContinue
                                $currentQueue = @()
                                if ($queueRaw -and $queueRaw.Trim() -ne "" -and $queueRaw.Trim() -ne "null") {
                                    try { $currentQueue = $queueRaw | ConvertFrom-Json } catch { }
                                }

                                $newItems = $newEpisodes | ForEach-Object {
                                    [ordered]@{ Path = $_.FullName; Library = $Context.LibraryType }
                                }

                                $mergedQueue = @($currentQueue) + @($newItems)
                                $mergedQueue | ConvertTo-Json -Depth 3 | Set-Content -Path $queuePath -Encoding UTF8

                                $mutex.ReleaseMutex()
                            }
                        }
                    }
                }
            }
        }

        # ---- Emit progress ---- #
        $Global:UM_ScannedCount = $scannedFiles
        $Global:UM_ScanTotal    = $totalFiles
        $Global:UM_Mode         = $Context.Mode

        UM-PhaseTwoConsole

        if (-not $anyRunning) { break }

        Start-Sleep -Milliseconds 500
    }

    # ---- Cleanup worker jobs ---- #
    foreach ($job in $workerJobs) {
        Receive-Job $job -ErrorAction SilentlyContinue | Out-Null
        Remove-Job  $job -ErrorAction SilentlyContinue
    }

    $mutex.Dispose()

    # ---- Clean up temp dir ---- #
    Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue

    # ---- Final progress emit ---- #
    $Global:UM_ScannedCount  = $totalFiles
    $Global:UM_ScanTotal     = $totalFiles
    $Global:UM_Mode          = $Context.Mode
    $Global:UM_WorkerFolders = @("Done", "Done", "Done", "Done")

    UM-PhaseTwoConsole
    Start-Sleep -Milliseconds 500

    return $null
}