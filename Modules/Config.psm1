class UnifiedMediaContext {
    [string]$Mode
    [string]$RootPath
    [string]$LibraryType

    [string]$LogsRoot
    [string]$RepairedRoot

    [string]$UnifiedHumanLogPath
    [string]$UnifiedMachineLogPath
    [int]$Workers
}

function Initialize-UMConfig {
    param(
        [string]$Mode,
        [string]$RootPath,
        [string]$RepairedRootOverride,
        [int]$Workers = 4
    )

    # Base folder (UM-GUI.ps1 directory)
    $base = Split-Path $PSScriptRoot -Parent

    # Logs folder
    $logsRoot = Join-Path $base "Logs"
    if (!(Test-Path $logsRoot)) {
        New-Item -ItemType Directory -Path $logsRoot -Force | Out-Null
    }

	# Pick subfolder name based on mode
    $subFolder = if ($Mode -eq "Compress") { "Compressed" } else { "Repaired" }

    # Default output folder under project root
	$repairedRoot = if ($RepairedRootOverride -and (Test-Path $RepairedRootOverride)) {
        Join-Path $RepairedRootOverride $subFolder
    } else {
        Join-Path $base $subFolder
    }

    # Create the folder now for Repair modes; Compress mode creates it per-file in Invoke-UMCompress
	if ($Mode -in @("Full", "RepairOnly") -and !(Test-Path $repairedRoot)) {
        New-Item -ItemType Directory -Path $repairedRoot -Force | Out-Null
    }

	$libraryType = UM-LibraryType -RootPath $RootPath

    # Unified log paths
    $Global:UnifiedMachineLogPath = Join-Path $logsRoot "UnifiedLog.json"

    foreach ($path in @($Global:UnifiedMachineLogPath)) {
        if (!(Test-Path $path)) {
            "" | Set-Content -Path $path -Encoding UTF8 			# Originally "[]"
        }
    }

    # Build context
    $ctx = [UnifiedMediaContext]::new()
    $ctx.Mode                  = $Mode
    $ctx.RootPath              = $RootPath
    $ctx.LibraryType           = $libraryType
    $ctx.LogsRoot              = $logsRoot
    $ctx.RepairedRoot          = $repairedRoot
    $ctx.UnifiedMachineLogPath = $Global:UnifiedMachineLogPath
    $ctx.Workers               = $Workers

    return $ctx
}

Export-ModuleMember -Function Initialize-UMConfig