# =====================================================================
# Unified Media Integrity Pipeline — Localhost Server
# Serves UI + Runs Real Pipeline + Streams Live Status
# Port: 17863
# =====================================================================

if ($MyInvocation.InvocationName -ne '.') {

    # Give the server a moment to start
    Start-Sleep -Milliseconds 250

    # Check if Edge app-mode window is already running
    $edgeRunning = Get-Process msedge -ErrorAction SilentlyContinue | Where-Object {
        $_.MainWindowTitle -eq "Unified Media Integrity Pipeline"
    }

    # Launch Edge only if not already open
    if (-not $edgeRunning) {
        Start-Process "msedge.exe" "--app=http://localhost:17863/"
    }
}

$port        = 17863
$root        = Split-Path -Parent $MyInvocation.MyCommand.Path  # /web folder
$projectRoot = Split-Path $root -Parent                         # project root
$modulesPath = Join-Path $projectRoot "Modules"

# Load core orchestration (defines Start-UMPipeline-Core and $Global:UM_CurrentJob)
. (Join-Path $projectRoot "GUI-Core.ps1") $projectRoot

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$port/")
$listener.Start()

Write-Host "Server running at http://localhost:$port/"
Write-Host "Serving UI from: $root"

function Send-Json {
    param($response, $obj)
    $json = ($obj | ConvertTo-Json -Depth 6)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    $response.ContentType = "application/json"
    $response.OutputStream.Write($bytes, 0, $bytes.Length)
}

function Send-File {
    param($response, $path, $contentType)
    if (-not (Test-Path $path)) {
        $response.StatusCode = 404
        $response.OutputStream.Write(
            [System.Text.Encoding]::UTF8.GetBytes("404 Not Found"), 0, 13
        )
        return
    }
    $bytes = [System.IO.File]::ReadAllBytes($path)
    $response.ContentType = $contentType
    $response.OutputStream.Write($bytes, 0, $bytes.Length)
}

# -----------------------------
# GLOBAL STATE
# -----------------------------
$Global:UM_Status       = "idle"   # idle | running | completed | error
$Global:UM_LatestStatus = $null
$Global:UM_Job          = $null

# -----------------------------
# START PIPELINE
# -----------------------------
function Start-Pipeline {
    param($settings)

    if ($Global:UM_Job -and $Global:UM_Job.State -eq "Running") {
        return
    }

    $Global:UM_Status       = "running"
    $Global:UM_LatestStatus = $null
	$Global:UM_Mode 		= $settings.Mode

    try {
        # Start the REAL pipeline job (GUI-Core creates it)
        Start-UMPipeline-Core -Settings $settings

        # Capture the real job
        $Global:UM_Job = $Global:UM_CurrentJob

        if (-not $Global:UM_Job) {
            throw "Pipeline job did not initialize correctly."
        }
    }
    catch {
        $Global:UM_Status = "error"
        $Global:UM_LatestStatus = [pscustomobject]@{
            Type    = "Console"
            Message = "ERROR starting pipeline: $($_.Exception.Message)"
        }
    }
}

# -----------------------------
# STOP PIPELINE
# -----------------------------
function Stop-Pipeline {
    if ($Global:UM_Job) {
        try {
            if ($Global:UM_Job.State -eq "Running") {
                Stop-Job $Global:UM_Job -ErrorAction SilentlyContinue
            }
            Receive-Job $Global:UM_Job -ErrorAction SilentlyContinue | Out-Null
            Remove-Job $Global:UM_Job -ErrorAction SilentlyContinue
        } catch { }
        $Global:UM_Job = $null
    }

    # Also tell core to clean up its notion of the job
    if ($Global:UM_CurrentJob) {
        try {
            if ($Global:UM_CurrentJob.State -eq "Running") {
                Stop-Job $Global:UM_CurrentJob -ErrorAction SilentlyContinue
            }
            Receive-Job $Global:UM_CurrentJob -ErrorAction SilentlyContinue | Out-Null
            Remove-Job $Global:UM_CurrentJob -ErrorAction SilentlyContinue
        } catch { }
        $Global:UM_CurrentJob = $null
    }

    $Global:UM_Status       = "idle"
    $Global:UM_LatestStatus = $null
}

