param(
    [string]$Mode = "Full",          # Full, ScanOnly, RepairOnly
    [string]$RootPath = $null,       # Optional override
    [string]$RepairedRoot = $null    # Optional override
)

# ---------------------------------------------------------------------
# Import modules
# ---------------------------------------------------------------------
Import-Module "$PSScriptRoot\Modules\UnifiedMedia.Common.psm1"   -Force
Import-Module "$PSScriptRoot\Modules\UnifiedMedia.Logging.psm1"  -Force
Import-Module "$PSScriptRoot\Modules\UnifiedMedia.Config.psm1"   -Force
Import-Module "$PSScriptRoot\Modules\UnifiedMedia.Scan.psm1"     -Force
Import-Module "$PSScriptRoot\Modules\UnifiedMedia.Repair.psm1"   -Force
Import-Module "$PSScriptRoot\Modules\UnifiedMedia.Quality.psm1"  -Force
Import-Module "$PSScriptRoot\Modules\UnifiedMedia.Output.psm1"   -Force

# ---------------------------------------------------------------------
# Establish working paths
# ---------------------------------------------------------------------

# If user did not provide RootPath, default to script directory
if (-not $RootPath) {
    $RootPath = Split-Path -Parent $PSScriptRoot
}

# Normalize RootPath
$RootPath = (Resolve-Path $RootPath).Path

# If user did not provide RepairedRoot, default to script directory
if (-not $RepairedRoot) {
    $RepairedRoot = Join-Path $RootPath "Repaired"
}

# Normalize RepairedRoot
$RepairedRoot = (Resolve-Path $RepairedRoot -ErrorAction SilentlyContinue) `
    ?? $RepairedRoot

# ---------------------------------------------------------------------
# Detect library type (Shows or Movies)
# ---------------------------------------------------------------------
# No prompts — purely automatic detection

if ($RootPath -match "Shows") {
    $libraryType = "Shows"
}
elseif ($RootPath -match "Movies") {
    $libraryType = "Movies"
}
else {
    UM-Output "ERROR: Could not determine library type from RootPath."
    UM-Output "RootPath for Shows must contain: 'show','shows','tv','tv show','tv shows','series','season'."
    UM-Output "RootPath for Movies must contain: 'movie','movies','film','films'."
    exit 1
}

# ---------------------------------------------------------------------
# Build Context object
# ---------------------------------------------------------------------
$Context = [PSCustomObject]@{
    RootPath     = $RootPath
    RepairedRoot = $RepairedRoot
    LibraryType  = $libraryType
    Mode         = $Mode
    IsGUI        = $false
}

# ---------------------------------------------------------------------
# Initialize logs
# ---------------------------------------------------------------------
UM-LogInit

# ---------------------------------------------------------------------
# Execute pipeline
# ---------------------------------------------------------------------

switch ($Mode.ToLower()) {

    "scanonly" {
        UM-Output "Running SCAN ONLY..."
        Invoke-UMScan -Context $Context
        break
    }

    "repaironly" {
        UM-Output "Running REPAIR ONLY..."
        Invoke-UMRepair -Context $Context
        break
    }

    "full" {
        UM-Output "Running FULL SCAN + REPAIR..."
        Invoke-UMScan   -Context $Context
        Invoke-UMRepair -Context $Context
        break
    }

    default {
        UM-Output "Unknown mode: $Mode"
        exit 1
    }
}

UM-Output "Pipeline complete."
