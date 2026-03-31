# ---------------------------------------------------------------------
# Core Output Router
# ---------------------------------------------------------------------
function UM-Output {
    param([string]$Message)

    if ($Global:IsGUI -and $Global:AppendConsole) {
        & $Global:AppendConsole $Message
    }
    else {
        Write-Host $Message
    }
}

# ---------------------------------------------------------------------
# Read Log (Phase 1)
# ---------------------------------------------------------------------
function UM-OutputPhaseOne {
    param($Context)

    UM-Output "Phase 1      : Checking UnifiedLog.json"
    UM-Output "Library Type : $($Context.LibraryType)"
    UM-Output "Root Path    : $($Context.RootPath)"
    UM-Output "Mode         : $($Context.Mode)"
    UM-Output ""

    Start-Sleep -Milliseconds 1250
}

# ---------------------------------------------------------------------
# SCAN OUTPUT (Phase 2)
# ---------------------------------------------------------------------
function UM-OutputScanProgressLive {

    if (-not $Global:UM_TotalFiles -or $Global:UM_TotalFiles -eq 0) {
        return
    }

    $file      = $Global:UM_CurrentScanFile
    $elapsedTS = [TimeSpan]::FromSeconds($Global:UM_ElapsedSeconds)
    $scanned   = $Global:UM_ScannedFiles
    $total     = $Global:UM_TotalFiles

    $percent = if ($total -gt 0) {
        [math]::Round(($scanned / $total) * 100)
    } else { 0 }

    UM-Output ("{0,-13} : {1}" -f "Phase 2",       "Scanning & Logging")
    UM-Output ("{0,-13} : {1}" -f "Scanning File", $file)
    UM-Output ("{0,-13} : {1}" -f "Elapsed Time",  $elapsedTS.ToString('hh\:mm\:ss'))
    UM-Output ("{0,-13} : {1}" -f "Scanned",       "$scanned/$total")
    UM-Output ("{0,-13} : {1}" -f "Completion",    "$percent%")
}

# ---------------------------------------------------------------------
# REPAIR OUTPUT (Phase 3)
# ---------------------------------------------------------------------
function UM-OutputRepairHeader {
    param(
        [Parameter(Mandatory=$true)][string]$SourcePath,
        [Parameter(Mandatory=$true)][int]$AttemptCount
    )

    UM-Output "Phase 3          : Repairing & Logging"
    UM-Output "Repairing        : $SourcePath"
}

function UM-OutputRepairProgress {
    param(
        [Parameter(Mandatory=$true)][int]$ItemIndex,
        [Parameter(Mandatory=$true)][int]$TotalItems,
        [Parameter(Mandatory=$true)][string]$StageFriendly,
        [Parameter(Mandatory=$true)][int]$CRF,
        [Parameter(Mandatory=$true)][string]$SourcePath,
        [Parameter(Mandatory=$true)][int]$AttemptCount
    )

    $attemptTS = [TimeSpan]::FromSeconds($Global:UM_AttemptSeconds)
    $fileTS    = [TimeSpan]::FromSeconds($Global:UM_FileSeconds)
    $sessionTS = [TimeSpan]::FromSeconds($Global:UM_ElapsedSeconds)

    UM-OutputRepairHeader `
        -SourcePath   $SourcePath `
        -AttemptCount $AttemptCount

    UM-Output "Repair Attempt   : $AttemptCount"
    UM-Output ("Attempt Time     : {0}" -f $attemptTS.ToString("hh\:mm\:ss"))
    UM-Output "----------------------------------------"
    UM-Output "Repairing File   : $ItemIndex / $TotalItems"
    UM-Output ("File Time        : {0}" -f $fileTS.ToString("hh\:mm\:ss"))
    UM-Output "----------------------------------------"

    $log = UM-ReadUnifiedLog
    $latestAttempt = $log |
        Where-Object { $_.Type -eq "RepairAttempt" -and $_.Path -eq $SourcePath } |
        Sort-Object Timestamp -Descending |
        Select-Object -First 1

	if ($latestAttempt -and $latestAttempt.CRF -gt 0) {
		$displayStage = $latestAttempt.StageFriendly
		$displayCRF   = $latestAttempt.CRF
	} else {
		# Fallback to live values when log is missing/zero
		$displayStage = $StageFriendly
		$displayCRF   = $CRF
	}


    UM-Output "Repair Type      : $displayStage (CRF $displayCRF)"
    UM-Output ("Elapsed Time     : {0}" -f $sessionTS.ToString("hh\:mm\:ss"))
    UM-Output "----------------------------------------"
}

function UM-OutputRepairProgressLive {

    $itemIndex     = $Global:UM_RepairItemIndex
    $totalItems    = $Global:UM_RepairTotalItems
    $stageFriendly = $Global:UM_RepairStageFriendly
    $crf           = $Global:UM_RepairCRF
    $sourcePath    = $Global:UM_RepairSourcePath
    $attemptCount  = $Global:UM_RepairAttemptCount

    if ($null -eq $itemIndex -or $null -eq $totalItems -or
        -not $stageFriendly -or -not $sourcePath -or
        $null -eq $crf -or $null -eq $attemptCount) {
        return
    }

    UM-OutputRepairProgress `
        -ItemIndex     $itemIndex `
        -TotalItems    $totalItems `
        -StageFriendly $stageFriendly `
        -CRF           $crf `
        -SourcePath    $sourcePath `
        -AttemptCount  $attemptCount
}

Export-ModuleMember -Function *
