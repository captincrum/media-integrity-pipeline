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
}

# -----------------------[ Console Output: Phase 2 ]------------------------- #

function UM-PhaseTwoConsole {

    $elapsedTS = ((Get-Date) - $Global:UM_ScanStart).ToString("hh\:mm\:ss")

    Write-Output ([pscustomobject]@{
        Type          = "ScanProgress"
        Mode          = (UM-PrettyMode $Global:UM_Mode)
        Elapsed       = $elapsedTS
        Scanned       = $Global:UM_ScannedCount
        Total         = $Global:UM_ScanTotal
        File          = $Global:UM_ScanFile
        WorkerFolders = $Global:UM_WorkerFolders
    })
}

# -----------------------[ Console Output: Phase 3 ]------------------------- #

function UM-PhaseThreeConsole {

    if (-not $Global:UM_RepairItemIndex) { return }

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

# -----------------------[ Console Output: Compress Heartbeat ]-------------- #

function UM-CompressHeartbeatConsole {

    $sessionTS = if ($Global:UM_CompressSessionStart) {
        ((Get-Date) - $Global:UM_CompressSessionStart).ToString("hh\:mm\:ss")
    } else { "00:00:00" }

    Write-Output ([pscustomobject]@{
        Type          = "CompressProgress"
        ItemIndex     = $Global:UM_CompressDoneCount2
        TotalItems    = $Global:UM_CompressTotalFiles2
        Elapsed       = $sessionTS
        WorkerFolders = $Global:UM_WorkerFolders
        CRF           = $Global:UM_CompressCRF
    })
}

# -----------------------[ Console Output: Repair Heartbeat ]---------------- #

function UM-RepairHeartbeatConsole {

    $s = $Global:UM_LatestStatus
    if (-not $s -or -not $s.ItemIndex) { return }

    $attemptTS = if ($Global:UM_RepairAttemptStart) {
        ((Get-Date) - $Global:UM_RepairAttemptStart).ToString("hh\:mm\:ss")
    } else { "00:00:00" }
    $fileTS = if ($Global:UM_RepairFileStart) {
        ((Get-Date) - $Global:UM_RepairFileStart).ToString("hh\:mm\:ss")
    } else { "00:00:00" }
    $sessionTS = if ($Global:UM_RepairSessionStart) {
        ((Get-Date) - $Global:UM_RepairSessionStart).ToString("hh\:mm\:ss")
    } else { "00:00:00" }

    Write-Output ([pscustomobject]@{
        Type          = "RepairProgress"
        ItemIndex     = $s.ItemIndex
        TotalItems    = $s.TotalItems
        StageFriendly = $s.StageFriendly
        CRF           = $s.CRF
        SourcePath    = $s.SourcePath
        AttemptCount  = $s.AttemptCount
        AttemptTime   = $attemptTS
        FileTime      = $fileTS
        Elapsed       = $sessionTS
    })
}

# -----------------------[ Console Output: Compress Final ]------------------ #

function UM-CompressFinalConsole {
    param([int]$TotalFiles, [double]$CRF)

    $sessionTS = if ($Global:UM_CompressSessionStart) {
        ((Get-Date) - $Global:UM_CompressSessionStart).ToString("hh\:mm\:ss")
    } else { "00:00:00" }

    Write-Output ([pscustomobject]@{
        Type          = "CompressProgress"
        ItemIndex     = $TotalFiles
        TotalItems    = $TotalFiles
        Elapsed       = $sessionTS
        WorkerFolders = @($null)
        CRF           = $CRF
    })
}

Export-ModuleMember -Function *