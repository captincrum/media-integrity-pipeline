# =====================================================================
# UnifiedMedia.Logging.psm1 — Dual Log System (Human + Machine)
# =====================================================================

function UM-LogInit {
    if (-not $Global:UnifiedHumanLogPath) {
        throw "UnifiedHumanLogPath must be set before calling UM-LogInit."
    }
    if (-not $Global:UnifiedMachineLogPath) {
        throw "UnifiedMachineLogPath must be set before calling UM-LogInit."
    }

    foreach ($path in @($Global:UnifiedHumanLogPath, $Global:UnifiedMachineLogPath)) {
        $dir = Split-Path $path -Parent
        if (-not (Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
        if (-not (Test-Path $path)) {
            "[]" | Set-Content -Path $path -Encoding UTF8
        }
    }
}

# =====================================================================
# Canonical Field Order
# =====================================================================

$Global:UM_FieldOrder = @(
    "Type","Path","Original","Comparison","Library",
    "StageInternal","StageFriendly","OutputPath","CRF",
    "OriginalSizeMB","RepairedSizeMB","SizeRatio",
    "Errors","ErrorsAfter","RepairStatus","QualityStatus",
    "PercentAchieved","Distance","AttemptedAt","CheckedAt",
    "RepairedAt","AddedAt","Timestamp"
)

# =====================================================================
# Machine Log Reader
# =====================================================================

function UM-ReadUnifiedLog {
    if (-not (Test-Path $Global:UnifiedMachineLogPath)) {
        return @()
    }

    # Read file line-by-line (NDJSON format)
    $lines = Get-Content $Global:UnifiedMachineLogPath
	
    $objects = foreach ($line in $lines) {
        $trim = $line.Trim()

        # Skip empty lines or the initial []
        if ($trim -eq "" -or $trim -eq "[]") { continue }

        try {
            $trim | ConvertFrom-Json
        }
        catch {
            Write-Host "Skipping invalid JSON line in machine log."
        }
    }

    return @($objects)
}

# =====================================================================
# Append Entry to Both Logs
# =====================================================================

function UM-AppendLogEntry {
    param([hashtable]$Entry)

    # Add timestamp
    $Entry["Timestamp"] = (Get-Date).ToString("s")

    # ---------------------------------------------------------------
    # MACHINE LOG (strict JSON)
    # ---------------------------------------------------------------
    $machineJson = $Entry | ConvertTo-Json -Depth 10 -Compress
    Add-Content -Path $Global:UnifiedMachineLogPath -Value ($machineJson + "`n")

    # ---------------------------------------------------------------
    # HUMAN LOG (aligned, pretty JSON)
    # ---------------------------------------------------------------

    # Build ordered key list
    $orderedKeys = @()
    $orderedKeys += ($Global:UM_FieldOrder | Where-Object { $Entry.ContainsKey($_) })
    $orderedKeys += ($Entry.Keys | Where-Object { $_ -notin $Global:UM_FieldOrder })

    # Determine max key length for alignment
    $maxKeyLen = ($orderedKeys | Measure-Object -Maximum Length).Maximum

    # Build JSON lines
    $jsonLines = @()
    $jsonLines += "{"

    $i = 0
    foreach ($key in $orderedKeys) {
        $value = $Entry[$key]

        # Format value
        if ($value -is [string]) {
            $valText = '"' + ($value.Replace('\','\\').Replace('"','\"')) + '"'
        }
        elseif ($value -is [array]) {
            if ($value.Count -eq 0) {
                $valText = "[]"
            }
            else {
                $escaped = $value | ForEach-Object { '"' + ($_ -replace '"','\"') + '"' }
                $valText = "[ " + ($escaped -join ", ") + " ]"
            }
        }
        else {
            $valText = $value
        }

        # Align colons
        $padding = " " * ($maxKeyLen - $key.Length)
        $comma = if ($i -lt $orderedKeys.Count - 1) { "," } else { "" }

        $jsonLines += ('    "' + $key + '"' + $padding + ' : ' + $valText + $comma)
        $i++
    }

    $jsonLines += "}"
    $entryJson = $jsonLines -join "`n"

    # Append to human log
    $raw = Get-Content $Global:UnifiedHumanLogPath -Raw
    $trim = $raw.Trim()

    if ($trim -eq "" -or $trim -eq "[]") {
        $newContent = "[`n$entryJson`n]"
    }
    else {
        $last = $trim.LastIndexOf(']')
        $before = $trim.Substring(0, $last).TrimEnd()

        if ($before.EndsWith("[")) {
            $newContent = "$before`n$entryJson`n]"
        }
        else {
            $newContent = "$before,`n$entryJson`n]"
        }
    }

    Set-Content -Path $Global:UnifiedHumanLogPath -Value $newContent -Encoding UTF8
}

# =====================================================================
# LOG EVENT TYPES
# =====================================================================

function UM-LogScan {
    param(
        [string]$Path,
        [string]$Library,
        [array] $Errors
    )

    UM-AppendLogEntry ([ordered]@{
        Type    = "Scan"
        Path    = $Path
        Library = $Library
        Errors  = $Errors
    })
}

function UM-LogToRepair {
    param(
        [string]$Path,
        [string]$Library,
        [array] $Errors,
        [string]$RepairStatus,
        [string]$AddedAt
    )

    UM-AppendLogEntry ([ordered]@{
        Type         = "ToRepair"
        Path         = $Path
        Library      = $Library
        Errors       = $Errors
        RepairStatus = $RepairStatus
        AddedAt      = $AddedAt
    })
}

function UM-LogRepairAttempt {
    param(
        [string]$Path,
        [string]$StageInternal,
        [string]$StageFriendly,
        [string]$OutputPath,
        [int]   $CRF,
        [double]$OriginalSizeMB,
        [double]$RepairedSizeMB,
        [double]$SizeRatio,
        [array] $ErrorsAfter,
        [string]$AttemptedAt
    )

    UM-AppendLogEntry ([ordered]@{
        Type           = "RepairAttempt"
        Path           = $Path
        StageInternal  = $StageInternal
        StageFriendly  = $StageFriendly
        OutputPath     = $OutputPath
        CRF            = $CRF
        OriginalSizeMB = $OriginalSizeMB
        RepairedSizeMB = $RepairedSizeMB
        SizeRatio      = $SizeRatio
        ErrorsAfter    = $ErrorsAfter
        AttemptedAt    = $AttemptedAt
    })
}

function UM-LogQuality {
    param(
        [string]$Original,
        [string]$Comparison,
        [double]$SSIM,
        [double]$PSNR,
        [double]$PercentAchieved,
        [double]$Distance,
        [string]$QualityStatus,
        [string]$CheckedAt
    )

    UM-AppendLogEntry ([ordered]@{
        Type            = "Quality"
        Original        = $Original
        Comparison      = $Comparison
        SSIM            = $SSIM
        PSNR            = $PSNR
        PercentAchieved = $PercentAchieved
        Distance        = $Distance
        QualityStatus   = $QualityStatus
        CheckedAt       = $CheckedAt
    })
}

function UM-LogRepairResult {
    param(
        [string]$Path,
        [string]$Library,
        [string]$RepairStatus,
        [string]$QualityStatus,
        [string]$RepairedAt
    )

    UM-AppendLogEntry ([ordered]@{
        Type          = "RepairResult"
        Path          = $Path
        Library       = $Library
        RepairStatus  = $RepairStatus
        QualityStatus = $QualityStatus
        RepairedAt    = $RepairedAt
    })
}

Export-ModuleMember -Function *
