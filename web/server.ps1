# -------------------------[ Server Initialization ]------------------------- #

Add-Type -Name Win32 -Namespace Console -MemberDefinition '[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);' ; [Console.Win32]::ShowWindow((Get-Process -Id $PID).MainWindowHandle, 0)

if ($MyInvocation.InvocationName -ne '.') {

    Start-Sleep -Milliseconds 250 												# Give the server a moment to start

    $edgeRunning = Get-Process msedge -ErrorAction SilentlyContinue | Where-Object {
        $_.MainWindowTitle -eq "FlickFix"
    }

    if (-not $edgeRunning) {
        Start-Process "msedge.exe" "--app=http://localhost:17863/"
    }
}

# -------------------------[ Path + Module Setup ]-------------------------- #

$port         = 17863
$root         = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot  = Split-Path $root -Parent
$modulesPath  = Join-Path $projectRoot "Modules"

. (Join-Path $projectRoot "GUI-Core.ps1") $projectRoot							# Load core orchestration (defines Start-UMPipeline-Core and $Global:UM_CurrentJob)
. (Join-Path $modulesPath "UM-Errors.ps1")

# -------------------------[ HTTP Listener Setup ]-------------------------- #

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$port/")
$listener.Start()

# -------------------------[ Response Helpers ]----------------------------- #

