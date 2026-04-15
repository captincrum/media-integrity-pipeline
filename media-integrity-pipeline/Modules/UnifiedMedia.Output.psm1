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
# Helpers
# ---------------------------------------------------------------------
function UM-PrettyMode {
    param([string]$Mode)

    switch ($Mode) {
        "ScanOnly"   { return "Scan Only" }
        "RepairOnly" { return "Repair Only" }
        "QualityOnly"{ return "Quality Only" }
        "Full"       { return "Full" }
        default      { return $Mode }
    }
}

# ---------------------------------------------------------------------
# Read Log (Phase 1)
# ---------------------------------------------------------------------
function UM-OutputPhaseOne {
    param($Context)

    $logExists = Test-Path $Context.UnifiedMachineLogPath

    if ($logExists) {
        $session = "Preparing session data"
    } else {
        $session = "Preparing session data"
    }

    $block  = ""
    $block += "Phase 1       : $session`n"
    $block += "Mode          : $(UM-PrettyMode $Context.Mode)`n"
    $block += "Library Type  : $($Context.LibraryType)`n"
    $block += "Root Path     : $($Context.RootPath)`n"

    UM-Output $block
	Start-Sleep -Milliseconds 800
}

# ---------------------------------------------------------------------
# SCAN OUTPUT (Phase 2)
# ---------------------------------------------------------------------
function UM-OutputScanProgressLive {

    if (-not $Global:UM_TotalFiles -or $Global:UM_TotalFiles -eq 0) {
        return
    }

    $file      = $Global:UM_CurrentScanFile
    $elapsedTS = [TimeSpan]::FromSeconds($Global:UM_ElapsedSeconds).ToString("hh\:mm\:ss")
    $scanned   = $Global:UM_ScannedFiles
    $total     = $Global:UM_TotalFiles

    Write-Output ([pscustomobject]@{
        Type    = "ScanProgress"
        Mode    = (UM-PrettyMode $Global:UM_Mode)
        File    = $file
        Elapsed = $elapsedTS
        Scanned = $scanned
        Total   = $total
    })
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
	UM-Output ("Mode             : {0}" -f (UM-PrettyMode $Global:UM_Mode))
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

	$attemptTS = [TimeSpan]::FromSeconds($Global:UM_AttemptSeconds).ToString("hh\:mm\:ss")
	$fileTS    = [TimeSpan]::FromSeconds($Global:UM_FileSeconds).ToString("hh\:mm\:ss")
	$sessionTS = [TimeSpan]::FromSeconds($Global:UM_ElapsedSeconds).ToString("hh\:mm\:ss")

    Write-Output ([pscustomobject]@{
        Type         = "RepairProgress"
        Mode         = (UM-PrettyMode $Global:UM_Mode)
        SourcePath   = $Global:UM_RepairSourcePath
        AttemptCount = $Global:UM_RepairAttemptCount
        AttemptTime  = $attemptTS
        FileTime     = $fileTS
        Elapsed      = $sessionTS
        ItemIndex    = $Global:UM_RepairItemIndex
        TotalItems   = $Global:UM_RepairTotalItems
        StageFriendly= $Global:UM_RepairStageFriendly
        CRF          = $Global:UM_RepairCRF
    })
}

Export-ModuleMember -Function *
