function Get-UMQualityMetrics {
    param(
        [Parameter(Mandatory=$true)][string]$OriginalPath,
        [Parameter(Mandatory=$true)][string]$ComparisonPath
    )

    if (-not (Test-Path $OriginalPath)) {
        throw "Original file not found: $OriginalPath"
    }
    if (-not (Test-Path $ComparisonPath)) {
        throw "Comparison file not found: $ComparisonPath"
    }

    # Temporary file for ffmpeg output
    $tempLog = [System.IO.Path]::GetTempFileName()

    # Run SSIM + PSNR filters
    & ffmpeg -i $ComparisonPath -i $OriginalPath `
        -lavfi "ssim;[0:v][1:v]psnr" -f null - 2> $tempLog

    $log = Get-Content $tempLog -Raw
    Remove-Item $tempLog -ErrorAction SilentlyContinue

    $ssim = 0.0
    $psnr = 0.0

    # Extract SSIM
    if ($log -match "All:\s*SSIM\s*=\s*([0-9\.]+)") {
        $ssim = [double]$matches[1]
    }

    # Extract PSNR
    if ($log -match "average:\s*([0-9\.]+)\s*min") {
        $psnr = [double]$matches[1]
    }

    return [PSCustomObject]@{
        SSIM = $ssim
        PSNR = $psnr
    }
}

function Invoke-UMQualityCheck {
    param(
        [Parameter(Mandatory=$true)][string]$OriginalPath,
        [Parameter(Mandatory=$true)][string]$ComparisonPath
    )

    Write-Host ""
    Write-Host "Quality Check"
    Write-Host ("Original:   {0}" -f $OriginalPath)
    Write-Host ("Comparison: {0}" -f $ComparisonPath)

    # Compute metrics
    $metrics = Get-UMQualityMetrics -OriginalPath $OriginalPath -ComparisonPath $ComparisonPath

    # Targets
    $targetSSIM = 0.96
    $targetPSNR = 40

    # Determine pass/fail
    $status = if ($metrics.SSIM -ge $targetSSIM -and $metrics.PSNR -ge $targetPSNR) {
        "Pass"
    } else {
        "Loss"
    }

    # Percent achieved
    $percent = if ($targetSSIM -gt 0) { ($metrics.SSIM / $targetSSIM) * 100 } else { 0 }
    if ($percent -gt 100) { $percent = 100 }

    $distance = 100 - $percent

    # Log event to UnifiedLog.json
    UM-LogQuality `
        -Original $OriginalPath `
        -Comparison $ComparisonPath `
        -SSIM $metrics.SSIM `
        -PSNR $metrics.PSNR `
        -PercentAchieved ([math]::Round($percent,2)) `
        -Distance ([math]::Round($distance,2)) `
        -QualityStatus $status `
        -CheckedAt (Get-Date).ToString("s")

    Write-Host ("SSIM:       {0}" -f $metrics.SSIM)
    Write-Host ("PSNR:       {0}" -f $metrics.PSNR)
    Write-Host ("Status:     {0}" -f $status)

    return $metrics
}

Export-ModuleMember -Function Get-UMQualityMetrics, Invoke-UMQualityCheck
