# =====================================================================
# SmartCompression.psm1
# Sample-encode probe: 1 sample (fast) or 3 samples (accurate).
# Hard filters: skip hevc/av1/vp9, duration < 3min, bitrate < 500kbps.
# Skip rule: if any sample encode exceeds source bitrate -> skip.
# =====================================================================

function Invoke-UMSmartProbe {
    param(
        [bool]$AccurateMode = $false
    )

    $Context = $Global:Context

    if (-not $Context.RootPath) {
        UM-Output "Smart Compression requires a valid root path. Exiting."
        return
    }

    $Global:UM_ScanStart     = Get-Date
    $Global:UM_ScannedCount  = 0
    $Global:UM_TotalFiles    = 0
    $Global:UM_ScanTotal     = 0
    $Global:UM_WorkerFolders = @("")

    UM-PhaseOneConsole -Context $Context

    $unifiedLog  = UM-ReadUnifiedLog
    $probedPaths = @{}
    if ($unifiedLog) {
        $unifiedLog |
            Where-Object { $_.Type -eq "SmartProbe" -and $_.Path -like "$($Context.RootPath)*" } |
            ForEach-Object {
                $probedPaths[$_.Path] = @{
                    ProbeMethod = $_.ProbeMethod
                    Verdict     = $_.Verdict
                    SampleKbps  = $_.SampleKbps
                    SkipReason  = $_.SkipReason
                }
            }
    }

    $scanAllRef = [ref]$false
    $allFiles = Get-UMFilesToScan `
                    -RootPath           $Context.RootPath `
                    -LibraryType        $Context.LibraryType `
                    -ScanAllEpisodesRef $scanAllRef

    $allFiles = $allFiles | Sort-Object FullName

    $filesToProbe = $allFiles | Where-Object {
        $entry = $probedPaths[$_.FullName]
        if (-not $entry) { return $true }
        if ($entry.Verdict -eq "Skip" -and $entry.SkipReason -ne "SavingsBelowThreshold") { return $false }
        if ($AccurateMode -and $entry.ProbeMethod -eq "Fast") { return $true }
        return $false
    }

    $totalFiles = $allFiles.Count
    $Global:UM_TotalFiles  = $totalFiles
    $Global:UM_ScanTotal   = $totalFiles
    $scannedFiles = $probedPaths.Count

    $crfValue     = if ($Context.CrfValue -gt 0) { $Context.CrfValue } else { 22 }
    $probeTempDir = Join-Path $env:TEMP "UMSmartTemp_$(Get-Random)"

    $probeExtra = @{
        AccurateMode = $AccurateMode
        CrfValue     = $crfValue
        ProbedPaths  = $probedPaths
    }

    $probeWorkScript = {
        param($filePath, $extra, $statusFile, $workerID)
        $folderName   = Split-Path (Split-Path $filePath -Parent) -Leaf
        $episodeName  = [System.IO.Path]::GetFileNameWithoutExtension($filePath)
        $existingKbps = if ($extra.ProbedPaths[$filePath] -and $extra.ProbedPaths[$filePath].SampleKbps) {
            @($extra.ProbedPaths[$filePath].SampleKbps)
        } else { @() }
        return Invoke-UMProbeFile `
            -FilePath           $filePath `
            -AccurateMode       $extra.AccurateMode `
            -CrfValue           $extra.CrfValue `
            -StatusFile         $statusFile `
            -WorkerID           $workerID `
            -FolderName         $folderName `
            -EpisodeName        $episodeName `
            -ExistingSampleKbps $existingKbps
    }

    $Global:UM_ProbeCount      = $scannedFiles
    $Global:UM_ProbeTotalFiles = $totalFiles

    $probeOnResult = {
        param($result)
        $Global:UM_ProbeCount++
        UM-LogSmartProbe -Result $result
        $Global:UM_ScannedCount = $Global:UM_ProbeCount
        $Global:UM_ScanTotal    = $Global:UM_ProbeTotalFiles
        $Global:UM_Mode         = $Global:Context.Mode
    }

    Invoke-UMWorkerPool `
        -Files      $filesToProbe `
        -Workers    $Context.Workers `
        -TempDir    $probeTempDir `
        -ModuleRoot $moduleRoot `
        -Modules    @("Common.psm1", "Logging.psm1", "SmartCompression.psm1") `
        -WorkScript $probeWorkScript `
        -Extra      $probeExtra `
        -OnResult   $probeOnResult `
        -OnProgress { UM-PhaseTwoConsole }

    $Global:UM_ScannedCount  = $totalFiles
    $Global:UM_ScanTotal     = $totalFiles
    $Global:UM_WorkerFolders = @("Done")

    UM-PhaseTwoConsole
    Start-Sleep -Milliseconds 500
}

