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

    # Base folder (Main.ps1 or UM-GUI.ps1 directory)
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

	# --------------------------------------------
	# SMART LIBRARY TYPE DETECTION
	# --------------------------------------------

	# Normalize for matching
	$rootLower = $RootPath.ToLower()

	# 1) Keyword-based detection
	$showKeywords  = @("show","shows","tv","tv show","tv shows","series","season")
	$movieKeywords = @("movie","movies","film","films")

	$libraryType = $null

	foreach ($kw in $showKeywords) {
		if ($rootLower -like "*$kw*") {
			$libraryType = "Shows"
			break
		}
	}

	if (-not $libraryType) {
		foreach ($kw in $movieKeywords) {
			if ($rootLower -like "*$kw*") {
				$libraryType = "Movies"
				break
			}
		}
	}

	# 2) Density-based detection (5+ video files in first 5 folders)
	if (-not $libraryType) {
		$videoExt = @("*.mkv","*.mp4","*.avi","*.mov","*.wmv","*.flv","*.mpeg","*.ts","*.webm")

		$subDirs = Get-ChildItem -Path $RootPath -Directory -ErrorAction SilentlyContinue | Select-Object -First 5

		$videoCount = 0
		foreach ($dir in $subDirs) {
			$videoCount += (Get-ChildItem -Path $dir.FullName -File -Include $videoExt -ErrorAction SilentlyContinue).Count
		}

		if ($videoCount -ge 5) {
			$libraryType = "Shows"
		}
	}

	# 3) Final fallback
	if (-not $libraryType) {
		$libraryType = "Movies"
	}


    # Unified log paths
    $Global:UnifiedMachineLogPath = Join-Path $logsRoot "UnifiedLog.json"
    $Global:UnifiedHumanLogPath   = Join-Path $logsRoot "HumanLog.json"

    foreach ($path in @($Global:UnifiedMachineLogPath, $Global:UnifiedHumanLogPath)) {
        if (!(Test-Path $path)) {
            "[]" | Set-Content -Path $path -Encoding UTF8
        }
    }

    # Build context
    $ctx = [UnifiedMediaContext]::new()
    $ctx.Mode                  = $Mode
    $ctx.RootPath              = $RootPath
    $ctx.LibraryType           = $libraryType
    $ctx.LogsRoot              = $logsRoot
    $ctx.RepairedRoot          = $repairedRoot
    $ctx.UnifiedHumanLogPath   = $Global:UnifiedHumanLogPath
    $ctx.UnifiedMachineLogPath = $Global:UnifiedMachineLogPath

    return $ctx
}

Export-ModuleMember -Function Initialize-UMConfig
