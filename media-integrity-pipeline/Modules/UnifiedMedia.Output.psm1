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

    UM-Output "Phase 1      : Checking for Previous Work"
    UM-Output "Library Type : $($Context.LibraryType)"
    UM-Output "Root Path    : $($Context.RootPath)"
    UM-Output "Mode         : $($Context.Mode)"
    UM-Output ""
}

function UM-OutputScanProgress {
    param(
        [Parameter(Mandatory=$true)]$File,
        [Parameter(Mandatory=$true)]$Elapsed,
        [Parameter(Mandatory=$true)]$ScannedFiles,
        [Parameter(Mandatory=$true)]$TotalFiles
    )

    # Clear screen (GUI or CLI)
    if ($Global:IsGUI -and $Global:AppendConsole) {
        & $Global:AppendConsole "__CLEAR__"
    }
    else {
        Clear-Host
    }

    $percent = if ($TotalFiles -gt 0) {
        [math]::Round(($ScannedFiles / $TotalFiles) * 100)
    } else { 0 }

    UM-Output ("{0,-13} : {1}" -f "Phase 2",        "Scanning & Logging")
    UM-Output ("{0,-13} : {1}" -f "Scanning File",  $File.FullName)
    UM-Output ("{0,-13} : {1}" -f "Elapsed Time",   $Elapsed.ToString('hh\:mm\:ss'))
    UM-Output ("{0,-13} : {1}" -f "Scanned",        "$ScannedFiles/$TotalFiles")
    UM-Output ("{0,-13} : {1}" -f "Completion",     "$percent%")
    UM-Output ""
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

    # --- NEW: CLEAR SCREEN ---
    if ($Global:IsGUI -and $Global:AppendConsole) {
        & $Global:AppendConsole "__CLEAR__"
    }
    else {
        Clear-Host
    }

	UM-Output "----------------------------------------"; [Console]::Out.Flush()
	UM-Output "Repairing           : $SourcePath";      [Console]::Out.Flush()
	UM-Output "Repair Attempt      : $AttemptCount";    [Console]::Out.Flush()
	UM-Output "Attempt Time        : $AttemptTime";     [Console]::Out.Flush()
	UM-Output "----------------------------------------"; [Console]::Out.Flush()

}

function UM-OutputRepairProgress {
    param(
        [Parameter(Mandatory=$true)][int]$ItemIndex,
        [Parameter(Mandatory=$true)][int]$TotalItems,
        [Parameter(Mandatory=$true)][string]$FileTime,
        [Parameter(Mandatory=$true)][string]$StageFriendly,
        [Parameter(Mandatory=$true)][int]$CRF,
        [Parameter(Mandatory=$true)][string]$SessionTime
    )

	UM-Output "Repairing File      : $ItemIndex / $TotalItems"; [Console]::Out.Flush()
	UM-Output "File Time           : $FileTime";                [Console]::Out.Flush()
	UM-Output "----------------------------------------";        [Console]::Out.Flush()
	UM-Output "Repair Type         : $StageFriendly (CRF $CRF)"; [Console]::Out.Flush()
	UM-Output "Session Time        : $SessionTime";             [Console]::Out.Flush()
	UM-Output "----------------------------------------";        [Console]::Out.Flush()

}

Export-ModuleMember -Function *
