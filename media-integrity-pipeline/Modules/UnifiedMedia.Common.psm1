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

function UM-ReadChoice {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Title,

        [Parameter()]
        [hashtable]$Choices = $null,

        [string]$Default = $null,

        [switch]$Silent,

        [switch]$FreeText,   				# NEW: allows arbitrary input

        [scriptblock]$Validator = $null  	# NEW: custom validation
    )

    while ($true) {
        Clear-Host
        Write-Host $Title

        if (-not $Silent -and -not $FreeText -and $Choices) {
            foreach ($key in ($Choices.Keys | Sort-Object)) {
                $label = $Choices[$key].Label
                Write-Host "$key = $label"
            }
        }

        $input = Read-Host "Enter choice"

        # FreeText mode: return raw input if valid
        if ($FreeText) {
            if ($Validator) {
                if (& $Validator $input) {
                    return $input
                }
            } else {
                return $input
            }

            Write-Host ""
            Write-Host "Invalid selection. Try again."
            Start-Sleep -Seconds 2
            continue
        }

        # Default handling
        if ($input -eq "" -and $Default) {
            return $Choices[$Default].Value
        }

        if ($Choices.ContainsKey($input)) {
            return $Choices[$input].Value
        }

        Write-Host ""
        Write-Host "Invalid selection. Try again."
        Start-Sleep -Seconds 2
    }
}

Export-ModuleMember -Function UM-LoadJson, UM-SaveJson, UM-ReadChoice
