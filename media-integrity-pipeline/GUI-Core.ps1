# =====================================================================
# UM-GUI-Core.ps1 — Unified Media Integrity Pipeline
# =====================================================================

param($ProjectRoot)

# Force correct script root even inside background jobs
$PSScriptRoot = $ProjectRoot
Set-Location $PSScriptRoot

$logsRoot                     = Join-Path $PSScriptRoot "Logs"
$Global:UnifiedMachineLogPath = Join-Path $logsRoot "UnifiedLog.json"
$configPath                   = Join-Path $PSScriptRoot "config.json"

$moduleRoot = Join-Path $PSScriptRoot "Modules"
$modules = @(
    "UnifiedMedia.Common.psm1",
    "UnifiedMedia.Logging.psm1",
    "UnifiedMedia.Config.psm1",
    "UnifiedMedia.Scan.psm1",
    "UnifiedMedia.Repair.psm1",
    "UnifiedMedia.Quality.psm1",
    "UnifiedMedia.Output.psm1"
)
foreach ($m in $modules) {
    Import-Module (Join-Path $moduleRoot $m) -Force
}

function Load-Config {
    if (Test-Path $configPath) {
        try {
            return Get-Content $configPath -Raw | ConvertFrom-Json
        } catch {}
    }

    return [pscustomobject]@{
        RootPath        = ""
        RepairedPath    = ""
        Mode            = "Full"
        ScanAllEpisodes = $false
    }
}

function Save-Config {
    param($cfg)
    $cfg | ConvertTo-Json -Depth 5 | Set-Content -Path $configPath -Encoding UTF8
}

$config = Load-Config

# ---------------------------[ Heartbeat ]----------------------------- #
function UM-RenderHeartbeat {
    switch ($Global:UM_HeartbeatPhase) {

        "Phase1" {
			
        }

        "Phase2" {
            $Global:UM_ElapsedSeconds++
            UM-PhaseTwoLog
        }
		
		"Phase3" {

			# Compute timers every second
			$attemptTS = if ($Global:UM_RepairAttemptStart) {
				((Get-Date) - $Global:UM_RepairAttemptStart).ToString("hh\:mm\:ss")
			} else { "00:00:00" }

			$fileTS = if ($Global:UM_RepairFileStart) {
				((Get-Date) - $Global:UM_RepairFileStart).ToString("hh\:mm\:ss")
			} else { "00:00:00" }

			$sessionTS = if ($Global:UM_RepairSessionStart) {
				((Get-Date) - $Global:UM_RepairSessionStart).ToString("hh\:mm\:ss")
			} else { "00:00:00" }

			# Emit a heartbeat RepairProgress object
			Write-Output ([pscustomobject]@{
				Type          = "RepairProgress"
				ItemIndex     = $Global:UM_LatestStatus.ItemIndex
				TotalItems    = $Global:UM_LatestStatus.TotalItems
				StageFriendly = $Global:UM_LatestStatus.StageFriendly
				CRF           = $Global:UM_LatestStatus.CRF
				SourcePath    = $Global:UM_LatestStatus.SourcePath
				AttemptCount  = $Global:UM_LatestStatus.AttemptCount

				AttemptTime   = $attemptTS
				FileTime      = $fileTS
				Elapsed       = $sessionTS
			})
		}
		
        default { }
    }
}

