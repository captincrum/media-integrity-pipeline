# ============================================================
# FlickFix - Automated Test Suite
# Run manually:   .\Tests\Run-Tests.ps1
# Run via CI:     GitHub Actions calls this on every push
# ============================================================

$passed = 0
$failed = 0
$errors = @()

function Test-Case {
    param(
        [string]$Name,
        [scriptblock]$Test
    )
    try {
        $result = & $Test
        if ($result -eq $true) {
            Write-Host "  PASS  $Name" -ForegroundColor Green
            $script:passed++
        } else {
            Write-Host "  FAIL  $Name" -ForegroundColor Red
            $script:failed++
            $script:errors += $Name
        }
    } catch {
        Write-Host "  FAIL  $Name -- Exception: $($_.Exception.Message)" -ForegroundColor Red
        $script:failed++
        $script:errors += $Name
    }
}

# ============================================================
# Resolve module root (works both locally and in CI)
# ============================================================
$repoRoot   = Split-Path $PSScriptRoot -Parent
$moduleRoot = Join-Path $repoRoot "Modules"

# ============================================================
# SUITE 1: File Structure
# Verifies all required files exist in the repo
# ============================================================
Write-Host ""
Write-Host "Suite 1: File Structure" -ForegroundColor Cyan
Write-Host "------------------------"

$requiredFiles = @(
    "GUI-Core.ps1",
    "config.json",
    "Modules\Common.psm1",
    "Modules\Config.psm1",
    "Modules\Logging.psm1",
    "Modules\Output.psm1",
    "Modules\Quality.psm1",
    "Modules\Repair.psm1",
    "Modules\Scan.psm1",
    "Modules\SmartCompression.psm1",
    "Modules\UM-Errors.ps1",
    "web\index.html",
    "web\app.js",
    "web\style.css",
    "web\server.ps1"
)

foreach ($file in $requiredFiles) {
    $fullPath = Join-Path $repoRoot $file
    Test-Case "File exists: $file" {
        Test-Path $fullPath
    }
}

# ============================================================
# SUITE 2: Config Validation
# Verifies config.json has all required keys
# ============================================================
Write-Host ""
Write-Host "Suite 2: Config Validation" -ForegroundColor Cyan
Write-Host "---------------------------"

$configPath = Join-Path $repoRoot "config.json"
$config     = $null
if (Test-Path $configPath) {
    $config = Get-Content $configPath -Raw | ConvertFrom-Json
}

$requiredConfigKeys = @(
    "RootPath",
    "RepairedPath",
    "Mode",
    "ScanAllEpisodes",
    "AccurateMode",
    "CompressionOutputPath",
    "CrfValue",
    "Workers",
    "RunMode"
)

foreach ($key in $requiredConfigKeys) {
    Test-Case "Config has key: $key" {
        $config -ne $null -and $config.PSObject.Properties.Name -contains $key
    }
}

Test-Case "Config CrfValue is between 18 and 28" {
    $config -ne $null -and $config.CrfValue -ge 18 -and $config.CrfValue -le 28
}

Test-Case "Config Workers is at least 1" {
    $config -ne $null -and $config.Workers -ge 1
}

Test-Case "Config Mode is a valid value" {
    $validModes = @("Full", "ScanOnly", "RepairOnly", "SmartCompression")
    $config -ne $null -and $validModes -contains $config.Mode
}

# ============================================================
# SUITE 3: Module Imports
# Verifies all modules load without errors
# ============================================================
Write-Host ""
Write-Host "Suite 3: Module Imports" -ForegroundColor Cyan
Write-Host "------------------------"

$modules = @(
    "Common.psm1",
    "Output.psm1",
    "Logging.psm1"
)

foreach ($m in $modules) {
    $modPath = Join-Path $moduleRoot $m
    Test-Case "Module imports cleanly: $m" {
        try {
            Import-Module $modPath -Force -ErrorAction Stop
            $true
        } catch {
            $false
        }
    }
}

# ============================================================
# SUITE 4: UM-PrettyMode
# Verifies mode display names return correctly
# ============================================================
Write-Host ""
Write-Host "Suite 4: UM-PrettyMode" -ForegroundColor Cyan
Write-Host "-----------------------"

Import-Module (Join-Path $moduleRoot "Common.psm1") -Force

Test-Case "ScanOnly returns 'Scan Only'" {
    (UM-PrettyMode "ScanOnly") -eq "Scan Only"
}

Test-Case "RepairOnly returns 'Repair Only'" {
    (UM-PrettyMode "RepairOnly") -eq "Repair Only"
}