# =====================================================================
# Probe a single file using sample encodes
# Fast mode:    1 sample at 50%
# Accurate mode: 3 samples at 25%, 50%, 75%
# Hard filters: skip hevc/av1/vp9, duration < 3min, bitrate < 500kbps
# Skip rule:    if any sample exceeds source bitrate -> skip
# =====================================================================
function Invoke-UMProbeFile {
    param(
        [string]$FilePath,
        [bool]$AccurateMode  = $false,
        [int]$CrfValue       = 22,
        [string]$StatusFile        = "",
        [int]$WorkerID             = 0,
        [string]$FolderName        = "",
        [string]$EpisodeName       = "",
        [double[]]$ExistingSampleKbps = @()
    )

    $originalBytes = (Get-Item $FilePath).Length
    $originalMB    = [math]::Round($originalBytes / 1MB, 2)

    # ---- Call 1: Headers ---- #
    $headerArgs = @(
        "-v", "error",
        "-show_entries", "stream=codec_name,width,height,bit_rate,r_frame_rate,profile",
        "-show_entries", "format=duration,bit_rate,size",
        "-of", "json",
        $FilePath
    )
    $headerJson = & ffprobe @headerArgs 2>$null | Out-String
    $headerData = $headerJson | ConvertFrom-Json

    $vs  = $headerData.streams | Where-Object { $_.codec_name -and $_.width } | Select-Object -First 1
    $as  = $headerData.streams | Where-Object { $_.codec_name -and -not $_.width } | Select-Object -First 1
    $fmt = $headerData.format

    if (-not $vs) {
        return [ordered]@{
            Type        = "SmartProbe"
            Path        = $FilePath
            SkipReason  = "NoVideoStream"
            Verdict     = "Skip"
            OriginalMB  = $originalMB
            EstimatedMB = $originalMB
            SavedMB     = 0
            SavedPct    = 0
            Confidence  = "N/A"
            ProbeMethod = if ($AccurateMode) { "Accurate" } else { "Fast" }
            ProbedAt    = (Get-Date).ToString("s")
        }
    }

    $codec       = $vs.codec_name
    $width       = [int]$vs.width
    $height      = [int]$vs.height
    $durationSec = [double]$fmt.duration

    $fpsParts = $vs.r_frame_rate -split "/"
    $fps = if ($fpsParts.Count -eq 2 -and [double]$fpsParts[1] -gt 0) {
        [math]::Round([double]$fpsParts[0] / [double]$fpsParts[1], 2)
    } else { 24 }

    $videoBitrateKbps = if ($vs.bit_rate -and $vs.bit_rate -ne "N/A") {
        [math]::Round([long]$vs.bit_rate / 1000, 1)
    } elseif ($fmt.bit_rate -and $fmt.bit_rate -ne "N/A") {
        [math]::Round([long]$fmt.bit_rate / 1000, 1)
    } else { 0 }

    $audioBitrateKbps = if ($as -and $as.bit_rate -and $as.bit_rate -ne "N/A") {
        [math]::Round([long]$as.bit_rate / 1000, 1)
    } else { 128 }

    # ---- Hard filters ---- #
    $skipReason = $null

    if ($codec -in @("hevc", "av1", "vp9")) {
        $skipReason = "AlreadyModernCodec"
    } elseif ($durationSec -lt 180) {
        $skipReason = "DurationTooShort"
    } elseif ($videoBitrateKbps -gt 0 -and $videoBitrateKbps -lt 500) {
        $skipReason = "BitrateTooLow"
    }

    if ($skipReason) {
        return [ordered]@{
            Type        = "SmartProbe"
            Path        = $FilePath
            Codec       = $codec
            Width       = $width
            Height      = $height
            DurationSec = [math]::Round($durationSec, 1)
            OriginalMB  = $originalMB
            EstimatedMB = $originalMB
            SavedMB     = 0
            SavedPct    = 0
            Confidence  = "N/A"
            SkipReason  = $skipReason
            Verdict     = "Skip"
            ProbeMethod = if ($AccurateMode) { "Accurate" } else { "Fast" }
            ProbedAt    = (Get-Date).ToString("s")
        }
    }

    # ---- Sample encode points ---- #
    $samplePoints = if ($AccurateMode) {
        @(
            [int]($durationSec * 0.25),
            [int]($durationSec * 0.50),
            [int]($durationSec * 0.75)
        )
    } else {
        @([int]($durationSec * 0.50))
    }

    # Seed results with existing fast sample (the 50% point) when upgrading
    $sampleResults = @()
    if ($ExistingSampleKbps -and $ExistingSampleKbps.Count -gt 0) {
        $sampleResults += $ExistingSampleKbps[0]
        # Remove the 50% point from the list since we already have it
        $samplePoints = $samplePoints | Where-Object { $_ -ne [int]($durationSec * 0.50) }
    }

	$passNumber = $ExistingSampleKbps.Count
	foreach ($seekPoint in $samplePoints) {
		$passNumber++
		$totalPasses = $samplePoints.Count + $ExistingSampleKbps.Count

        if ($StatusFile -and (Test-Path (Split-Path $StatusFile -Parent))) {
            @{ WorkerID = $WorkerID; Folder = $FolderName; Episode = $EpisodeName; Sample = $passNumber; TotalSamples = $totalPasses; SampleStart = (Get-Date).ToString("o") } |
                ConvertTo-Json -Compress |
                Set-Content -Path $StatusFile -Encoding UTF8
        }

        $seek = [math]::Max(0, [math]::Min($seekPoint, [int]$durationSec - 35))

        $encodeOutput = & ffmpeg -ss $seek -t 30 -i $FilePath `
            -c:v libx265 -crf $CrfValue -c:a copy -f null NUL 2>&1

        $summaryLine = $encodeOutput | Select-String "encoded \d+ frames"
        if ($summaryLine) {
            $kbsMatch = [regex]::Match($summaryLine.Line, "([\d.]+)\s*kb/s")
            if ($kbsMatch.Success) {
                $sampleResults += [double]$kbsMatch.Groups[1].Value
            }
        }
    }

    # ---- No valid sample results ---- #
    if ($sampleResults.Count -eq 0) {
        return [ordered]@{
            Type        = "SmartProbe"
            Path        = $FilePath
            Codec       = $codec
            Width       = $width
            Height      = $height
            DurationSec = [math]::Round($durationSec, 1)
            OriginalMB  = $originalMB
            EstimatedMB = $originalMB
            SavedMB     = 0
            SavedPct    = 0
            Confidence  = "N/A"
            SkipReason  = "SampleEncodeFailed"
            Verdict     = "Skip"
            ProbeMethod = if ($AccurateMode) { "Accurate" } else { "Fast" }
            ProbedAt    = (Get-Date).ToString("s")
        }
    }

    # ---- Skip rule: any sample exceeds source bitrate ---- #
    $anyExceedsSource = $sampleResults | Where-Object { $_ -gt $videoBitrateKbps }
    if ($anyExceedsSource) {
        return [ordered]@{
            Type        = "SmartProbe"
            Path        = $FilePath
            Codec       = $codec
            Width       = $width
            Height      = $height
            DurationSec = [math]::Round($durationSec, 1)
            OriginalMB  = $originalMB
            EstimatedMB = $originalMB
            SavedMB     = 0
            SavedPct    = 0
            Confidence  = "N/A"
            SkipReason  = "SampleExceedsSource"
            Verdict     = "Skip"
            ProbeMethod = if ($AccurateMode) { "Accurate" } else { "Fast" }
            ProbedAt    = (Get-Date).ToString("s")
        }
    }

    # ---- Calculate estimate from sample average ---- #
    $avgSampleKbps    = ($sampleResults | Measure-Object -Average).Average
    $estimatedVideoKbps = [math]::Round($avgSampleKbps, 1)
    $estimatedTotalKbps = $estimatedVideoKbps + $audioBitrateKbps
    $estimatedMB = [math]::Round(($estimatedTotalKbps * 1000 / 8 * $durationSec) / 1MB, 2)
    $savedMB     = [math]::Round($originalMB - $estimatedMB, 2)
    $savedPct    = if ($originalMB -gt 0) { [math]::Round($savedMB / $originalMB * 100, 1) } else { 0 }

    # ---- Confidence from variance between samples ---- #
    $confidence = "High"
    if ($sampleResults.Count -gt 1) {
        $minSample = ($sampleResults | Measure-Object -Minimum).Minimum
        $maxSample = ($sampleResults | Measure-Object -Maximum).Maximum
        $spread    = if ($avgSampleKbps -gt 0) { ($maxSample - $minSample) / $avgSampleKbps * 100 } else { 0 }
        $confidence = if    ($spread -le 15) { "High" }
                      elseif ($spread -le 40) { "Medium" }
                      else                    { "Low" }
    }

    # ---- Verdict ---- #
    $verdict = if ($savedPct -ge 10) { "Compress" } else { "Skip" }
    $skipReason = if ($verdict -eq "Skip") { "SavingsBelowThreshold" } else { $null }

    return [ordered]@{
        Type        = "SmartProbe"
        Path        = $FilePath
        Codec       = $codec
        Width       = $width
        Height      = $height
        DurationSec = [math]::Round($durationSec, 1)
        OriginalMB  = $originalMB
        EstimatedMB = $estimatedMB
        SavedMB     = $savedMB
        SavedPct    = $savedPct
        Confidence  = $confidence
        SkipReason  = $skipReason
        Verdict     = $verdict
        SampleKbps  = @($sampleResults)
        ProbeMethod = if ($AccurateMode) { "Accurate" } else { "Fast" }
        ProbedAt    = (Get-Date).ToString("s")
    }
}

# =====================================================================
# Write a SmartProbe result to UnifiedLog.json
# =====================================================================

# =====================================================================
# Write a SmartProbe result to UnifiedLog.json
# =====================================================================
function UM-LogSmartProbe {
    param([object]$Result)

    $entry = [ordered]@{
        Type        = "SmartProbe"
        Path        = $Result.Path
        Codec       = $Result.Codec
        Width       = $Result.Width
        Height      = $Result.Height
        DurationSec = $Result.DurationSec
        OriginalMB  = $Result.OriginalMB
        EstimatedMB = $Result.EstimatedMB
        SavedMB     = $Result.SavedMB
        SavedPct    = $Result.SavedPct
        Confidence  = $Result.Confidence
        SkipReason  = $Result.SkipReason
        Verdict     = $Result.Verdict
        SampleKbps  = $Result.SampleKbps
        ProbeMethod = $Result.ProbeMethod
        Timestamp   = $Result.ProbedAt
    }

    $json = $entry | ConvertTo-Json -Compress -Depth 5
    $logPath = $Global:UnifiedMachineLogPath
    Add-Content -Path $logPath -Value $json -Encoding UTF8
}

# =====================================================================
# Compress a single file (called by worker via Invoke-UMWorkerPool)
# =====================================================================
function Invoke-UMCompressFile {
    param($sourcePath, $extra, $statusFile, $workerID)

    $outputRoot = $extra.OutputRoot
    $sourceRoot = $extra.SourceRoot
    $crf        = $extra.CRF

    $relativePath = ""
    if ($sourcePath -match "(?i)(.*\\Shows\\)(.+)") {
        $relativePath = "Shows\" + $matches[2]
    } elseif ($sourcePath -match "(?i)(.*\\Movies\\)(.+)") {
        $relativePath = "Movies\" + $matches[2]
    } elseif ($sourceRoot -and $sourcePath.StartsWith($sourceRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        $relativePath = $sourcePath.Substring($sourceRoot.Length).TrimStart("\", "/")
    } else {
        $relativePath = Split-Path $sourcePath -Leaf
    }

    $ext        = [System.IO.Path]::GetExtension($sourcePath)
    $outputPath = Join-Path (Join-Path $outputRoot "Compressed") $relativePath
    $outputPath = [System.IO.Path]::ChangeExtension($outputPath, $ext)
    $outputDir  = Split-Path $outputPath -Parent
    if (-not (Test-Path $outputDir)) {
        New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    }

    $showFolder  = Split-Path (Split-Path $sourcePath -Parent) -Leaf
    $episodeName = [System.IO.Path]::GetFileNameWithoutExtension($sourcePath)
    $fileStart   = Get-Date
	$estimatedMB = if ($extra.ProbeResultsMap -and $extra.ProbeResultsMap[$episodeName]) { $extra.ProbeResultsMap[$episodeName] } else { 0 }
    @{ WorkerID = $workerID; Folder = $showFolder; Episode = $episodeName; FileStart = $fileStart.ToString("s"); OutputPath = $outputPath; EstimatedMB = $estimatedMB } |
        ConvertTo-Json -Compress | Set-Content -Path $statusFile -Encoding UTF8

    $originalMB = [math]::Round((Get-Item $sourcePath).Length / 1MB, 2)
    $argList = @("-y", "-i", $sourcePath, "-c:v", "libx265", "-crf", $crf.ToString(), "-c:a", "copy", "-loglevel", "error", $outputPath)
    & ffmpeg @argList 2>&1 | Out-Null
    $exitCode = $LASTEXITCODE

    $compressedMB = if (Test-Path $outputPath) { [math]::Round((Get-Item $outputPath).Length / 1MB, 2) } else { 0 }
    $savedMB      = [math]::Round($originalMB - $compressedMB, 2)
    $savedPct     = if ($originalMB -gt 0) { [math]::Round(($savedMB / $originalMB) * 100, 1) } else { 0 }

    return [ordered]@{
        Type         = "Compress"
        Path         = $sourcePath
        OutputPath   = $outputPath
        CRF          = $crf
        OriginalMB   = $originalMB
        CompressedMB = $compressedMB
        SavedMB      = $savedMB
        SavedPct     = $savedPct
        ExitCode     = $exitCode
        Timestamp    = (Get-Date).ToString("s")
    }
}

# =====================================================================
# Invoke-UMCompress - parallel compress with restart safety
# =====================================================================
function Invoke-UMCompress {

    $Context   = $Global:Context
    $logsRoot  = Split-Path $Global:UnifiedMachineLogPath -Parent
    $queuePath = Join-Path $logsRoot "CompressionQueue.json"

    if (-not (Test-Path $queuePath)) {
        UM-Output "No compression queue found. Please run the probe and select files first."
        return
    }

    $payloadRaw = Get-Content $queuePath -Raw | ConvertFrom-Json
    $outputRoot = $payloadRaw.outputPath
    $allPaths   = @($payloadRaw.paths)
    $sourceRoot = if ($payloadRaw.sourceRoot) { $payloadRaw.sourceRoot.TrimEnd('\', '/') } else { "" }
    $crf        = if ($payloadRaw.crf -gt 0) { [int]$payloadRaw.crf } else { if ($Context.CrfValue -gt 0) { [int]$Context.CrfValue } else { 22 } }

    $completedPaths = @{}
    $unifiedLog = UM-ReadUnifiedLog
    if ($unifiedLog) {
        $unifiedLog |
            Where-Object { $_.Type -eq "Compress" -and $_.ExitCode -eq 0 } |
            ForEach-Object { $completedPaths[$_.Path] = $_.OutputPath }
    }

    $filesToCompress = $allPaths | Where-Object {
        $path = $_
        if ($completedPaths.ContainsKey($path)) {
            $outPath = $completedPaths[$path]
            if ($outPath -and (Test-Path $outPath)) { return $false }
        }
        return $true
    }

    $totalFiles  = $allPaths.Count
    $doneAlready = $totalFiles - @($filesToCompress).Count
    $doneCount   = $doneAlready

    $Global:UM_CompressSessionStart = Get-Date
    $Global:UM_CompressTotalFiles   = $totalFiles
    $Global:UM_CompressDoneCount    = $doneAlready
    $Global:UM_WorkerFolders        = @($null)

    if (@($filesToCompress).Count -eq 0) {
        UM-Output "All files already compressed. Nothing to do."
        return
    }

    $compressTempDir = Join-Path $logsRoot "ScanTemp\Compress_$(Get-Random)"

	$probeResultsMap = @{}
    if ($unifiedLog) {
        $unifiedLog | Where-Object { $_.Type -eq "SmartProbe" } | ForEach-Object {
            $epName = [System.IO.Path]::GetFileNameWithoutExtension($_.Path)
            $probeResultsMap[$epName] = $_.EstimatedMB
        }
    }

    $compressExtra = @{
        OutputRoot      = $outputRoot
        SourceRoot      = $sourceRoot
        CRF             = $crf
        ProbeResultsMap = $probeResultsMap
    }

    $compressWorkScript = { param($f, $e, $s, $w) Invoke-UMCompressFile $f $e $s $w }

    $Global:UM_CompressDoneCount2  = $doneCount
    $Global:UM_CompressTotalFiles2 = $totalFiles
    $Global:UM_CompressCRF         = $crf

    $compressOnResult = {
        param($result)
        $Global:UM_CompressDoneCount2++
        $Global:UM_CompressDoneCount = $Global:UM_CompressDoneCount2
        $json = $result | ConvertTo-Json -Compress -Depth 5
        Add-Content -Path $Global:UnifiedMachineLogPath -Value $json -Encoding UTF8
    }

	Invoke-UMWorkerPool `
        -Files      $filesToCompress `
        -Workers    $Context.Workers `
        -TempDir    $compressTempDir `
        -ModuleRoot $moduleRoot `
        -Modules    @("Common.psm1", "Logging.psm1", "SmartCompression.psm1") `
        -WorkScript $compressWorkScript `
        -Extra      $compressExtra `
        -OnResult   $compressOnResult `
        -OnProgress { UM-CompressHeartbeatConsole }

    $Global:UM_CompressDoneCount = $Global:UM_CompressTotalFiles2
    UM-CompressFinalConsole -TotalFiles $Global:UM_CompressTotalFiles2 -CRF $Global:UM_CompressCRF

    Remove-Item $queuePath -Force -ErrorAction SilentlyContinue
}

Export-ModuleMember -Function Invoke-UMSmartProbe, Invoke-UMProbeFile, UM-LogSmartProbe, Invoke-UMCompressFile, Invoke-UMCompress