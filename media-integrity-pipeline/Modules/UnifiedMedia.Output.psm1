# -----------------------[    Core Output Router   ]------------------------- #

function UM-Output {
    param([string]$Message)

    if ($Global:IsGUI -and $Global:AppendConsole) {
        & $Global:AppendConsole $Message
    }
    else {
        Write-Host $Message
    }
}

# -----------------------[ Console Output: Phase 1 ]------------------------- #

function UM-PhaseOneConsole {
    param($Context)

    $block = @"
Phase 1       : Preparing session data
Mode          : $(UM-PrettyMode $Context.Mode)
Library Type  : $($Context.LibraryType)
Root Path     : $($Context.RootPath)
"@

    UM-Output $block
    Start-Sleep -Milliseconds 500
}

# -----------------------[ Console Output: Phase 2 ]------------------------- #

function UM-PhaseTwoConsole {

    $elapsedTS = ((Get-Date) - $Global:UM_ScanStart).ToString("hh\:mm\:ss")

    Write-Output ([pscustomobject]@{
        Type       = "ScanProgress"
        Mode       = (UM-PrettyMode $Global:UM_Mode)
        File       = $Global:UM_ScanFile
        Elapsed    = $elapsedTS
        Scanned    = $Global:UM_ScannedCount
        Total      = $Global:UM_ScanTotal
    })
}

# -----------------------[ Console Output: Phase 3 ]------------------------- #

function UM-PhaseThreeConsole {

    $attemptTS = ((Get-Date) - $Global:UM_RepairAttemptStart).ToString("hh\:mm\:ss")
    $fileTS    = ((Get-Date) - $Global:UM_RepairFileStart).ToString("hh\:mm\:ss")
    $sessionTS = ((Get-Date) - $Global:UM_RepairSessionStart).ToString("hh\:mm\:ss")

    Write-Output ([pscustomobject]@{
        Type          = "RepairProgress"
        ItemIndex     = $Global:UM_RepairItemIndex
        TotalItems    = $Global:UM_RepairTotalItems
        StageFriendly = $Global:UM_RepairStageFriendly
        CRF           = $Global:UM_RepairCRF
        SourcePath    = $Global:UM_RepairSourcePath
        AttemptCount  = $Global:UM_RepairAttemptCount

        AttemptTime   = $attemptTS
        FileTime      = $fileTS
        Elapsed       = $sessionTS
    })
}

Export-ModuleMember -Function *
