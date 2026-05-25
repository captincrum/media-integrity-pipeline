# =====================================================================
# UM-GUI-Core.ps1 - Unified Media Integrity Pipeline
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
    "Common.psm1",
    "Logging.psm1",
    "Config.psm1",
    "Scan.psm1",
    "Repair.psm1",
    "Quality.psm1",
    "Output.psm1"
    "SmartCompression.psm1"
)
foreach ($m in $modules) {
    Import-Module (Join-Path $moduleRoot $m) -Force
}

function Load-Config {
    if (Test-Path $configPath) {
        try {
            $cfg = Get-Content $configPath -Raw | ConvertFrom-Json
            if ($null -eq $cfg.AccurateMode) {
                $cfg | Add-Member -NotePropertyName AccurateMode -NotePropertyValue $false
            }
            if ($null -eq $cfg.ScanAllEpisodes) {
                $cfg | Add-Member -NotePropertyName ScanAllEpisodes -NotePropertyValue $false
            }
			if ($null -eq $cfg.CompressionOutputPath) {
                $cfg | Add-Member -NotePropertyName CompressionOutputPath -NotePropertyValue ""
            }
			if ($null -eq $cfg.CrfValue -or $cfg.CrfValue -lt 18 -or $cfg.CrfValue -gt 28) {
                $cfg | Add-Member -NotePropertyName CrfValue -NotePropertyValue 22 -Force
            }
            if ($null -eq $cfg.Workers -or $cfg.Workers -lt 1 -or $cfg.Workers -gt 8) {
                $cfg | Add-Member -NotePropertyName Workers -NotePropertyValue 4 -Force
            }
            return $cfg
        } catch {}
    }
    return [pscustomobject]@{
        RootPath              = ""
        RepairedPath          = ""
        Mode                  = "Full"
        ScanAllEpisodes       = $false
        AccurateMode          = $false
        CompressionOutputPath = ""
        Workers               = 4
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

			# Compression phase heartbeat
			if ($Global:UM_CompressTotalFiles2 -gt 0) {
				UM-CompressHeartbeatConsole
			} else {
				# Repair phase heartbeat
				UM-RepairHeartbeatConsole
			}
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
    if ($Settings.ContainsKey('ScanAllEpisodes')) { $config.ScanAllEpisodes = [bool]$Settings.ScanAllEpisodes }
    if ($Settings.ContainsKey('Workers'))         { $config.Workers         = [int]$Settings.Workers }

    # Keep Repair and Compression output paths separate
    if ($Settings.Mode -eq "Compress") {
        if ($Settings.ContainsKey('RepairedPath')) { $config.CompressionOutputPath = $Settings.RepairedPath }
    } else {
        if ($Settings.ContainsKey('Mode'))         { $config.Mode        = $Settings.Mode }
        if ($Settings.ContainsKey('RepairedPath')) { $config.RepairedPath = $Settings.RepairedPath }
    }

    # RunMode carries the actual intended mode into the job without touching the saved Mode
    $config | Add-Member -NotePropertyName RunMode -NotePropertyValue $Settings.Mode -Force

    Save-Config $config

    # Basic validation (same rules as GUI)
    if ($config.Mode -in @('Full','ScanOnly')) {
        if ([string]::IsNullOrWhiteSpace($config.RootPath) -or -not (Test-Path $config.RootPath)) {
            throw "Invalid or missing Library Root path."
        }
    }

	if ($config.Mode -notin @("ScanOnly", "SmartCompression", "Compress")) {
        if ([string]::IsNullOrWhiteSpace($config.RepairedPath)) {
            $config.RepairedPath = $PSScriptRoot
            Save-Config $config
        } elseif (-not (Test-Path $config.RepairedPath)) {
            throw "Invalid Repaired Output path."
        }
    }

    # Reset timers / phases
    $Global:UM_ElapsedSeconds = 0
    $Global:UM_FileSeconds    = 0
    $Global:UM_AttemptSeconds = 0
    $Global:UM_HeartbeatPhase = "Phase1"

    # Job: run pipeline, emit progress + console as JSON-friendly objects
    $Global:UM_CurrentJob = Start-Job -ScriptBlock {
        param($cfg, $moduleRoot, $settings)

        $modules = @(
            "Common.psm1",
            "Logging.psm1",
            "Config.psm1",
            "Scan.psm1",
            "Repair.psm1",
            "Quality.psm1",
            "Output.psm1",
			"SmartCompression.psm1"
        )
        foreach ($m in $modules) {
            Import-Module (Join-Path $moduleRoot $m) -Force
        }

        # GUI-style output router - emit console messages as structured objects
        # Override cfg with live settings values passed from UI
        if ($settings -and $settings.Workers -gt 0)                  { $cfg | Add-Member -NotePropertyName Workers         -NotePropertyValue ([int]$settings.Workers)          -Force }
        if ($settings -and $settings.RootPath)                        { $cfg | Add-Member -NotePropertyName RootPath         -NotePropertyValue $settings.RootPath                -Force }
        if ($settings -and $null -ne $settings.ScanAllEpisodes)       { $cfg | Add-Member -NotePropertyName ScanAllEpisodes -NotePropertyValue ([bool]$settings.ScanAllEpisodes) -Force }
        if ($settings -and $settings.CrfValue -gt 0)                  { $cfg | Add-Member -NotePropertyName CrfValue         -NotePropertyValue ([int]$settings.CrfValue)         -Force }

        $Global:IsGUI = $true
        $Global:AppendConsole = {
            param($msg)
            Write-Output ([pscustomobject]@{
                Type    = "Console"
                Message = $msg
            })
        }

		$repairedOverride = if ($cfg.Mode -eq "Compress") { $cfg.CompressionOutputPath } else { $cfg.RepairedPath }
        $ctx = Initialize-UMConfig -Mode $cfg.RunMode -RootPath $cfg.RootPath -RepairedRootOverride $repairedOverride -Workers ([int]$cfg.Workers)
        $ctx | Add-Member -NotePropertyName IsGUI           -NotePropertyValue $true                                              -Force
        $ctx | Add-Member -NotePropertyName ScanAllEpisodes -NotePropertyValue $cfg.ScanAllEpisodes                              -Force
        $ctx | Add-Member -NotePropertyName AccurateMode    -NotePropertyValue ([bool]$cfg.AccurateMode)                         -Force
        $ctx | Add-Member -NotePropertyName CrfValue        -NotePropertyValue ([int](if ($cfg.CrfValue) { $cfg.CrfValue } else { 22 })) -Force

        UM-LogInit

		if ($cfg.Mode -notin @("ScanOnly", "SmartCompression", "Compress")) {
            if (-not (Test-Path $ctx.RepairedRoot)) {
                New-Item -ItemType Directory -Path $ctx.RepairedRoot -Force | Out-Null
            }
        }

        $Global:Context               = $ctx
        $Global:UnifiedMachineLogPath = $ctx.UnifiedMachineLogPath

        # Phase 1 output
		Start-Sleep -Milliseconds 200

		UM-PhaseOneConsole -Context $ctx


		if ($cfg.RunMode -in @("Full","ScanOnly")) {
			$Global:UM_HeartbeatPhase = "Phase2"
			Invoke-UMScan
		}

		if ($cfg.RunMode -eq "SmartCompression") {
			$Global:UM_HeartbeatPhase = "Phase2"
			Invoke-UMSmartProbe -AccurateMode $cfg.AccurateMode
		}

		if ($cfg.RunMode -eq "Compress") {
            $Global:UM_HeartbeatPhase = "Phase3"
            $Global:UM_RepairSessionStart = Get-Date
            $Global:UM_RepairFileStart    = $null
            $Global:UM_RepairAttemptStart = $null
            Invoke-UMCompress
        }
		
		if ($cfg.RunMode -eq "Full") {
			$Global:UM_RepairSessionStart  = Get-Date
			$Global:UM_RepairFileStart     = $null
			$Global:UM_RepairAttemptStart  = $null
			$Global:UM_HeartbeatPhase = "Phase3"
			Invoke-UMRepair -Context $ctx
		}

		if ($cfg.RunMode -eq "RepairOnly") {
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
    } -ArgumentList $config, $moduleRoot, $Settings
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