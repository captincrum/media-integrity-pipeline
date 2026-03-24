# =====================================================================
# UnifiedMedia.Repair.psm1 — Updated for GUI + Correct Folder Structure
# =====================================================================

function UM-GetRepairQueue {
    $log = UM-ReadUnifiedLog
    if (-not $log) { return @() }

    $pending = $log |
        Where-Object { $_.Type -eq "ToRepair" -and $_.RepairStatus -eq "Pending" }

    $results = $log | Where-Object { $_.Type -eq "RepairResult" }

    $queue = foreach ($p in $pending) {
        $lastResult = $results |
            Where-Object { $_.Path -eq $p.Path } |
            Sort-Object Timestamp -Descending |
            Select-Object -First 1

        if (-not $lastResult) { $p }
    }

    return @($queue)
}

# =====================================================================
# MAIN REPAIR FUNCTION
# =====================================================================

function Invoke-UMRepair {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Context
    )

    $queue = @(UM-GetRepairQueue)
    if (-not $queue -or $queue.Count -eq 0) {
        return "NO_REPAIR_ITEMS"
    }

    $totalItems    = $queue.Count
    $sessionStart  = Get-Date
    $itemIndex     = 0

    # ------------------------------------------------------------
    # Helper: Scan file for errors
    # ------------------------------------------------------------
    function Invoke-ScanFile {
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

    # ------------------------------------------------------------
    # Helper: Quality check
    # ------------------------------------------------------------
    function Invoke-QualityCheckInternal {
        param(
            [string]$Original,
            [string]$Repaired,
            [string]$StageName,
            [int]   $CRF
        )

        $targetSSIM = 0.96

        $ssimRaw = & ffmpeg -hide_banner -i $Original -i $Repaired `
            -lavfi "ssim" -f null - 2>&1
        $ssimMatch = $ssimRaw | Select-String -Pattern "All:(\d+\.\d+)"
        $ssim = if ($ssimMatch) { [double]$ssimMatch.Matches[0].Groups[1].Value } else { 0 }

        $psnrRaw = & ffmpeg -hide_banner -i $Original -i $Repaired `
            -lavfi "psnr" -f null - 2>&1
        $psnrMatch = $psnrRaw | Select-String -Pattern "average:(\d+\.\d+)"
        $psnr = if ($psnrMatch) { [double]$psnrMatch.Matches[0].Groups[1].Value } else { 0 }

        $percent = if ($targetSSIM -gt 0) { ($ssim / $targetSSIM) * 100 } else { 0 }
        if ($percent -gt 100) { $percent = 100 }
        $distance = 100 - $percent

        $status = if ($ssim -ge $targetSSIM) { "Pass" } else { "Loss" }

        UM-LogQuality `
            -Original $Original `
            -Comparison $Repaired `
            -SSIM $ssim `
            -PSNR $psnr `
            -PercentAchieved ([math]::Round($percent,2)) `
            -Distance ([math]::Round($distance,2)) `
            -QualityStatus $status `
            -CheckedAt (Get-Date).ToString("s")

        if ($status -eq "Pass") {
            return @{ Result = "Pass"; QualityStatus = $status }
        }

        $crfDrop = switch ($distance) {
            {$_ -le 1}  {1; break}
            {$_ -le 3}  {2; break}
            {$_ -le 7}  {3; break}
            {$_ -le 12} {4; break}
            default     {5}
        }

        $nextCRF = $CRF - $crfDrop
        if ($nextCRF -lt 1) { $nextCRF = 1 }

        return @{
            Result        = "RetrySameStage"
            NextCRF       = $nextCRF
            QualityStatus = $status
        }
    }

    # ------------------------------------------------------------
    # Helper: Run a repair stage
    # ------------------------------------------------------------
    function Invoke-RepairStage {
        param(
            [string]   $StageName,
            [string]   $SourcePath,
            [string]   $OutputPath,
            [string]   $VideoMode,
            [string]   $AudioMode,
            [int]      $CRF,
            [string[]] $ExtraArgs,
            [int]      $AttemptCount,
            [int]      $ItemIndex,
            [int]      $TotalItems,
            [datetime] $SessionStart,
            [datetime] $FileStart,
            [hashtable]$FriendlyNames
        )

        # -----------------------------
        # GUI MODE: suppress console UI
        # -----------------------------
        $suppressUI = $Context.PSObject.Properties.Name -contains "IsGUI" -and $Context.IsGUI

        if (-not $suppressUI) {
            Clear-Host
            Write-Host "----------------------------------------"
            Write-Host ("Repairing           : {0}" -f $SourcePath)
            Write-Host ("Repair Attempt      : {0}" -f $AttemptCount)
            Write-Host "----------------------------------------"
            Write-Host ("Repairing File      : {0} / {1}" -f $ItemIndex, $TotalItems)
            Write-Host ("Repair Type         : {0} (CRF {1})" -f $FriendlyNames[$StageName], $CRF)
            Write-Host "----------------------------------------"
        }

        # Build ffmpeg args
        $argList = @("-y", "-i", $SourcePath)

        if ($VideoMode) {
            $argList += @("-c:v", $VideoMode)
            if ($CRF -gt 0) {
                $argList += @("-crf", $CRF.ToString())
            }
        } else {
            $argList += @("-c", "copy")
        }

        if ($AudioMode) {
            $argList += @("-c:a", $AudioMode)
        }

        if ($ExtraArgs) {
            $argList += $ExtraArgs
        }

        $argList += @($OutputPath, "-loglevel", "quiet")

        # Run ffmpeg
        & ffmpeg @argList
        $exitCode = $LASTEXITCODE

        $originalSize = (Get-Item $SourcePath).Length
        $repairedSize = if (Test-Path $OutputPath) { (Get-Item $OutputPath).Length } else { 0 }

        $attempt = [PSCustomObject]@{
            Path           = $SourcePath
            Stage          = $FriendlyNames[$StageName]
            OutputPath     = $OutputPath
            CRF            = $CRF
            OriginalSizeMB = [math]::Round($originalSize / 1MB, 2)
            RepairedSizeMB = [math]::Round($repairedSize / 1MB, 2)
            SizeRatio      = if ($originalSize -gt 0) { [math]::Round($repairedSize / $originalSize, 2) } else { 0 }
            ErrorsAfter    = @()
            AttemptedAt    = (Get-Date).ToString("s")
        }

        if (-not (Test-Path $OutputPath)) {
            $attempt.ErrorsAfter = @("Output file not created")
        } else {
            $probe = & ffprobe -v error -select_streams v -show_entries stream=codec_type -of csv=p=0 $OutputPath
            if ($probe -ne "video") {
                $attempt.ErrorsAfter = @("No video stream in output file")
            } else {
                $attempt.ErrorsAfter = Invoke-ScanFile -FilePath $OutputPath
            }
        }

        UM-LogRepairAttempt `
            -Path $attempt.Path `
            -StageInternal $StageName `
            -StageFriendly $attempt.Stage `
            -OutputPath $attempt.OutputPath `
            -CRF $attempt.CRF `
            -OriginalSizeMB $attempt.OriginalSizeMB `
            -RepairedSizeMB $attempt.RepairedSizeMB `
            -SizeRatio $attempt.SizeRatio `
            -ErrorsAfter $attempt.ErrorsAfter `
            -AttemptedAt $attempt.AttemptedAt

        if ($repairedSize -gt ($originalSize * 1.5)) {
            return $false
        }

        if ($exitCode -ne 0) {
            return $false
        }

        return ($attempt.ErrorsAfter.Count -eq 0)
    }

    # ------------------------------------------------------------
    # MAIN REPAIR LOOP
    # ------------------------------------------------------------
    foreach ($item in $queue) {
        $itemIndex++

        $sourcePath = $item.Path
        if (-not (Test-Path $sourcePath)) {
            UM-LogRepairResult `
                -Path $sourcePath `
                -Library $Context.LibraryType `
                -RepairStatus "Missing" `
                -QualityStatus "Unknown" `
                -RepairedAt (Get-Date).ToString("s")
            continue
        }

        # -----------------------------
        # USE CONTEXT LIBRARY TYPE
        # -----------------------------
        $libraryType = $Context.LibraryType

        # -----------------------------
        # RELATIVE PATH FIX
        # -----------------------------
        $relative = $null

        if ($Context.RootPath -and
            $sourcePath.StartsWith($Context.RootPath, [System.StringComparison]::OrdinalIgnoreCase)) {

            $relative = $sourcePath.Substring($Context.RootPath.Length).TrimStart("\","/")

        } else {
            # fallback: strip up to Movies/Shows
            $libIndex = $sourcePath.IndexOf($libraryType, [System.StringComparison]::OrdinalIgnoreCase)
            if ($libIndex -ge 0) {
                $relative = $sourcePath.Substring($libIndex + $libraryType.Length).TrimStart("\","/")
            } else {
                $relative = [System.IO.Path]::GetFileName($sourcePath)
            }
        }

        $relativeDir = [System.IO.Path]::GetDirectoryName($relative)

        $ext      = [System.IO.Path]::GetExtension($sourcePath)
        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($sourcePath)

        $targetDirBase = Join-Path $Context.RepairedRoot $libraryType
        $targetFullDir = if ($relativeDir) {
            Join-Path $targetDirBase $relativeDir
        } else {
            $targetDirBase
        }

        if (-not (Test-Path $targetFullDir)) {
            New-Item -ItemType Directory -Path $targetFullDir -Force | Out-Null
        }

        $targetPathSameExt = Join-Path $targetFullDir ($baseName + $ext)
        $targetPathMp4     = Join-Path $targetFullDir ($baseName + ".mp4")

        # --------------------------------------------------------
        # Repair stages
        # --------------------------------------------------------
        $repairStages = @(
            @{ Name="Remux";                   Video=$null;     Audio=$null; Extra=@();                   ForceExt=$null  },
            @{ Name="ReencodeVideo_CopyAudio"; Video="libx264"; Audio="copy"; Extra=@();                   ForceExt=$null  },
            @{ Name="ReencodeVideo_AAC";       Video="libx264"; Audio="aac";  Extra=@();                   ForceExt=$null  },
            @{ Name="FullReencode";            Video="libx264"; Audio="aac";  Extra=@("-preset","medium"); ForceExt=$null  },
            @{ Name="LastResortMp4";           Video="libx264"; Audio="aac";  Extra=@("-preset","medium"); ForceExt=".mp4" }
        )

        $success            = $false
        $attemptCount       = 0
        $successfulStage    = $null
        $finalQualityStatus = "Unknown"

        $friendlyNames = @{
            "Remux"                   = "Fast Repair"
            "ReencodeVideo_CopyAudio" = "Standard Repair"
            "ReencodeVideo_AAC"       = "Enhanced Repair"
            "FullReencode"            = "Deep Repair"
            "LastResortMp4"           = "Emergency Conversion"
        }

        foreach ($stage in $repairStages) {
            if ($success) { break }

            $currentCRF = 18
            $stageDone  = $false

            while (-not $stageDone) {
                $attemptCount++

                $outputPath = if ($stage.ForceExt) {
                    Join-Path $targetFullDir ($baseName + $stage.ForceExt)
                } else {
                    $targetPathSameExt
                }

                $stageSuccess = Invoke-RepairStage `
                    -StageName     $stage.Name `
                    -SourcePath    $sourcePath `
                    -OutputPath    $outputPath `
                    -VideoMode     $stage.Video `
                    -AudioMode     $stage.Audio `
                    -CRF           $currentCRF `
                    -ExtraArgs     $stage.Extra `
                    -AttemptCount  $attemptCount `
                    -ItemIndex     $itemIndex `
                    -TotalItems    $totalItems `
                    -SessionStart  $sessionStart `
                    -FileStart     (Get-Date) `
                    -FriendlyNames $friendlyNames

                if (-not $stageSuccess) {
                    $stageDone = $true
                    break
                }

                $qualityResult = Invoke-QualityCheckInternal -Original $sourcePath -Repaired $outputPath -StageName $stage.Name -CRF $currentCRF

                $finalQualityStatus = $qualityResult.QualityStatus

                if ($qualityResult.Result -eq "Pass") {
                    $success           = $true
                    $stageDone         = $true
                    $successfulStage   = $stage.Name
                } elseif ($qualityResult.Result -eq "RetrySameStage") {
                    $nextCRF = [int]$qualityResult.NextCRF
                    if ($nextCRF -ge $currentCRF -or $nextCRF -lt 1) {
                        $stageDone = $true
                    } else {
                        $currentCRF = $nextCRF
                    }
                } else {
                    $stageDone = $true
                }
            }
        }

        # --------------------------------------------------------
        # Final result logging
        # --------------------------------------------------------
        if ($success) {

            if ($successfulStage -eq "LastResortMp4") {
                if (Test-Path $targetPathMp4 -and Test-Path $targetPathSameExt) {
                    try {
                        Remove-Item $targetPathSameExt -Force
                    } catch {}
                }
            }

            UM-LogRepairResult `
                -Path $sourcePath `
                -Library $libraryType `
                -RepairStatus "Repaired" `
                -QualityStatus $finalQualityStatus `
                -RepairedAt (Get-Date).ToString("s")

        } else {

            UM-LogRepairResult `
                -Path $sourcePath `
                -Library $libraryType `
                -RepairStatus "Failed" `
                -QualityStatus $finalQualityStatus `
                -RepairedAt (Get-Date).ToString("s")
        }
    }

    return "OK"
}

Export-ModuleMember -Function Invoke-UMRepair, UM-GetRepairQueue
