# =====================================================================
# UnifiedMedia.Logging.psm1 — Machine Log Only (NDJSON)
# =====================================================================

function UM-LogInit {
    if (-not $Global:UnifiedMachineLogPath) {
        throw "UnifiedMachineLogPath must be set before calling UM-LogInit."
    }

    $path = $Global:UnifiedMachineLogPath
    $dir  = Split-Path $path -Parent

    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    if (-not (Test-Path $path)) {
        "" | Set-Content -Path $path -Encoding UTF8
    }
}

# =====================================================================
# Machine Log Reader (NDJSON)
# =====================================================================

function UM-ReadUnifiedLog {
    if (-not (Test-Path $Global:UnifiedMachineLogPath)) {
        return @()
    }

    $lines = Get-Content $Global:UnifiedMachineLogPath

    $objects = foreach ($line in $lines) {
        $trim = $line.Trim()
        if ($trim -eq "") { continue }

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
# Append Entry to Machine Log Only
# =====================================================================

function UM-AppendLogEntry {
    param([hashtable]$Entry)

    # Add timestamp
    $Entry["Timestamp"] = (Get-Date).ToString("s")

    # MACHINE LOG ONLY
    $machineJson = $Entry | ConvertTo-Json -Depth 10 -Compress
    Add-Content -Path $Global:UnifiedMachineLogPath -Value ($machineJson + "`n")
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
        [string]$StageFriendly,
        [string]$OutputPath,
        [int]   $CRF,
        [double]$OriginalSizeMB,
        [double]$RepairedSizeMB,
        [double]$SizeRatio,
        [array] $ErrorsAfter
    )

    UM-AppendLogEntry ([ordered]@{
        Type           = "RepairAttempt"
        Path           = $Path
        StageFriendly  = $StageFriendly
        OutputPath     = $OutputPath
        CRF            = $CRF
        OriginalSizeMB = $OriginalSizeMB
        RepairedSizeMB = $RepairedSizeMB
        SizeRatio      = $SizeRatio
        ErrorsAfter    = $ErrorsAfter
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
