# --------------------------------[   Helpers   ]---------------------------- #

function UM-LoadJson {
    param([string]$Path)

    if (Test-Path $Path) {
        $raw = Get-Content $Path -Raw
        if ($raw.Trim().Length -gt 0) {
            try {
                $data = $raw | ConvertFrom-Json
                if ($data -is [System.Collections.IEnumerable]) {
                    return $data
                } else {
                    return @($data)
                }
            }
            catch {
                Write-Host "UM-LoadJson: FAILED to parse JSON at $Path. Returning empty array."
                return @()
            }
        }
    }

    return @()
}

function UM-SaveJson {
    param(
        [string]$Path,
        [object]$Data
    )

    try {
        $dir = Split-Path $Path -Parent
        if ($dir -and -not (Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }

        $count = ($Data | Measure-Object).Count

        $json = $Data | ConvertTo-Json -Depth 6
        $json | Set-Content -Path $Path -Encoding UTF8 -ErrorAction Stop
    }
    catch {
        Write-Host "UM-SaveJson: ERROR writing to $Path"
        Write-Host "UM-SaveJson: $($_.Exception.Message)"
        throw
    }
}

function UM-PrettyMode {
    param([string]$Mode)

    switch ($Mode) {
        "ScanOnly"    { return "Scan Only" }
        "RepairOnly"  { return "Repair Only" }
        "QualityOnly" { return "Quality Only" }
        "Full"        { return "Full" }
        default       { return $Mode }
    }
}

# ----------------------------[ Media Utilities ]---------------------------- #

function UM-VideoExtensions {
    return @(
        "*.mkv", "*.mp4", "*.avi", "*.mov", "*.wmv",
        "*.flv", "*.mpeg", "*.mpg", "*.ts", "*.webm"
    )
}

function UM-LibraryType {
    param(
        [Parameter(Mandatory=$true)]
        [string]$RootPath
    )

    $rootLower = $RootPath.ToLower()

    # Keyword-based detection
    $showKeywords  = @("show","shows","tv","tv show","tv shows","series","season")
    $movieKeywords = @("movie","movies","film","films")

    foreach ($kw in $showKeywords) {
        if ($rootLower -like "*$kw*") {
            return "Shows"
        }
    }

    foreach ($kw in $movieKeywords) {
        if ($rootLower -like "*$kw*") {
            return "Movies"
        }
    }

    # Density-based detection
    $videoExt = UM-VideoExtensions

    $subDirs = Get-ChildItem -Path $RootPath -Directory -ErrorAction SilentlyContinue |
               Select-Object -First 5

    $videoCount = 0
    foreach ($dir in $subDirs) {
        $videoCount += (Get-ChildItem -Path $dir.FullName -File -Include $videoExt -ErrorAction SilentlyContinue).Count
    }

    if ($videoCount -ge 5) {
        return "Shows"
    }

    # Final fallback
    return "Movies"
}

# ------------------------------[   Utilities   ]---------------------------- #

function UM-CleanupPreviousRepairs {
    param(
        [Parameter(Mandatory=$true)][string]$Directory,
        [Parameter(Mandatory=$true)][string]$BaseName,
        [Parameter(Mandatory=$true)][string]$KeepExtension
    )

    # Build pattern: BaseName.*
    $pattern = Join-Path $Directory ($BaseName + ".*")

    # Get all matching files
    $files = Get-ChildItem -Path $pattern -File -ErrorAction SilentlyContinue

	# Delete everything EXCEPT the final successful extension
    foreach ($f in $files) {
        if ($f.Extension -ne $KeepExtension) {
            try {
                Remove-Item $f.FullName -Force
            }
            catch {
                Write-Host "UM-CleanupPreviousRepairs: Failed to delete $($f.FullName)"
            }
        }
    }
}

function UM-GetRepairedOutputPath {
    param(
        [Parameter(Mandatory=$true)][object]$Context,
        [Parameter(Mandatory=$true)][string]$SourcePath
    )
	
    $libraryType = $Context.LibraryType											# Determine library type

    $relative = $null

    if ($SourcePath -match "(?i)(.*\\Shows\\)(.+)") {
        $relative = $matches[2]
    }
	
    elseif ($SourcePath -match "(?i)(.*\\Movies\\)(.+)") {
        $relative = $matches[2]
    }
	
    elseif ($Context.RootPath -and
            $SourcePath.StartsWith($Context.RootPath, [System.StringComparison]::OrdinalIgnoreCase)) {

        $relative = $SourcePath.Substring($Context.RootPath.Length).TrimStart("\","/")
    }
	
    else {
        $relative = [System.IO.Path]::GetFileName($SourcePath)
    }

    $relativeDir = [System.IO.Path]::GetDirectoryName($relative)
    $ext         = [System.IO.Path]::GetExtension($SourcePath)
    $baseName    = [System.IO.Path]::GetFileNameWithoutExtension($SourcePath)

    $targetDirBase = Join-Path $Context.RepairedRoot $libraryType				# Build repaired root

    # Build full directory
    $targetFullDir = if ($relativeDir) {
        Join-Path $targetDirBase $relativeDir
    } else {
        $targetDirBase
    }

    # Ensure directory exists
    if (-not (Test-Path $targetFullDir)) {
        New-Item -ItemType Directory -Path $targetFullDir -Force | Out-Null
    }

    # Return all relevant paths
    return [PSCustomObject]@{
        Directory   = $targetFullDir
        BaseName    = $baseName
        SameExtPath = Join-Path $targetFullDir ($baseName + $ext)
        Mp4Path     = Join-Path $targetFullDir ($baseName + ".mp4")
        Relative    = $relative
        RelativeDir = $relativeDir
    }
}


Export-ModuleMember -Function `
    UM-LoadJson, `
    UM-SaveJson, `
    UM-CleanupPreviousRepairs, `
    UM-GetRepairedOutputPath, `
    UM-PrettyMode, `
    UM-VideoExtensions, `
    UM-LibraryType
