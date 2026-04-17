class UnifiedMediaContext {
    [string]$Mode
    [string]$RootPath
    [string]$LibraryType

    [string]$LogsRoot
    [string]$RepairedRoot

    [string]$UnifiedHumanLogPath
    [string]$UnifiedMachineLogPath
}

function Initialize-UMConfig {
    param(
        [string]$Mode,
        [string]$RootPath,
        [string]$RepairedRootOverride
    )

    # Base folder (UM-GUI.ps1 directory)
    $base = Split-Path $PSScriptRoot -Parent

    # Logs folder
    $logsRoot = Join-Path $base "Logs"
    if (!(Test-Path $logsRoot)) {
        New-Item -ItemType Directory -Path $logsRoot -Force | Out-Null
    }

	# Default repaired folder under project root
	$repairedRoot = Join-Path $base "Repaired"

	# If GUI provided a parent folder, put Repaired under it
	if ($RepairedRootOverride -and (Test-Path $RepairedRootOverride)) {
		$repairedRoot = Join-Path $RepairedRootOverride "Repaired"
	}

    # Ensure repaired folder exists
    if (!(Test-Path $repairedRoot)) {
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

    return $ctx
}

Export-ModuleMember -Function Initialize-UMConfig
