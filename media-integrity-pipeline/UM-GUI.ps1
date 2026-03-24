# =====================================================================
# UM-GUI.ps1 — Unified Media Integrity Pipeline GUI (Updated)
# =====================================================================

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms

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
    Import-Module (Join-Path $moduleRoot $m) -Force
}

# ------------------------------------------------------------
# Log paths in GUI runspace
# ------------------------------------------------------------
$logsRoot = Join-Path $PSScriptRoot "Logs"
$Global:UnifiedHumanLogPath   = Join-Path $logsRoot "HumanLog.json"
$Global:UnifiedMachineLogPath = Join-Path $logsRoot "UnifiedLog.json"

# ------------------------------------------------------------
# CONFIG FILE
# ------------------------------------------------------------
$configPath = Join-Path $PSScriptRoot "config.json"

function Load-Config {
    if (Test-Path $configPath) {
        try { return Get-Content $configPath -Raw | ConvertFrom-Json } catch {}
    }
    return [pscustomobject]@{
        RootPath        = ""
        RepairedPath    = ""
        Mode            = "Full"
        ScanAllEpisodes = $false
        WindowLeft      = $null
        WindowTop       = $null
        WindowWidth     = 800
        WindowHeight    = 480
    }
}

function Save-Config {
    param($cfg)
    $cfg | ConvertTo-Json -Depth 5 | Set-Content -Path $configPath -Encoding UTF8
}

$config = Load-Config

# ------------------------------------------------------------
# XAML
# ------------------------------------------------------------
$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Unified Media Integrity Pipeline"
        Height="480" Width="800"
        WindowStartupLocation="Manual"
        Background="{DynamicResource {x:Static SystemColors.WindowBrushKey}}">
    <Grid Margin="10">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <!-- SETTINGS -->
        <GroupBox Header="Settings" Grid.Row="0" Margin="0,0,0,10">
            <Grid Margin="10">
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                </Grid.RowDefinitions>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>

                <TextBlock Grid.Row="0" Grid.Column="0" Margin="0,0,10,5">Library Root:</TextBlock>
                <TextBox x:Name="txtRootPath" Grid.Row="0" Grid.Column="1" Margin="0,0,5,5"/>
                <Button x:Name="btnBrowseRoot" Grid.Row="0" Grid.Column="2" Width="80">Browse...</Button>

                <TextBlock Grid.Row="1" Grid.Column="0" Margin="0,0,10,5">Repaired Output:</TextBlock>
                <TextBox x:Name="txtRepairedPath" Grid.Row="1" Grid.Column="1" Margin="0,0,5,5"/>
                <Button x:Name="btnBrowseRepaired" Grid.Row="1" Grid.Column="2" Width="80">Browse...</Button>

                <TextBlock Grid.Row="2" Grid.Column="0" Margin="0,0,10,0">Options:</TextBlock>
                <StackPanel Grid.Row="2" Grid.Column="1" Orientation="Horizontal">
                    <CheckBox x:Name="chkScanAllEpisodes" Content="Scan all episodes (Shows only)"/>
                </StackPanel>
            </Grid>
        </GroupBox>

        <!-- MODE -->
        <GroupBox Header="Mode" Grid.Row="1" Margin="0,0,0,10">
            <StackPanel Orientation="Horizontal" Margin="10,5,10,5">
                <RadioButton x:Name="rbFull" Content="Full" Margin="0,0,15,0"/>
                <RadioButton x:Name="rbScanOnly" Content="Scan Only" Margin="0,0,15,0"/>
                <RadioButton x:Name="rbRepairOnly" Content="Repair Only" Margin="0,0,15,0"/>
                <RadioButton x:Name="rbQualityOnly" Content="Quality Only"/>
            </StackPanel>
        </GroupBox>

        <!-- STATUS -->
        <GroupBox Header="Status" Grid.Row="2" Margin="0,0,0,10">
            <Grid Margin="10">
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="*"/>
                </Grid.RowDefinitions>

                <StackPanel Orientation="Horizontal">
                    <TextBlock Text="Current Status:" Margin="0,0,5,0"/>
                    <TextBlock x:Name="txtStatus" Text="Idle"/>
                </StackPanel>

                <TextBox x:Name="txtConsole"
                         Grid.Row="1"
                         Margin="0,5,0,0"
                         IsReadOnly="True"
                         VerticalScrollBarVisibility="Auto"
                         TextWrapping="Wrap"/>
            </Grid>
        </GroupBox>

        <!-- BOTTOM BAR -->
        <DockPanel Grid.Row="3">
            <StackPanel Orientation="Horizontal" DockPanel.Dock="Left">
                <Button x:Name="btnStart" Width="100" Margin="0,0,10,0">Start</Button>
                <Button x:Name="btnCancel" Width="100" Margin="0,0,10,0" IsEnabled="False">Cancel</Button>
            </StackPanel>

            <StackPanel Orientation="Horizontal" DockPanel.Dock="Right">
                <Button x:Name="btnOpenHumanLog" Width="130" Margin="0,0,10,0">Open Human Log</Button>
                <Button x:Name="btnOpenMachineLog" Width="140">Open Machine Log</Button>
            </StackPanel>

            <ProgressBar x:Name="progressMain"
                         Height="18"
                         Margin="10,0,10,0"
                         Minimum="0" Maximum="100"
                         DockPanel.Dock="Bottom"/>
        </DockPanel>
    </Grid>
