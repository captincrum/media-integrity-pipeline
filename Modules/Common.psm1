# --------------------------------[   Helpers   ]---------------------------- #

function UM-LoadJson {
    param([string]$Path)

    if (Test-Path $Path) {
        $raw = Get-Content $Path -Raw
        if ($raw.Trim().Length -gt 0) {
            try {
                $data = $raw | ConvertFrom-Json
                if ($data -is [System.Collections.IEnumerable]) {
                    return $data
                } else {
                    return @($data)
                }
            }
            catch {
                Write-Host "UM-LoadJson: FAILED to parse JSON at $Path. Returning empty array."
                return @()
            }
        }
    }

    return @()
}

function UM-SaveJson {
    param(
        [string]$Path,
        [object]$Data
    )

    try {
        $dir = Split-Path $Path -Parent
        if ($dir -and -not (Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }

        $count = ($Data | Measure-Object).Count

        $json = $Data | ConvertTo-Json -Depth 6
        $json | Set-Content -Path $Path -Encoding UTF8 -ErrorAction Stop
    }
    catch {
        Write-Host "UM-SaveJson: ERROR writing to $Path"
        Write-Host "UM-SaveJson: $($_.Exception.Message)"
        throw
    }
}

function UM-PrettyMode {
    param([string]$Mode)

    switch ($Mode) {
        "ScanOnly"    { return "Scan Only" }
        "RepairOnly"  { return "Repair Only" }
        "QualityOnly" { return "Quality Only" }
        "Full"        { return "Full" }
        default       { return $Mode }
    }
}

# ----------------------------[ Media Utilities ]---------------------------- #

function UM-VideoExtensions {
    return @(
        "*.mkv", "*.mp4", "*.avi", "*.mov", "*.wmv",
        "*.flv", "*.mpeg", "*.mpg", "*.ts", "*.webm"
    )
}

function UM-LibraryType {
    param(
        [Parameter(Mandatory=$true)]
        [string]$RootPath
    )

    $rootLower = $RootPath.ToLower()

    # Keyword-based detection
    $showKeywords  = @("show","shows","tv","tv show","tv shows","series","season")
    $movieKeywords = @("movie","movies","film","films")

    foreach ($kw in $showKeywords) {
        if ($rootLower -like "*$kw*") {
            return "Shows"
        }
    }

    foreach ($kw in $movieKeywords) {
        if ($rootLower -like "*$kw*") {
            return "Movies"
        }
    }

    # Density-based detection
    $videoExt = UM-VideoExtensions

    $subDirs = Get-ChildItem -Path $RootPath -Directory -ErrorAction SilentlyContinue |
               Select-Object -First 5

    $videoCount = 0
    foreach ($dir in $subDirs) {
        $videoCount += (Get-ChildItem -Path $dir.FullName -File -Include $videoExt -ErrorAction SilentlyContinue).Count
    }

    if ($videoCount -ge 5) {
        return "Shows"
    }

    # Final fallback
    return "Movies"
}

# ------------------------------[   Utilities   ]---------------------------- #

function UM-CleanupPreviousRepairs {
    param(
        [Parameter(Mandatory=$true)][string]$Directory,
        [Parameter(Mandatory=$true)][string]$BaseName,
        [Parameter(Mandatory=$true)][string]$KeepExtension
    )

    # Build pattern: BaseName.*
    $pattern = Join-Path $Directory ($BaseName + ".*")

    # Get all matching files
    $files = Get-ChildItem -Path $pattern -File -ErrorAction SilentlyContinue

	# Delete everything EXCEPT the final successful extension
    foreach ($f in $files) {
        if ($f.Extension -ne $KeepExtension) {
            try {
                Remove-Item $f.FullName -Force
            }
            catch {
                Write-Host "UM-CleanupPreviousRepairs: Failed to delete $($f.FullName)"
            }
        }
    }
}

function UM-GetRepairedOutputPath {
    param(
        [Parameter(Mandatory=$true)][object]$Context,
        [Parameter(Mandatory=$true)][string]$SourcePath
    )
	
    $libraryType = $Context.LibraryType											# Determine library type

    $relative = $null

	if ($SourcePath -match "(?i)(.*\\)(Shows\\.+)") {
        $relative = $matches[2]
    }
	
    elseif ($SourcePath -match "(?i)(.*\\)(Movies\\.+)") {
        $relative = $matches[2]
    }
	
    elseif ($Context.RootPath -and
            $SourcePath.StartsWith($Context.RootPath, [System.StringComparison]::OrdinalIgnoreCase)) {

        $relative = $SourcePath.Substring($Context.RootPath.Length).TrimStart("\","/")
    }
	
    else {
        $relative = [System.IO.Path]::GetFileName($SourcePath)
    }

    $relativeDir = [System.IO.Path]::GetDirectoryName($relative)
    $ext         = [System.IO.Path]::GetExtension($SourcePath)
    $baseName    = [System.IO.Path]::GetFileNameWithoutExtension($SourcePath)

    $targetDirBase = $Context.RepairedRoot

    # Build full directory
    $targetFullDir = if ($relativeDir) {
        Join-Path $targetDirBase $relativeDir
    } else {
        $targetDirBase
    }

    # Ensure directory exists
    if (-not (Test-Path $targetFullDir)) {
        New-Item -ItemType Directory -Path $targetFullDir -Force | Out-Null
    }

    # Return all relevant paths
    return [PSCustomObject]@{
        Directory   = $targetFullDir
        BaseName    = $baseName
        SameExtPath = Join-Path $targetFullDir ($baseName + $ext)
        Mp4Path     = Join-Path $targetFullDir ($baseName + ".mp4")
        Relative    = $relative
        RelativeDir = $relativeDir
    }
}

function Invoke-UMWorkerPool {
    param(
        [object[]]  $Files,
        [int]       $Workers      = 1,
        [string]    $TempDir,
        [string]    $ModuleRoot,
        [string[]]  $Modules,
        [scriptblock]$WorkScript,
        [hashtable] $Extra        = @{},
        [scriptblock]$OnResult,
        [scriptblock]$OnProgress  = $null
    )

    # ---- Setup temp dir ---- #
    if (-not (Test-Path $TempDir)) {
        New-Item -ItemType Directory -Path $TempDir -Force | Out-Null
    }
    1..$Workers | ForEach-Object {
        $f = Join-Path $TempDir "Worker_$_.tmp"
        $s = Join-Path $TempDir "Status_$_.json"
        if (Test-Path $f) { Remove-Item $f -Force }
        if (Test-Path $s) { Remove-Item $s -Force }
    }

    # ---- Build queue ---- #
    $queuePath = Join-Path $TempDir "Queue.json"
    $indexPath = Join-Path $TempDir "QueueIndex.dat"

    $queueItems = $Files | ForEach-Object {
        if ($_ -is [string]) { $_ } else { $_.FullName }
    }
    @($queueItems) | ConvertTo-Json -Depth 2 | Set-Content -Path $queuePath -Encoding UTF8
    [System.IO.File]::WriteAllText($indexPath, "0")

    # ---- Mutex ---- #
    $mutexName = "Global\UMWorkerPool_$(Get-Random)"
    $mutex     = New-Object System.Threading.Mutex($false, $mutexName)

    # ---- Worker scriptblock wrapper ---- #
    # Wraps the caller's WorkScript in queue/mutex/file-write boilerplate
    $workerWrapper = {
        param($workerID, $queuePath, $indexPath, $tmpFile, $statusFile, $mutexName, $moduleRoot, $modules, [string]$workScript, $extra)

        foreach ($m in $modules) {
            Import-Module (Join-Path $moduleRoot $m) -Force
        }

        $workerMutex = New-Object System.Threading.Mutex($false, $mutexName)
        $workScriptBlock = [scriptblock]::Create($workScript)

        while ($true) {

            # ---- Grab next item ---- #
            $workerMutex.WaitOne() | Out-Null

            $queueRaw = Get-Content $queuePath -Raw -ErrorAction SilentlyContinue
            $queue    = @()
            if ($queueRaw -and $queueRaw.Trim() -ne "" -and $queueRaw.Trim() -ne "null") {
                try { $queue = $queueRaw | ConvertFrom-Json } catch { }
            }

            $idx = [int][System.IO.File]::ReadAllText($indexPath).Trim()
            if ($idx -ge $queue.Count) {
                $workerMutex.ReleaseMutex()
                break
            }

            $filePath = $queue[$idx]
            [System.IO.File]::WriteAllText($indexPath, ($idx + 1).ToString())
            $workerMutex.ReleaseMutex()

            # ---- Update status ---- #
            $folderName = Split-Path (Split-Path $filePath -Parent) -Leaf
            @{ WorkerID = $workerID; Folder = $folderName; File = (Split-Path $filePath -Leaf) } |
                ConvertTo-Json -Compress | Set-Content -Path $statusFile -Encoding UTF8

            # ---- Run caller WorkScript ---- #
            $result = & $workScriptBlock $filePath $extra $statusFile $workerID
			if (-not $result) {
                [System.IO.File]::AppendAllText("$tmpFile.debug", "No result returned for $filePath`n")
            } else {
                [System.IO.File]::AppendAllText("$tmpFile.debug", "Got result for $filePath`n")
            }

            # ---- Write result to tmp file ---- #
            if ($result) {
                $json = $result | ConvertTo-Json -Compress -Depth 5
                Add-Content -Path $tmpFile -Value ($json + "`n")
            }
        }

        # ---- Signal done ---- #
        @{ WorkerID = $workerID; Folder = "Done"; File = "" } |
            ConvertTo-Json -Compress | Set-Content -Path $statusFile -Encoding UTF8
    }

    # ---- Spin up one runspace per worker ---- #
    $workerJobs = @()
    for ($w = 1; $w -le $Workers; $w++) {
        $tmpFile    = Join-Path $TempDir "Worker_$w.tmp"
        $statusFile = Join-Path $TempDir "Status_$w.json"

        $rs = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
        $rs.Open()
        $ps = [PowerShell]::Create()
        $ps.Runspace = $rs
        $ps.AddScript($workerWrapper).AddArgument($w).AddArgument($queuePath).AddArgument($indexPath).AddArgument($tmpFile).AddArgument($statusFile).AddArgument($mutexName).AddArgument($ModuleRoot).AddArgument($Modules).AddArgument($WorkScript.ToString()).AddArgument($Extra) | Out-Null

        $workerJobs += [pscustomobject]@{ PS = $ps; RS = $rs; Handle = $ps.BeginInvoke() }
    }

    # ---- Main polling loop ---- #
    $processedPaths = @{}

    while ($true) {

        $anyRunning = $workerJobs | Where-Object { -not $_.Handle.IsCompleted }

        # Read worker statuses for UI
        $folders = @(1..$Workers | ForEach-Object { "" })
        for ($w = 1; $w -le $Workers; $w++) {
            $sf = Join-Path $TempDir "Status_$w.json"
            if (Test-Path $sf) {
                try {
                    $s = Get-Content $sf -Raw | ConvertFrom-Json
                    if ($s.Sample) {
                        $folders[$w - 1] = [ordered]@{
                            Folder       = $s.Folder
                            Episode      = $s.Episode
                            Sample       = $s.Sample
                            TotalSamples = $s.TotalSamples
                            SampleStart  = $s.SampleStart
                        }
                    } else {
						$folders[$w - 1] = if ($s.FileStart) {
                            $currentMB = 0
                            $speedMBs  = 0
                            if ($s.OutputPath -and (Test-Path $s.OutputPath)) {
                                $currentMB = [math]::Round((Get-Item $s.OutputPath).Length / 1MB, 2)
                                $fileSec   = ((Get-Date) - [datetime]::Parse($s.FileStart)).TotalSeconds
                                if ($fileSec -gt 2) { $speedMBs = [math]::Round($currentMB / $fileSec, 1) }
                            }
                            [ordered]@{ Folder = $s.Folder; Episode = $s.Episode; FileStart = $s.FileStart; CurrentMB = $currentMB; EstimatedMB = ($s.EstimatedMB -as [double]); SpeedMBs = $speedMBs }
                        } elseif ($s.File -ne $null) {
                            [ordered]@{ Folder = $s.Folder; File = $s.File }
                        } else {
                            $s.Folder
                        }
                    }
                } catch { }
            }
        }
        $Global:UM_WorkerFolders = $folders

		# Flush tmp files -> call OnResult for each new result
        for ($w = 1; $w -le $Workers; $w++) {
            $tmpFile = Join-Path $TempDir "Worker_$w.tmp"
            if (-not (Test-Path $tmpFile)) { continue }

            $lines = Get-Content $tmpFile -ErrorAction SilentlyContinue
            foreach ($line in $lines) {
                $trim = $line.Trim()
                if ($trim -eq "") { continue }
                try { $result = $trim | ConvertFrom-Json } catch { continue }
                $key = if ($result.Path) { $result.Path } else { $trim }
                if ($processedPaths.ContainsKey($key)) { continue }
                $processedPaths[$key] = $true
                $onResultOutput = & $OnResult $result
                if ($onResultOutput) { Write-Output $onResultOutput }
            }
        }

        if ($OnProgress) { $onProgressOutput = & $OnProgress; if ($onProgressOutput) { Write-Output $onProgressOutput } }

        if (-not $anyRunning) { break }
        Start-Sleep -Milliseconds 500
    }

    # ---- Cleanup ---- #
    foreach ($wj in $workerJobs) {
        try { $wj.PS.EndInvoke($wj.Handle) } catch { }
        $wj.PS.Dispose()
        $wj.RS.Close()
        $wj.RS.Dispose()
    }
    $mutex.Dispose()
    Remove-Item -Path $TempDir -Recurse -Force -ErrorAction SilentlyContinue

    $Global:UM_WorkerFolders = @(1..$Workers | ForEach-Object { "Done" })
}


Export-ModuleMember -Function `
    UM-LoadJson, `
    UM-SaveJson, `
    UM-CleanupPreviousRepairs, `
    UM-GetRepairedOutputPath, `
    UM-PrettyMode, `
    UM-VideoExtensions, `
    UM-LibraryType, `
    Invoke-UMWorkerPool