# -----------------------------
# MAIN LOOP
# -----------------------------
while ($true) {

    # Capture pipeline output
    if ($Global:UM_Job) {
        $output = $null
        try {
            $output = Receive-Job $Global:UM_Job -Keep -ErrorAction SilentlyContinue
        } catch { }

        if ($output) {
            foreach ($o in $output) {
                if ($o -is [pscustomobject]) {
                    $Global:UM_LatestStatus = $o
                }
                elseif ($o -is [string]) {
                    $Global:UM_LatestStatus = [pscustomobject]@{
                        Type    = "Console"
                        Message = $o
                    }
                }
            }
        }

        # Update status if job finished
        if ($Global:UM_Job.State -ne "Running" -and $Global:UM_Status -eq "running") {
            $Global:UM_Status = "completed"
        }
    }

    # Handle HTTP request
    $context  = $listener.GetContext()
    $request  = $context.Request
    $response = $context.Response
    $path     = $request.Url.AbsolutePath.ToLower()

    switch ($path) {

        "/"           { Send-File $response "$root\index.html" "text/html" }
        "/index.html" { Send-File $response "$root\index.html" "text/html" }
        "/style.css"  { Send-File $response "$root\style.css" "text/css" }
        "/app.js"     { Send-File $response "$root\app.js" "application/javascript" }

        # ---------------------------
        # API ENDPOINTS
        # ---------------------------

		"/start" {
			$settings = @{
				RootPath        = $request.QueryString["root"]
				RepairedPath    = $request.QueryString["repaired"]
				Mode            = $request.QueryString["mode"]
				ScanAllEpisodes = ($request.QueryString["scanAll"] -eq "true")
			}
			Start-Pipeline $settings
			$Global:UM_Job = $Global:UM_CurrentJob
			Send-Json $response @{ ok = $true }
		}

        "/cancel" {
            Stop-Pipeline
            Send-Json $response @{ ok = $true }
        }

        "/status" {
            Send-Json $response @{ status = $Global:UM_Status }
        }

		"/status-console" {
			$payload = $Global:UM_LatestStatus

			if ($payload) {
				# Inject Mode into the object
				$payload | Add-Member -NotePropertyName Mode -NotePropertyValue (UM-PrettyMode $Global:UM_Mode) -Force
			}

			Send-Json $response @{ status = $payload }
		}

        "/browse-folder" {
            Add-Type -AssemblyName System.Windows.Forms

            $owner = New-Object System.Windows.Forms.Form
            $owner.TopMost       = $true
            $owner.ShowInTaskbar = $false
            $owner.StartPosition = "CenterScreen"
            $owner.Size          = New-Object System.Drawing.Size(1,1)
            $owner.Location      = New-Object System.Drawing.Point(-2000,-2000)
            $owner.Add_Shown({ $owner.Hide() })
            $owner.Show()

            $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
            $dialog.Description       = "Select a folder"
            $dialog.ShowNewFolderButton = $true

            $result = $dialog.ShowDialog($owner)

            if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
                Send-Json $response @{ ok = $true; path = $dialog.SelectedPath }
            }
            else {
                Send-Json $response @{ ok = $false; path = "" }
            }

            $owner.Dispose()
        }

		"/logs/human" {
			try {
				# Read NDJSON from UnifiedLog.json
				$entries = UM-ReadUnifiedLog

				# Return as pretty-printable objects
				Send-Json $response @{ ok = $true; entries = $entries }
			}
			catch {
				Send-Json $response @{ ok = $false; error = $_.Exception.Message }
			}
		}

		"/logs/machine" {
			try {
				$entries = UM-ReadUnifiedLog
				Send-Json $response @{ ok = $true; entries = $entries }
			}
			catch {
				Send-Json $response @{ ok = $false; error = $_.Exception.Message }
			}
		}

		"/logs/clear" {
			try {
				if (Test-Path $Global:UnifiedMachineLogPath) {
					"[]" | Set-Content -Path $Global:UnifiedMachineLogPath -Encoding UTF8
				}

				Send-Json $response @{ ok = $true }
			}
			catch {
				Send-Json $response @{ ok = $false; error = $_.Exception.Message }
			}
		}

		"/config" {
			Send-Json $response @{
				ok = $true
				config = @{
					RootPath        = $config.RootPath
					RepairedPath    = $config.RepairedPath
					Mode            = $config.Mode
					ScanAllEpisodes = $config.ScanAllEpisodes
				}
			}
		}

        default {
            $response.StatusCode = 404
            $response.OutputStream.Write(
                [System.Text.Encoding]::UTF8.GetBytes("404 Not Found"), 0, 13
            )
        }
    }

    $response.Close()
}