</Window>
"@

# ------------------------------------------------------------
# Build window
# ------------------------------------------------------------
$reader = New-Object System.Xml.XmlNodeReader ([xml]$xaml)
$window = [Windows.Markup.XamlReader]::Load($reader)

# ------------------------------------------------------------
# Restore window position
# ------------------------------------------------------------
if ($config.WindowLeft -ne $null -and $config.WindowTop -ne $null) {
    $screen = [System.Windows.SystemParameters]::WorkArea
    $valid = ($config.WindowLeft -ge $screen.Left -and
              $config.WindowTop -ge $screen.Top -and
              $config.WindowLeft + $config.WindowWidth -le $screen.Right -and
              $config.WindowTop + $config.WindowHeight -le $screen.Bottom)

    if ($valid) {
        $window.Left   = $config.WindowLeft
        $window.Top    = $config.WindowTop
        $window.Width  = $config.WindowWidth
        $window.Height = $config.WindowHeight
    } else {
        $window.WindowStartupLocation = "CenterScreen"
    }
} else {
    $window.WindowStartupLocation = "CenterScreen"
}

# ------------------------------------------------------------
# Grab controls
# ------------------------------------------------------------
$txtRootPath       = $window.FindName("txtRootPath")
$btnBrowseRoot     = $window.FindName("btnBrowseRoot")
$txtRepairedPath   = $window.FindName("txtRepairedPath")
$btnBrowseRepaired = $window.FindName("btnBrowseRepaired")

$chkScanAllEpisodes = $window.FindName("chkScanAllEpisodes")

$rbFull            = $window.FindName("rbFull")
$rbScanOnly        = $window.FindName("rbScanOnly")
$rbRepairOnly      = $window.FindName("rbRepairOnly")
$rbQualityOnly     = $window.FindName("rbQualityOnly")

$txtStatus         = $window.FindName("txtStatus")
$txtConsole        = $window.FindName("txtConsole")
$btnStart          = $window.FindName("btnStart")
$btnCancel         = $window.FindName("btnCancel")
$btnOpenHumanLog   = $window.FindName("btnOpenHumanLog")
$btnOpenMachineLog = $window.FindName("btnOpenMachineLog")
$progressMain      = $window.FindName("progressMain")

# ------------------------------------------------------------
# Load config into GUI
# ------------------------------------------------------------
$txtRootPath.Text     = $config.RootPath
$txtRepairedPath.Text = $config.RepairedPath

switch ($config.Mode) {
    "Full"       { $rbFull.IsChecked = $true }
    "ScanOnly"   { $rbScanOnly.IsChecked = $true }
    "RepairOnly" { $rbRepairOnly.IsChecked = $true }
    "QualityOnly"{ $rbQualityOnly.IsChecked = $true }
}

$chkScanAllEpisodes.IsChecked = $config.ScanAllEpisodes

# ------------------------------------------------------------
# Helpers
# ------------------------------------------------------------
function Append-Console { param($msg)
    $window.Dispatcher.Invoke([action]{
        $txtConsole.AppendText("$msg`r`n")
        $txtConsole.ScrollToEnd()
    })
}

function Set-Status { param($msg)
    $window.Dispatcher.Invoke([action]{ $txtStatus.Text = $msg })
}

function Set-RunningState { param($running)
    $window.Dispatcher.Invoke([action]{
        $btnStart.IsEnabled  = -not $running
        $btnCancel.IsEnabled = $running
        $progressMain.IsIndeterminate = $running
    })
}

function Show-FolderPicker {
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    if ($dlg.ShowDialog() -eq "OK") { return $dlg.SelectedPath }
    return $null
}

