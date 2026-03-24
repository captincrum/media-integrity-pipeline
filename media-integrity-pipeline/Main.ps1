# ------------------------------------------------------------
# Main.ps1 — Unified Log Version (Updated)
# ------------------------------------------------------------

$WarningPreference = "SilentlyContinue"

# ------------------------------------------------------------
# Load modules
# ------------------------------------------------------------
$moduleRoot = Join-Path $PSScriptRoot "Modules"

$modules = @(
    "UnifiedMedia.Common.psm1",
    "UnifiedMedia.Logging.psm1",
    "UnifiedMedia.Config.psm1",
    "UnifiedMedia.Scan.psm1",
    "UnifiedMedia.Repair.psm1",
    "UnifiedMedia.Quality.psm1"
)

foreach ($m in $modules) {
    $path = Join-Path $moduleRoot $m
    Import-Module $path -Force
}

# ------------------------------------------------------------
# MAIN MENU LOOP
# ------------------------------------------------------------
while ($true) {

    $Mode = UM-ReadChoice `
        -Title "Unified Media Integrity Pipeline`n--------------------------------" `
        -Choices @{
            "1" = @{ Label = "Full (Scan, Repair, and Quality)"; Value = "Full" }
            "2" = @{ Label = "Scan Only";    Value = "ScanOnly" }
            "3" = @{ Label = "Repair Only";  Value = "RepairOnly" }
            "4" = @{ Label = "Quality Only"; Value = "QualityOnly" }
        }

    $RootPath = $null
    if ($Mode -in @("Full","ScanOnly")) {
        $RootPath = UM-ReadChoice `
            -Title "Enter the root folder of your Movies or Shows library.`n" `
            -FreeText `
            -Validator { param($p) Test-Path $p }
    }

    # ------------------------------------------------------------
    # Build context FIRST (sets log paths)
    # ------------------------------------------------------------
    $Global:Context = Initialize-UMConfig -Mode $Mode -RootPath $RootPath

    # ------------------------------------------------------------
    # REPAIR ONLY MODE — FIX ROOTPATH + LIBRARYTYPE
    # ------------------------------------------------------------
    if ($Mode -eq "RepairOnly" -and -not $Global:Context.RootPath) {

        $queue = UM-GetRepairQueue

        if ($queue -and $queue.Count -gt 0) {

            $firstPath = $queue[0].Path

            # Try to derive library root up to \Movies\ or \Shows\
            $libRoot = $null

            if ($firstPath -match "(.*\\Movies\\)") {
                $libRoot = ($matches[1] + "Movies")
                $Global:Context.LibraryType = "Movies"
            }
            elseif ($firstPath -match "(.*\\Shows\\)") {
                $libRoot = ($matches[1] + "Shows")
                $Global:Context.LibraryType = "Shows"
            }

            # Fallback: parent folder
            if (-not $libRoot) {
                $libRoot = Split-Path $firstPath -Parent
            }

            $Global:Context.RootPath = $libRoot
        }
    }

    # ------------------------------------------------------------
    # Initialize unified log AFTER paths exist
    # ------------------------------------------------------------
    UM-LogInit

    if ($Mode -in @("Full","ScanOnly")) {
        Write-Host "Context loaded. LibraryType = $($Global:Context.LibraryType)"
        Write-Host ""
    }

    switch ($Mode) {

        "Full" {
            Invoke-UMScan
            $result = Invoke-UMRepair -Context $Global:Context
            Write-Host "Full pipeline complete."
        }

        "ScanOnly" {
            Invoke-UMScan
            Write-Host "Scan complete."
        }

        "RepairOnly" {

            $result = Invoke-UMRepair -Context $Global:Context

            if ($result -eq "NO_REPAIR_ITEMS") {
                Write-Host ""
                Write-Host "There are no items pending repair. Try scanning a library first."
                Write-Host ""
                Write-Host "Press ENTER to return to the main menu..."
                Read-Host
                Clear-Host
                continue
            }

            Write-Host "Repair complete."
        }

        "QualityOnly" {
            Write-Host ""
            Write-Host "Quality Only Mode"
            Write-Host "Enter ORIGINAL file path:"
            $orig = Read-Host "Original"

            Write-Host "Enter REPAIRED file path:"
            $comp = Read-Host "Repaired"

            $metrics = Invoke-UMQualityCheck -OriginalPath $orig -ComparisonPath $comp

            Write-Host ""
            Write-Host "SSIM: $($metrics.SSIM)"
            Write-Host "PSNR: $($metrics.PSNR)"
        }
    }

    Write-Host ""
    Write-Host "Press ENTER to return to the main menu..."
    Read-Host
    Clear-Host
}