# ------------------------[ Core: Start pipeline ]--------------------- #
function Start-UMPipeline-Core {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Settings
    )

    if ($Global:UM_CurrentJob -and $Global:UM_CurrentJob.State -eq 'Running') {
        return
    }

    # Merge settings into config
    if ($Settings.ContainsKey('RootPath'))        { $config.RootPath        = $Settings.RootPath }
    if ($Settings.ContainsKey('RepairedPath'))    { $config.RepairedPath    = $Settings.RepairedPath }
    if ($Settings.ContainsKey('Mode'))            { $config.Mode            = $Settings.Mode }
    if ($Settings.ContainsKey('ScanAllEpisodes')) { $config.ScanAllEpisodes = [bool]$Settings.ScanAllEpisodes }

    Save-Config $config

    # Basic validation (same rules as GUI)
    if ($config.Mode -in @('Full','ScanOnly')) {
        if ([string]::IsNullOrWhiteSpace($config.RootPath) -or -not (Test-Path $config.RootPath)) {
            throw "Invalid or missing Library Root path."
        }
    }

    if ([string]::IsNullOrWhiteSpace($config.RepairedPath)) {
        $config.RepairedPath = $PSScriptRoot
        Save-Config $config
    } elseif (-not (Test-Path $config.RepairedPath)) {
        throw "Invalid Repaired Output path."
    }

    # Reset timers / phases
    $Global:UM_ElapsedSeconds = 0
    $Global:UM_FileSeconds    = 0
    $Global:UM_AttemptSeconds = 0
    $Global:UM_HeartbeatPhase = "Phase1"

    # Job: run pipeline, emit progress + console as JSON-friendly objects
    $Global:UM_CurrentJob = Start-Job -ScriptBlock {
        param($cfg, $moduleRoot)

        $modules = @(
            "UnifiedMedia.Common.psm1",
            "UnifiedMedia.Logging.psm1",
            "UnifiedMedia.Config.psm1",
            "UnifiedMedia.Scan.psm1",
            "UnifiedMedia.Repair.psm1",
            "UnifiedMedia.Quality.psm1",
            "UnifiedMedia.Output.psm1"
        )
        foreach ($m in $modules) {
            Import-Module (Join-Path $moduleRoot $m) -Force
        }

        # GUI-style output router → emit console messages as structured objects
        $Global:IsGUI = $true
        $Global:AppendConsole = {
            param($msg)
            Write-Output ([pscustomobject]@{
                Type    = "Console"
                Message = $msg
            })
        }

        $ctx = Initialize-UMConfig -Mode $cfg.Mode -RootPath $cfg.RootPath -RepairedRootOverride $cfg.RepairedPath
        $ctx | Add-Member -NotePropertyName IsGUI -NotePropertyValue $true -Force
        $ctx | Add-Member -NotePropertyName ScanAllEpisodes -NotePropertyValue $cfg.ScanAllEpisodes -Force

        UM-LogInit

        if (-not (Test-Path $ctx.RepairedRoot)) {
            New-Item -ItemType Directory -Path $ctx.RepairedRoot -Force | Out-Null
        }

        $Global:Context               = $ctx
        $Global:UnifiedMachineLogPath = $ctx.UnifiedMachineLogPath

        # Phase 1 output
		Start-Sleep -Milliseconds 200

		UM-PhaseOneConsole -Context $ctx


		if ($cfg.Mode -in @("Full","ScanOnly")) {
			$Global:UM_HeartbeatPhase = "Phase2"
			Invoke-UMScan
		}

		# If FULL mode, we must run repair AFTER scan
		if ($cfg.Mode -eq "Full") {

			# Set all repair timers BEFORE heartbeat starts Phase 3
			$Global:UM_RepairSessionStart  = Get-Date
			$Global:UM_RepairFileStart     = $null
			$Global:UM_RepairAttemptStart  = $null

			$Global:UM_HeartbeatPhase = "Phase3"

			Invoke-UMRepair -Context $ctx
		}

		# If REPAIR ONLY mode
		if ($cfg.Mode -eq "RepairOnly") {

			# Set all repair timers BEFORE heartbeat starts Phase 3
			$Global:UM_RepairSessionStart  = Get-Date
			$Global:UM_RepairFileStart     = $null
			$Global:UM_RepairAttemptStart  = $null

			$Global:UM_HeartbeatPhase = "Phase3"

			Invoke-UMRepair -Context $ctx
		}


        # Simple summary
        $totalFiles = 0
        $scanned    = 0
        try {
            $log = UM-ReadUnifiedLog
            if ($log) {
                $scanEntries = $log | Where-Object { $_.Type -eq "Scan" }
                $totalFiles  = $scanEntries.Count
                $scanned     = $scanEntries.Count
            }
        } catch {}

        # Final result object
        [PSCustomObject]@{
            Type       = "Summary"
            Context    = $ctx
            TotalFiles = $totalFiles
            Scanned    = $scanned
        }
    } -ArgumentList $config, $moduleRoot
}

# ------------------------[ Core: Stop pipeline ]---------------------- #
function Stop-UMPipeline-Core {

    if (-not $Global:UM_CurrentJob) { return }

    if ($Global:UM_CurrentJob.State -eq 'Running') {
        try {
            Stop-Job -Job $Global:UM_CurrentJob -ErrorAction SilentlyContinue
            Receive-Job -Job $Global:UM_CurrentJob -ErrorAction SilentlyContinue | Out-Null
        } catch { }
    }

    try {
        Remove-Job -Job $Global:UM_CurrentJob -ErrorAction SilentlyContinue
    } catch { }

    $Global:UM_CurrentJob = $null
    $Global:UM_HeartbeatPhase = "Idle"
}