Test-Case "Full returns 'Full'" {
    (UM-PrettyMode "Full") -eq "Full"
}

Test-Case "Unknown mode returns the input value" {
    (UM-PrettyMode "SmartCompression") -eq "SmartCompression"
}

# ============================================================
# SUITE 5: UM-VideoExtensions
# Verifies video extension list is complete and correct
# ============================================================
Write-Host ""
Write-Host "Suite 5: UM-VideoExtensions" -ForegroundColor Cyan
Write-Host "----------------------------"

$extensions = UM-VideoExtensions

Test-Case "Returns at least 5 extensions" {
    $extensions.Count -ge 5
}

Test-Case "Contains *.mkv" {
    $extensions -contains "*.mkv"
}

Test-Case "Contains *.mp4" {
    $extensions -contains "*.mp4"
}

Test-Case "Contains *.avi" {
    $extensions -contains "*.avi"
}

# ============================================================
# SUITE 6: UM-LibraryType
# Verifies library type detection from path keywords
# ============================================================
Write-Host ""
Write-Host "Suite 6: UM-LibraryType" -ForegroundColor Cyan
Write-Host "------------------------"

Test-Case "Detects Shows from path containing 'Shows'" {
    (UM-LibraryType -RootPath "D:\Media\Shows") -eq "Shows"
}

Test-Case "Detects Shows from path containing 'TV'" {
    (UM-LibraryType -RootPath "D:\Media\TV") -eq "Shows"
}

Test-Case "Detects Movies from path containing 'Movies'" {
    (UM-LibraryType -RootPath "D:\Media\Movies") -eq "Movies"
}

Test-Case "Detects Movies from path containing 'Films'" {
    (UM-LibraryType -RootPath "D:\Media\Films") -eq "Movies"
}

# ============================================================
# SUITE 7: UM-LoadJson
# Verifies JSON loading handles edge cases cleanly
# ============================================================
Write-Host ""
Write-Host "Suite 7: UM-LoadJson" -ForegroundColor Cyan
Write-Host "---------------------"

Test-Case "Returns empty array for non-existent file" {
    $result = @(UM-LoadJson -Path "C:\does\not\exist\fake.json")
    $result.Count -eq 0
}

$tmpJson = [System.IO.Path]::GetTempFileName()
'[{"Type":"Test","Value":"Hello"}]' | Set-Content $tmpJson -Encoding UTF8
Test-Case "Loads valid JSON array correctly" {
    $result = @(UM-LoadJson -Path $tmpJson)
    $result.Count -eq 1 -and $result[0].Type -eq "Test"
}

"" | Set-Content $tmpJson -Encoding UTF8
Test-Case "Returns empty array for empty file" {
    $result = @(UM-LoadJson -Path $tmpJson)
    $result.Count -eq 0
}

Remove-Item $tmpJson -Force -ErrorAction SilentlyContinue

# ============================================================
# SUITE 8: Output Module Guards
# Verifies heartbeat functions return nothing when globals unset
# ============================================================
Write-Host ""
Write-Host "Suite 8: Output Module Guards" -ForegroundColor Cyan
Write-Host "------------------------------"

Import-Module (Join-Path $moduleRoot "Output.psm1") -Force

$Global:UM_LatestStatus        = $null
$Global:UM_RepairItemIndex     = $null
$Global:UM_RepairDoneCount     = 0
$Global:UM_RepairTotalItems    = 0
$Global:UM_RepairSessionStart  = $null
$Global:UM_WorkerFolders       = @()
$Global:UM_CompressTotalFiles2 = 0

Test-Case "UM-RepairWorkerConsole returns valid object when globals are zero" {
    $result = UM-RepairWorkerConsole
    $result -ne $null -and $result.Type -eq "RepairProgress" -and $result.ItemIndex -eq 0
}

Test-Case "UM-PhaseThreeConsole returns nothing when RepairItemIndex is null" {
    $result = UM-PhaseThreeConsole
    $result -eq $null
}

# ============================================================
# RESULTS
# ============================================================
Write-Host ""
Write-Host "=========================" -ForegroundColor White
Write-Host "  Results: $passed passed, $failed failed" -ForegroundColor $(if ($failed -eq 0) { "Green" } else { "Red" })
Write-Host "=========================" -ForegroundColor White

if ($errors.Count -gt 0) {
    Write-Host ""
    Write-Host "Failed tests:" -ForegroundColor Red
    foreach ($e in $errors) {
        Write-Host "  - $e" -ForegroundColor Red
    }
}

Write-Host ""

# Exit with error code if any tests failed (required for CI)
if ($failed -gt 0) { exit 1 } else { exit 0 }