# ---------------------------------------------------------------------
# Core Output Router
# ---------------------------------------------------------------------
function UM-Output {
    param([string]$Message)

    # GUI mode: send to Append-Console
    if ($Global:IsGUI -and $Global:AppendConsole) {
        & $Global:AppendConsole $Message
    }
    else {
        # CLI fallback
        Write-Host $Message
    }
}

# ---------------------------------------------------------------------
# SCAN OUTPUT
# ---------------------------------------------------------------------

function UM-OutputScanPhase {
    param($Context)

    # Clear screen ONCE for Phase 1
    if ($Global:IsGUI -and $Global:AppendConsole) {
        & $Global:AppendConsole "__CLEAR__"
    }
    else {
        Clear-Host
    }

    UM-Output "Phase 1      : Checking Unifiedlog.json"
    UM-Output "Library Type : $($Context.LibraryType)"
    UM-Output "Root Path    : $($Context.RootPath)"
    UM-Output "Mode         : $($Context.Mode)"
    UM-Output ""

    # ⭐ Pause so Phase 1 is visible
    Start-Sleep -Milliseconds 1250
}

function UM-OutputScanProgressLive {

    # If no scan is running, do nothing
    if (-not $Global:UM_TotalFiles -or $Global:UM_TotalFiles -eq 0) {
        return
    }

    $file        = $Global:UM_CurrentScanFile
    $elapsed     = $Global:UM_CurrentScanElapsed
    $fileElapsed = $Global:UM_CurrentFileElapsed
    $scanned     = $Global:UM_ScannedFiles
    $total       = $Global:UM_TotalFiles

    $percent = if ($total -gt 0) {
        [math]::Round(($scanned / $total) * 100)
    } else { 0 }

    # Clear screen EVERY TICK for Phase 2 (live updates)
    if ($Global:IsGUI -and $Global:AppendConsole) {
        & $Global:AppendConsole "__CLEAR__"
    }
    else {
        Clear-Host
    }

    UM-Output ("{0,-13} : {1}" -f "Phase 2",        "Scanning & Logging")
    UM-Output ("{0,-13} : {1}" -f "Scanning File",  $file)
    UM-Output ("{0,-13} : {1}" -f "Elapsed Time",   $elapsed.ToString('hh\:mm\:ss'))
    UM-Output ("{0,-13} : {1}" -f "Scanned",        "$scanned/$total")
    UM-Output ("{0,-13} : {1}" -f "Completion",     "$percent%")
}

# ---------------------------------------------------------------------
# REPAIR OUTPUT
# ---------------------------------------------------------------------

function UM-OutputRepairHeader {
    param(
        [Parameter(Mandatory=$true)][string]$SourcePath,
        [Parameter(Mandatory=$true)][int]$AttemptCount,
        [Parameter(Mandatory=$true)][string]$AttemptTime
    )

    UM-Output "Phase 3          : Repairing & Logging"; 
    UM-Output "Repairing        : $SourcePath";         
    UM-Output "Repair Attempt   : $AttemptCount";       
    UM-Output "Attempt Time     : $AttemptTime";        
    UM-Output "----------------------------------------"; 
}

function UM-OutputRepairProgress {
    param(
        [Parameter(Mandatory=$true)][int]$ItemIndex,
        [Parameter(Mandatory=$true)][int]$TotalItems,
        [Parameter(Mandatory=$true)][string]$FileTime,
        [Parameter(Mandatory=$true)][string]$StageFriendly,
        [Parameter(Mandatory=$true)][int]$CRF,
        [Parameter(Mandatory=$true)][string]$SessionTime,
        [Parameter(Mandatory=$true)][string]$SourcePath,
        [Parameter(Mandatory=$true)][int]$AttemptCount,
        [Parameter(Mandatory=$true)][string]$AttemptTime
    )

    # Clear screen once per tick
    if ($Global:IsGUI -and $Global:AppendConsole) {
        & $Global:AppendConsole "__CLEAR__"
    }
    else {
        Clear-Host
    }

    # Print header
    UM-OutputRepairHeader `
        -SourcePath   $SourcePath `
        -AttemptCount $AttemptCount `
        -AttemptTime  $AttemptTime

    # Print progress
    UM-Output "Repairing File   : $ItemIndex / $TotalItems"; 
    UM-Output "File Time        : $FileTime";                
    UM-Output "----------------------------------------";        
	# NEW: Pull latest RepairAttempt from HumanLog
	$log = UM-ReadUnifiedLog
	$latestAttempt = $log |
		Where-Object { $_.Type -eq "RepairAttempt" -and $_.Path -eq $SourcePath } |
		Sort-Object Timestamp -Descending |
		Select-Object -First 1

	if ($latestAttempt) {
		$displayStage = $latestAttempt.StageFriendly
		$displayCRF   = $latestAttempt.CRF
	} else {
		# Fallback to passed-in values (should rarely be needed)
		$displayStage = $StageFriendly
		$displayCRF   = $CRF
	}
	UM-Output "Repair Type      : $displayStage (CRF $displayCRF)"
    UM-Output "Session Time     : $SessionTime";             
    UM-Output "----------------------------------------";        
}

Export-ModuleMember -Function *