# ------------------------------------------------------------
# Browse buttons
# ------------------------------------------------------------
$btnBrowseRoot.Add_Click({
    $path = Show-FolderPicker
    if ($path) { $txtRootPath.Text = $path }
})

$btnBrowseRepaired.Add_Click({
    $path = Show-FolderPicker
    if ($path) { $txtRepairedPath.Text = $path }
})

# ------------------------------------------------------------
# Log buttons
# ------------------------------------------------------------
$btnOpenHumanLog.Add_Click({
    if ($Global:UnifiedHumanLogPath -and (Test-Path $Global:UnifiedHumanLogPath)) {
        Start-Process $Global:UnifiedHumanLogPath
    } else {
        [System.Windows.MessageBox]::Show("Human log not found yet.","Logs")
    }
})

$btnOpenMachineLog.Add_Click({
    if ($Global:UnifiedMachineLogPath -and (Test-Path $Global:UnifiedMachineLogPath)) {
        Start-Process $Global:UnifiedMachineLogPath
    } else {
        [System.Windows.MessageBox]::Show("Machine log not found yet.","Logs")
    }
})

# ------------------------------------------------------------
# Pipeline execution
# ------------------------------------------------------------
$script:CurrentJob  = $null
$script:JobTimer    = $null

$btnStart.Add_Click({

    # Save config immediately
    $config.RootPath        = $txtRootPath.Text
    $config.RepairedPath    = $txtRepairedPath.Text
    $config.ScanAllEpisodes = $chkScanAllEpisodes.IsChecked

    $config.Mode = if ($rbFull.IsChecked) {
        "Full"
    } elseif ($rbScanOnly.IsChecked) {
        "ScanOnly"
    } elseif ($rbRepairOnly.IsChecked) {
        "RepairOnly"
    } else {
        "QualityOnly"
    }

    Save-Config $config

    # Validate
    if ($config.Mode -in @("Full","ScanOnly")) {
        if (-not (Test-Path $config.RootPath)) {
            [System.Windows.MessageBox]::Show("Invalid library root.","Error")
            return
        }
    }
    if (-not (Test-Path $config.RepairedPath)) {
        [System.Windows.MessageBox]::Show("Invalid repaired output path.","Error")
        return
    }

    $txtConsole.Clear()
    Append-Console "Starting pipeline..."
    Set-Status "Running..."
    Set-RunningState $true

    # Start job
    $script:CurrentJob = Start-Job -ScriptBlock {
        param($cfg,$moduleRoot)

        $modules = @(
            "UnifiedMedia.Common.psm1",
            "UnifiedMedia.Logging.psm1",
            "UnifiedMedia.Config.psm1",
            "UnifiedMedia.Scan.psm1",
            "UnifiedMedia.Repair.psm1",
            "UnifiedMedia.Quality.psm1"
        )
        foreach ($m in $modules) {
            Import-Module (Join-Path $moduleRoot $m) -Force
        }

        $ctx = Initialize-UMConfig -Mode $cfg.Mode -RootPath $cfg.RootPath -RepairedRootOverride $cfg.RepairedPath

        # Mark this context as GUI-driven
        $ctx | Add-Member -NotePropertyName IsGUI -NotePropertyValue $true -Force

        # ------------------------------------------------------------
        # REPAIR ONLY MODE — FIX ROOTPATH + LIBRARYTYPE
        # ------------------------------------------------------------
        if ($cfg.Mode -eq "RepairOnly") {

            $queue = UM-GetRepairQueue

            if ($queue -and $queue.Count -gt 0) {

                $firstPath = $queue[0].Path

                # Try to derive library root up to \Movies\ or \Shows\
                $libRoot = $null

                if ($firstPath -match "(.*\\Movies\\)") {
                    $libRoot = ($matches[1] + "Movies")
                    $ctx.LibraryType = "Movies"
                }
                elseif ($firstPath -match "(.*\\Shows\\)") {
                    $libRoot = ($matches[1] + "Shows")
                    $ctx.LibraryType = "Shows"
                }

                # Fallback: parent folder
                if (-not $libRoot) {
                    $libRoot = Split-Path $firstPath -Parent
                }

                $ctx.RootPath = $libRoot
            }
        }

        UM-LogInit

        # Ensure repaired root exists
        if (-not (Test-Path $ctx.RepairedRoot)) {
            New-Item -ItemType Directory -Path $ctx.RepairedRoot -Force | Out-Null
        }

        # Update globals AFTER context is finalized
        $Global:Context = $ctx
        $Global:UnifiedHumanLogPath   = $ctx.UnifiedHumanLogPath
        $Global:UnifiedMachineLogPath = $ctx.UnifiedMachineLogPath

        $ctx | Add-Member -NotePropertyName ScanAllEpisodes -NotePropertyValue $cfg.ScanAllEpisodes -Force

        if ($cfg.Mode -in @("Full","ScanOnly")) {
            Invoke-UMScan
        }
        if ($cfg.Mode -in @("Full","RepairOnly")) {
            Invoke-UMRepair -Context $ctx | Out-Null
        }

        # Derive simple summary
        $totalFiles = 0
        $scanned    = 0
        try {
            $log = UM-ReadUnifiedLog
            if ($log) {
                $scanEntries = $log | Where-Object { $_.Type -eq "Scan" }
                $totalFiles  = $scanEntries.Count
                $scanned     = $scanEntries.Count
            }
        } catch {}

        [PSCustomObject]@{
            Context    = $ctx
            TotalFiles = $totalFiles
            Scanned    = $scanned
        }
    } -ArgumentList $config,$moduleRoot

    # Poll job state and stream output
    $script:JobTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:JobTimer.Interval = [TimeSpan]::FromSeconds(1)

    $script:JobTimer.Add_Tick({
        if (-not $script:CurrentJob) { return }

        $state = $script:CurrentJob.State

        # Stream all text output so far
        $output = Receive-Job $script:CurrentJob -Keep -ErrorAction SilentlyContinue
        if ($output) {
            $lines = $output | Where-Object { $_ -is [string] }
            $window.Dispatcher.Invoke([action]{
                $txtConsole.Clear()
                if ($lines.Count -gt 0) {
                    $txtConsole.AppendText(($lines -join "`r`n"))
                    $txtConsole.ScrollToEnd()
                }
            })
        }

        if ($state -ne "Running") {

            if ($script:JobTimer -ne $null) {
                $script:JobTimer.Stop()
            }

            # Final receive
            $result   = Receive-Job $script:CurrentJob -ErrorAction SilentlyContinue
            $jobState = $script:CurrentJob.State

            Remove-Job $script:CurrentJob -ErrorAction SilentlyContinue
            $script:CurrentJob = $null
            $script:JobTimer   = $null

            if ($result -and $result.Context) {
                $ctx = $result.Context
                $Global:UnifiedHumanLogPath   = $ctx.UnifiedHumanLogPath
                $Global:UnifiedMachineLogPath = $ctx.UnifiedMachineLogPath

                $total   = $result.TotalFiles
                $scanned = $result.Scanned
                if ($total -gt 0) {
                    $percent = [math]::Round(($scanned / $total) * 100)
                } else {
                    $percent = 0
                }

                Append-Console ""
                Append-Console "Library Scanned: $($ctx.RootPath)"
                Append-Console "Scanned: $scanned/$total"
                Append-Console "Percentage: $percent%"
                Append-Console ""
                Append-Console "Scan of $($ctx.RootPath) complete. Select the next task."
            }

            if ($jobState -eq "Completed") {
                Set-Status "Completed"
            }
            elseif ($jobState -eq "Stopped") {
                Append-Console "Pipeline cancelled."
                Set-Status "Cancelled"
            }
            else {
                Append-Console "Pipeline ended: $jobState"
                Set-Status "Ended"
            }

            Set-RunningState $false
        }
    })
    $script:JobTimer.Start()
})

$btnCancel.Add_Click({
    if ($script:CurrentJob -and $script:CurrentJob.State -eq "Running") {
        Append-Console "Cancellation requested..."
        Set-Status "Cancelling..."

        try {
            Stop-Job -Job $script:CurrentJob -ErrorAction SilentlyContinue
            Receive-Job -Job $script:CurrentJob -ErrorAction SilentlyContinue | Out-Null
            Remove-Job -Job $script:CurrentJob -ErrorAction SilentlyContinue
        } catch {
            Append-Console "Error while cancelling: $($_.Exception.Message)"
        }

        if ($script:JobTimer) {
            $script:JobTimer.Stop()
            $script:JobTimer = $null
        }

        $script:CurrentJob = $null
        Set-RunningState $false
        Set-Status "Cancelled"
    }
})

# ------------------------------------------------------------
# Save window position on close
# ------------------------------------------------------------
$window.Add_Closing({
    $config.WindowLeft   = $window.Left
    $config.WindowTop    = $window.Top
    $config.WindowWidth  = $window.Width
    $config.WindowHeight = $window.Height
    Save-Config $config
})

# ------------------------------------------------------------
# Show window
# ------------------------------------------------------------
$window.ShowDialog() | Out-Null