function Send-Json {
    param($response, $obj)

    $json  = ($obj | ConvertTo-Json -Depth 6)
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

# -------------------------[ Log Cache ]----------------------------------- #

function Update-LogCache {
    $path = $Global:UnifiedMachineLogPath
    if (-not $path -or -not (Test-Path $path)) {
        return
    }

    try {
        $fileSize = (Get-Item $path).Length
    } catch {
        return   # file busy
    }

    if ($fileSize -eq $Global:UM_LogCacheSize) {
        return
    }

    if ($fileSize -lt $Global:UM_LogCacheSize) {
        $Global:UM_LogCache.Clear()
        $Global:UM_LogCacheSize = 0
    }

    $stream = $null
    try {
        $stream = [System.IO.FileStream]::new($path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        $stream.Seek($Global:UM_LogCacheSize, [System.IO.SeekOrigin]::Begin) | Out-Null
        $newBytes = New-Object byte[] ($fileSize - $Global:UM_LogCacheSize)
        $stream.Read($newBytes, 0, $newBytes.Length) | Out-Null
    }
    catch {
        return   # file busy — try again next cycle
    }
    finally {
        if ($stream) { $stream.Close() }
    }

    $newText  = [System.Text.Encoding]::UTF8.GetString($newBytes)
    $newLines = $newText -split "`n"

    foreach ($line in $newLines) {
        $trim = $line.Trim()
        if ($trim -ne "" -and $trim -ne "[]") {
            $Global:UM_LogCache.Add($trim)
        }
    }

    $Global:UM_LogCacheSize = $fileSize
}

# -------------------------[ Global State ]--------------------------------- #

$Global:UM_Status             = "idle"
$Global:UM_LatestStatus       = $null
$Global:UM_Job                = $null

# Log cache — avoids re-reading the entire file on every request
$Global:UM_LogCache           = [System.Collections.Generic.List[string]]::new()
$Global:UM_LogCacheSize       = 0

# -------------------------[ Start Pipeline ]------------------------------- #

function Start-Pipeline {
    param($settings)

    if ($Global:UM_Job -and $Global:UM_Job.State -eq "Running") { return }

    $Global:UM_Status       = "running"
    $Global:UM_LatestStatus = $null
    $Global:UM_Mode         = $settings.Mode

    try {
        Start-UMPipeline-Core -Settings $settings
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

# -------------------------[ Stop Pipeline ]-------------------------------- #

function Stop-Pipeline {

    Get-Process -Name "ffmpeg" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

    if ($Global:UM_Job) {
        try {
            if ($Global:UM_Job.State -eq "Running") {
                Stop-Job $Global:UM_Job -ErrorAction SilentlyContinue
            }
            Receive-Job $Global:UM_Job -ErrorAction SilentlyContinue | Out-Null
            Remove-Job  $Global:UM_Job -ErrorAction SilentlyContinue
        } catch { }
        $Global:UM_Job = $null
    }

    if ($Global:UM_CurrentJob) {
        try {
            if ($Global:UM_CurrentJob.State -eq "Running") {
                Stop-Job $Global:UM_CurrentJob -ErrorAction SilentlyContinue
            }
            Receive-Job $Global:UM_CurrentJob -ErrorAction SilentlyContinue | Out-Null
            Remove-Job  $Global:UM_CurrentJob -ErrorAction SilentlyContinue
        } catch { }
        $Global:UM_CurrentJob = $null
    }

    $Global:UM_Status       = "idle"
    $Global:UM_LatestStatus = $null
}

# -------------------------[ Main Loop ]------------------------------------ #

while ($true) {

    if ($Global:UM_Job) {

        $output = $null
        try {
            $output = Receive-Job $Global:UM_Job -ErrorAction SilentlyContinue
        } catch { }

        if ($output) {
            foreach ($o in $output) {

                if ($o -is [pscustomobject]) {

                    if ($o.SessionStart) { $Global:UM_RepairSessionStart = $o.SessionStart }
                    if ($o.FileStart)    { $Global:UM_RepairFileStart    = $o.FileStart }
                    if ($o.AttemptStart) { $Global:UM_RepairAttemptStart = $o.AttemptStart }

					if ($o.Type -eq "CompressProgress") { $Global:UM_HeartbeatPhase = "Phase3" }
                    $Global:UM_LatestStatus = $o
					
					if ($o.Type -eq "CompressProgress") { 
                        $Global:UM_HeartbeatPhase = "Phase3"
                    }
                    $Global:UM_LatestStatus = $o
                }
                elseif ($o -is [string]) {
                    continue
                }
            }
        }

        if ($Global:UM_Job.State -ne "Running" -and $Global:UM_Status -eq "running") {
            $Global:UM_Status = "completed"
        }
    }

    if ($Global:UM_HeartbeatPhase -in @("Phase2","Phase3")) {
        UM-RenderHeartbeat
    }

    # -------------------------[ HTTP Request Handling ]-------------------- #

    $context  = $listener.GetContext()
    $request  = $context.Request
    $response = $context.Response
    $path     = $request.Url.AbsolutePath.ToLower()

    switch ($path) {

        "/"           { Send-File $response "$root\index.html" "text/html" }
        "/index.html" { Send-File $response "$root\index.html" "text/html" }
        "/style.css"  { Send-File $response "$root\style.css" "text/css" }
        "/app.js"     { Send-File $response "$root\app.js" "application/javascript" }
		"/favicon.ico"{ Send-File $response "$root\favicon.ico" "image/x-icon" }

        # ------------------------[ API: Buttons ]--------------------------- #

		"/start" {
			$settings = @{
				RootPath        = $request.QueryString["root"]
				RepairedPath    = $request.QueryString["repaired"]
				Mode            = $request.QueryString["mode"]
				ScanAllEpisodes = ($request.QueryString["scanAll"] -eq "true")
				Workers         = if ($request.QueryString["workers"]) { [int]$request.QueryString["workers"] } else { $config.Workers }
			}

			# ------------------[ VALIDATION: Library Root ]------------------ #
			if (-not $settings.RootPath -or -not (Test-Path $settings.RootPath)) {
				$Global:UM_Status       = "error"
				$Global:UM_LatestStatus = UM-ThrowError -Code "LibraryRootNotFound"

				Send-Json $response @{ ok = $false }
				continue
			}

			# ------------------[ VALIDATION: Repaired Output ]------------------ #
			$skipRepairedCheck = $settings.Mode -in @("ScanOnly", "SmartCompression")
			if (-not $skipRepairedCheck -and -not (Test-Path $settings.RepairedPath)) {
				$Global:UM_Status       = "error"
				$Global:UM_LatestStatus = UM-ThrowError -Code "RepairedPathNotFound"

				Send-Json $response @{ ok = $false }
				continue
			}

			# ------------------[ START PIPELINE ]------------------ #
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
                $payload | Add-Member -NotePropertyName Mode -NotePropertyValue (UM-PrettyMode $Global:UM_Mode) -Force
            }

            Send-Json $response @{ status = $payload }
        }
        
		"/status-all" {
			Update-LogCache
			$payload = $Global:UM_LatestStatus
			if ($payload) {
				$payload | Add-Member -NotePropertyName Mode -NotePropertyValue (UM-PrettyMode $Global:UM_Mode) -Force
			}
			Send-Json $response @{
				status   = $payload
				logTotal = $Global:UM_LogCache.Count
			}
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
            $dialog.Description        = "Select a folder"
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
                $entries = UM-ReadUnifiedLog
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

		"/logs/total" {
			try {
				Update-LogCache
				Send-Json $response @{ ok = $true; total = $Global:UM_LogCache.Count }
			}
			catch {
				Send-Json $response @{ ok = $false; total = 0 }
			}
		}

		"/logs/slice" {
			try {
				$start = [int]$request.QueryString["start"]
				$end   = [int]$request.QueryString["end"]

				Update-LogCache
				$total = $Global:UM_LogCache.Count

				if ($total -eq 0) {
					Send-Json $response @{ ok = $true; entries = @(); total = 0 }
					continue
				}

				if ($start -lt 0) { $start = 0 }
				if ($start -ge $total) { $start = [Math]::Max(0, $total - 1) }
				$end = [Math]::Min($end, $total)

				# Parse ONLY the requested slice from cached raw lines
				$slice = @()
				for ($i = $start; $i -lt $end; $i++) {
					try {
						$slice += $Global:UM_LogCache[$i] | ConvertFrom-Json
					} catch {}
				}

				Send-Json $response @{
					ok      = $true
					entries = $slice
					total   = $total
				}
			}
			catch {
				Send-Json $response @{ ok = $false; error = $_.Exception.Message }
			}
		}

		"/logs/search" {
			try {
				$query = $request.QueryString["q"]
				$max   = if ($request.QueryString["max"]) { [int]$request.QueryString["max"] } else { 500 }

				if (-not $query) {
					Send-Json $response @{ ok = $true; entries = @(); total = 0 }
					continue
				}

				Update-LogCache
				$total = $Global:UM_LogCache.Count
				$lowerQuery = $query.ToLower()
				$matches = @()

				foreach ($line in $Global:UM_LogCache) {
					# Match against both raw JSON (escaped \\) and unescaped version
					$lower = $line.ToLower().Replace("\\", "\")
					if ($lower.Contains($lowerQuery) -or $line.ToLower().Contains($lowerQuery)) {
						if ($matches.Count -lt $max) {
							try { $matches += $line | ConvertFrom-Json } catch {}
						}
					}
				}

				Send-Json $response @{
					ok      = $true
					entries = $matches
					total   = $total
				}
			}
			catch {
				Send-Json $response @{ ok = $false; error = $_.Exception.Message }
			}
		}
       
		"/logs/clear" {
            try {
                if (Test-Path $Global:UnifiedMachineLogPath) {
                    "" | Set-Content -Path $Global:UnifiedMachineLogPath -Encoding UTF8
                }
                $Global:UM_LogCache.Clear()
                $Global:UM_LogCacheSize = 0
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
                    RootPath              = $config.RootPath
                    RepairedPath          = $config.RepairedPath
                    Mode                  = $config.Mode
                    ScanAllEpisodes       = $config.ScanAllEpisodes
                    AccurateMode          = $config.AccurateMode
                    CompressionOutputPath = $config.CompressionOutputPath
                    CrfValue              = if ($config.CrfValue) { $config.CrfValue } else { 22 }
					Workers               = if ($config.Workers -gt 0) { $config.Workers } else { 4 }
                }
            }
        }

		"/config/save" {
            $config.RootPath        = $request.QueryString["root"]
            $config.RepairedPath    = $request.QueryString["repaired"]
            $config.Mode            = $request.QueryString["mode"]
            $config.ScanAllEpisodes = ($request.QueryString["scanAll"] -eq "true")
            $config.AccurateMode    = ($request.QueryString["accurateMode"] -eq "true")
            $config.CrfValue        = if ($request.QueryString["crfValue"]) { [int]$request.QueryString["crfValue"] } else { 22 }
            $config.Workers         = if ($request.QueryString["workers"]) { [int]$request.QueryString["workers"] } else { 2 }
            Save-Config $config
            Send-Json $response @{ ok = $true }
        }
		
		"/disk-space" {
            try {
                $drivePath = $request.QueryString["path"]
                $drive = Split-Path -Qualifier $drivePath
                $disk  = Get-PSDrive -Name $drive.TrimEnd(':') -ErrorAction Stop
                $freeMB = [math]::Round($disk.Free / 1MB, 2)
                Send-Json $response @{ ok = $true; freeMB = $freeMB }
            } catch {
                Send-Json $response @{ ok = $false; freeMB = 0 }
            }
        }

		"/compress/start" {
            try {
                $body    = New-Object System.IO.StreamReader($request.InputStream)
                $json    = $body.ReadToEnd()

                if (-not $json -or $json.Trim() -eq "") {
                    Send-Json $response @{ ok = $false; error = "Empty request body" }
                    continue
                }

                $payload = $json | ConvertFrom-Json

                if (-not $payload.paths -or $payload.paths.Count -eq 0) {
                    Send-Json $response @{ ok = $false; error = "No paths in payload" }
                    continue
                }

                $config.CompressionOutputPath = $payload.outputPath
                Save-Config $config

                $queuePath = Join-Path $logsRoot "CompressionQueue.json"
                $json | Set-Content -Path $queuePath -Encoding UTF8

			$config.CompressionOutputPath = $payload.outputPath
                $config.CrfValue              = if ($payload.crf) { [int]$payload.crf } else { 22 }
                Save-Config $config

                $settings = @{
                    RootPath        = $config.RootPath
                    RepairedPath    = $payload.outputPath
                    Mode            = "Compress"
                    ScanAllEpisodes = $config.ScanAllEpisodes
                    AccurateMode    = $config.AccurateMode
                    CrfValue        = $config.CrfValue
                    Workers         = if ($payload.workers -gt 0) { [int]$payload.workers } else { if ($config.Workers -gt 0) { $config.Workers } else { 2 } }
                }

                Start-Pipeline $settings
                $Global:UM_Job = $Global:UM_CurrentJob

                Send-Json $response @{ ok = $true }
            } catch {
                Send-Json $response @{ ok = $false; error = $_.Exception.Message }
            }
        }		

		"/compression/selections" {
            try {
                $path = Join-Path $logsRoot "CompressionSelections.json"
                if (Test-Path $path) {
                    $content = Get-Content $path -Raw -Encoding UTF8
                    $response.ContentType = "application/json"
                    $bytes = [System.Text.Encoding]::UTF8.GetBytes($content)
                    $response.OutputStream.Write($bytes, 0, $bytes.Length)
                } else {
                    Send-Json $response @{}
                }
            } catch {
                Send-Json $response @{}
            }
        }

        "/compression/selections/save" {
            try {
                $body    = New-Object System.IO.StreamReader($request.InputStream)
                $json    = $body.ReadToEnd()
                $path    = Join-Path $logsRoot "CompressionSelections.json"
                $json | Set-Content -Path $path -Encoding UTF8
                Send-Json $response @{ ok = $true }
            } catch {
                Send-Json $response @{ ok = $false; error = $_.Exception.Message }
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