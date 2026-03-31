# =====================================================================
# UM-GUI.ps1 — Unified Media Integrity Pipeline GUI (Updated)
# =====================================================================
# Heartbeat timers
$Global:UM_ElapsedSeconds = 0
$Global:UM_FileSeconds    = 0
$Global:UM_AttemptSeconds = 0

$Global:UM_LastRepairItemIndex      = $null
$Global:UM_LastRepairAttemptCount   = $null

$Global:UM_HeartbeatPhase 			= "Idle"
$Global:UM_LastScanProgressCount 	= 0
$Global:UM_LastConsoleSnapshot 		= @()
$Global:LogAutoScroll = $true

$Global:UM_LogPanelOpen = $false

$Global:UM_BaseWindowWidth = $null
$Global:UM_LogPanelOpen = $false

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
    "UnifiedMedia.Quality.psm1",
    "UnifiedMedia.Output.psm1"
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
        RootPath            = ""
        RepairedPath        = ""
        Mode                = "Full"
        ScanAllEpisodes     = $false

        WindowLeft          = $null
        WindowTop           = $null
        WindowWidth         = 800
        WindowHeight        = 500

        LastMainWindowWidth = 800
        LogPanelWidth       = 450

        HumanLog            = $false
        MachineLog          = $false
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
        ResizeMode="CanResize"
        UseLayoutRounding="True"
        SizeToContent="Manual"
        Background="{DynamicResource {x:Static SystemColors.WindowBrushKey}}">
    <Grid Margin="10">
        <Grid.ColumnDefinitions>
            <ColumnDefinition Width="*"   x:Name="colMain"/>
            <ColumnDefinition Width="0"   x:Name="colSplitter"/>
            <ColumnDefinition Width="0"   x:Name="colLog"/>
        </Grid.ColumnDefinitions>
		
        <!-- MAIN CONTENT -->
        <Grid Grid.Column="0">
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="*"/>
                <RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>

            <!-- SETTINGS -->
            <GroupBox Header="Settings" Grid.Row="0" Margin="0,0,10,10">
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
            <GroupBox Header="Mode" Grid.Row="1" Margin="0,0,10,10">
                <StackPanel Orientation="Horizontal" Margin="10,5,10,5">
                    <RadioButton x:Name="rbFull" Content="Full" Margin="0,0,15,0"/>
                    <RadioButton x:Name="rbScanOnly" Content="Scan Only" Margin="0,0,15,0"/>
                    <RadioButton x:Name="rbRepairOnly" Content="Repair Only" Margin="0,0,15,0"/>
                    <RadioButton x:Name="rbQualityOnly" Content="Quality Only"/>
                </StackPanel>
            </GroupBox>

            <!-- STATUS -->
            <GroupBox Header="Status" Grid.Row="2" Margin="0,0,10,10">
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
                             TextWrapping="Wrap"
                             FontFamily="Consolas"
                             FontSize="14"/>
                </Grid>
            </GroupBox>

            <!-- BOTTOM BAR -->
            <Grid Grid.Row="3" Margin="0,10,0,0">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>

                <!-- LEFT: Start + Cancel -->
                <StackPanel Orientation="Vertical" Grid.Column="0">
                    <Button x:Name="btnStart" Width="140" Margin="0,0,0,10">Start</Button>
                    <Button x:Name="btnCancel" Width="140" IsEnabled="False">Cancel</Button>
                </StackPanel>

                <!-- RIGHT: Log Toggles -->
                <StackPanel Orientation="Vertical" Grid.Column="2" HorizontalAlignment="Right">
                    <Button x:Name="btnOpenHumanLog" Width="140" Margin="0,0,10,10">Human Log Toggle</Button>
                    <Button x:Name="btnOpenMachineLog" Width="140" Margin="0,0,10,0">Machine Log Toggle</Button>
                </StackPanel>
            </Grid>
        </Grid>

        <!-- SPLITTER -->
        <GridSplitter x:Name="colSplitterControl"
                      Grid.Column="1"
                      Width="5"
                      HorizontalAlignment="Stretch"
                      VerticalAlignment="Stretch"
                      Background="#444"
                      ShowsPreview="True"
                      Visibility="Collapsed"/>

        <!-- LOG COLUMN (2 rows: panel + button) -->
        <Grid Grid.Column="2">
            <Grid.RowDefinitions>
                <RowDefinition Height="*"/>
                <RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>

            <!-- LOG PANEL GROUP -->
            <GroupBox Header="Live Log" Grid.Row="0"
                      Margin="10,0,10,30"
                      BorderThickness="1"
                      Visibility="Collapsed"
                      x:Name="logPanelGroup">

                <Border x:Name="logPanel"
                        Background="White"
                        BorderBrush="#444"
                        BorderThickness="1"
                        Margin="10">

                    <TextBox x:Name="txtLogViewer"
                             IsReadOnly="True"
                             TextWrapping="Wrap"
                             VerticalScrollBarVisibility="Auto"
                             FontFamily="Consolas"
                             FontSize="14"
                             Background="White"
                             Foreground="Black"
                             BorderThickness="0"
                             Margin="5"/>
                </Border>
            </GroupBox>
            <!-- CLEAR LOGS BUTTON -->
            <Button x:Name="btnClearLogs"
                    Grid.Row="1"
                    Width="140"
                    Margin="0,10,10,10"
                    HorizontalAlignment="Right"
                    Visibility="Collapsed">
                Clear All Logs
            </Button>
        </Grid>
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
        $window.Width = $config.LastMainWindowWidth
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

$logPanel     = $window.FindName("logPanel")
$txtLogViewer = $window.FindName("txtLogViewer")
$btnClearLogs = $window.FindName("btnClearLogs")
$logPanelGroup = $window.FindName("logPanelGroup")

$Global:LogAutoScroll = $true

$colMain     = $window.FindName("colMain")
$colSplitter = $window.FindName("colSplitter")
$colLog      = $window.FindName("colLog")
$colSplitterControl = $window.FindName("colSplitterControl")

# --- FORCE CLEAN STARTUP STATE ---
$colLog.Width = New-Object System.Windows.GridLength(0)
$colSplitter.Width = New-Object System.Windows.GridLength(0)
$logPanelGroup.Visibility = "Collapsed"
$colSplitterControl.Visibility = "Collapsed"

$txtLogViewer.Add_Loaded({
    try {
        $Global:LogScrollViewer = Get-ScrollViewer $txtLogViewer

        if ($Global:LogScrollViewer) {
            $Global:LogScrollViewer.Add_ScrollChanged({
                $sv = $Global:LogScrollViewer

                # User scrolled up → disable autoscroll
                if ($sv.VerticalOffset -lt ($sv.ExtentHeight - $sv.ViewportHeight)) {
                    $Global:LogAutoScroll = $false
                }
                else {
                    # User returned to bottom → enable autoscroll
                    $Global:LogAutoScroll = $true
                }
            })
        }
    }
    catch {
        # Fail silently — control may not be ready yet
    }
})

# When the window is resized, expand/contract the log panel
$window.Add_SizeChanged({
    if ($Global:UM_LogPanelOpen -and $Global:UM_BaseWindowWidth) {

        $extra = $window.Width - $Global:UM_BaseWindowWidth

        if ($extra -gt 0) {
            $colLog.Width = New-Object System.Windows.GridLength($extra)
        }
        else {
            $colLog.Width = New-Object System.Windows.GridLength(0)
        }
    }
})

# Save width when user drags the splitter
$colSplitterControl.Add_DragCompleted({
    $config.LogPanelWidth = $colLog.Width.Value
    Save-Config $config
})

$chkScanAllEpisodes.IsChecked = $config.ScanAllEpisodes

# ------------------------------------------------------------
# Helpers
# ------------------------------------------------------------
function Append-Console { param($msg)
    $window.Dispatcher.Invoke([action]{
        if ($msg -eq "__CLEAR__") {
            $txtConsole.Clear()
            return
        }

        $txtConsole.AppendText("$msg`r`n")
		
		# Track last known console state for heartbeat redraw
		$Global:UM_LastConsoleSnapshot += $msg

        $txtConsole.ScrollToEnd()
    })
}

function Set-Status { param($msg)
    $window.Dispatcher.Invoke([action]{ $txtStatus.Text = $msg })
}

function Set-RunningState { param($running)
    
	$window.Dispatcher.Invoke([action]{

        # Core pipeline controls
        $btnStart.IsEnabled  = -not $running
        $btnCancel.IsEnabled = $running

        # Disable all settings while running
        $txtRootPath.IsEnabled       = -not $running
        $btnBrowseRoot.IsEnabled     = -not $running
        $txtRepairedPath.IsEnabled   = -not $running
        $btnBrowseRepaired.IsEnabled = -not $running
        $chkScanAllEpisodes.IsEnabled = -not $running
		$btnClearLogs.IsEnabled = -not $running

        # Disable mode selection
        $rbFull.IsEnabled        = -not $running
        $rbScanOnly.IsEnabled    = -not $running
        $rbRepairOnly.IsEnabled  = -not $running
        $rbQualityOnly.IsEnabled = -not $running
    })
}

function Show-FolderPicker {
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    if ($dlg.ShowDialog() -eq "OK") { return $dlg.SelectedPath }
    return $null
}

function UM-RenderHeartbeat {

    switch ($Global:UM_HeartbeatPhase) {

        "Phase1" {
			# Phase 1 is printed by the job, not the heartbeat
        }

        "Phase2" {
            UM-OutputScanProgressLive
        }

        "Phase3" {
            UM-OutputRepairProgressLive
        }

        default {
            # Idle → print nothing
        }
    }
}

function Show-LogPanel {
    param($path)

    $content = if (Test-Path $path) {
        Get-Content $path -Raw
    } else {
        "No log available yet. Run a mode to generate output."
    }

    $window.Dispatcher.Invoke([action]{

        # Determine width to use
        $logWidth = if ($config.LogPanelWidth -gt 0) {
            $config.LogPanelWidth
        } else {
            $Global:UM_DefaultLogWidth
        }

        # If the log panel is NOT open, expand the window
        if (-not $Global:UM_LogPanelOpen) {

            # Capture baseline BEFORE expanding
            $Global:UM_BaseWindowWidth = $window.Width
            $Global:UM_LogPanelOpen = $true

            # Expand window outward
            $window.Width += $logWidth

            # Show the log column
            $colSplitter.Width = New-Object System.Windows.GridLength(5)
            $colLog.Width      = New-Object System.Windows.GridLength($logWidth)

            # Make UI visible
            $colSplitterControl.Visibility = "Visible"
            $logPanelGroup.Visibility = "Visible"
            $btnClearLogs.Visibility = "Visible"
        }

        # Load content (always)
        $txtLogViewer.Text = $content

        # Preserve tag
        $txtLogViewer.Tag = $txtLogViewer.Tag
    })
}

function Hide-LogPanel {
    $window.Dispatcher.Invoke([action]{

        # Shrink window back
        $window.Width -= $colLog.Width.Value

		# Save ONLY the main window width (not including log panel)
		$config.LastMainWindowWidth = $window.Width
		$config.WindowWidth = $window.Width
		Save-Config $config


        # Save log panel width
        if ($colLog.Width.Value -gt 0) {
            $config.LogPanelWidth = $colLog.Width.Value
            Save-Config $config
        }

        # Reset baseline tracking
        $Global:UM_BaseWindowWidth = $null
        $Global:UM_LogPanelOpen = $false

        # Collapse the log column
        $colSplitter.Width = New-Object System.Windows.GridLength(0)
        $colLog.Width      = New-Object System.Windows.GridLength(0)

        $colSplitterControl.Visibility = "Collapsed"
        $logPanelGroup.Visibility = "Collapsed"
        $btnClearLogs.Visibility = "Collapsed"

        $txtLogViewer.Tag = $null
    })
}

function Refresh-LogViewer {
    if ($logPanelGroup.Visibility -ne "Visible") { return }

    $path = if ($txtLogViewer.Tag -eq "Human") {
        $Global:UnifiedHumanLogPath
    } else {
        $Global:UnifiedMachineLogPath
    }

    if (-not (Test-Path $path)) { return }

    $window.Dispatcher.Invoke([action]{
        $txtLogViewer.Text = Get-Content $path -Raw

        if ($Global:LogAutoScroll) {
            $txtLogViewer.ScrollToEnd()
        }
    })
}

function Get-ScrollViewer {
    param($control)

    if (-not $control) { return $null }

    $childCount = [System.Windows.Media.VisualTreeHelper]::GetChildrenCount($control)
    if ($childCount -lt 1) { return $null }

    $border = [System.Windows.Media.VisualTreeHelper]::GetChild($control, 0)
    if (-not $border) { return $null }

    $childCount2 = [System.Windows.Media.VisualTreeHelper]::GetChildrenCount($border)
    if ($childCount2 -lt 1) { return $null }

    return [System.Windows.Media.VisualTreeHelper]::GetChild($border, 0)
}

function Set-LogButtonState {
    param(
        [string]$active  # "Human", "Machine", or "None"
    )

    # Default styles
    $defaultBg = [System.Windows.Media.Brushes]::LightGray
    $defaultFg = [System.Windows.Media.Brushes]::Black

    # Active styles
    $activeBg  = [System.Windows.Media.Brushes]::DimGray
    $activeFg  = [System.Windows.Media.Brushes]::White

    switch ($active) {
        "Human" {
            $btnOpenHumanLog.Background = $activeBg
            $btnOpenHumanLog.Foreground = $activeFg

            $btnOpenMachineLog.Background = $defaultBg
            $btnOpenMachineLog.Foreground = $defaultFg
        }
        "Machine" {
            $btnOpenMachineLog.Background = $activeBg
            $btnOpenMachineLog.Foreground = $activeFg

            $btnOpenHumanLog.Background = $defaultBg
            $btnOpenHumanLog.Foreground = $defaultFg
        }
        default {
            # No log open
            $btnOpenHumanLog.Background = $defaultBg
            $btnOpenHumanLog.Foreground = $defaultFg

            $btnOpenMachineLog.Background = $defaultBg
            $btnOpenMachineLog.Foreground = $defaultFg
        }
    }
}

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

# --- AUTO-OPEN LOG PANEL BASED ON CONFIG ---
if ($config.HumanLog -eq $true) {
    $txtLogViewer.Tag = "Human"
    Show-LogPanel $Global:UnifiedHumanLogPath
    Set-LogButtonState "Human"
}
elseif ($config.MachineLog -eq $true) {
    $txtLogViewer.Tag = "Machine"
    Show-LogPanel $Global:UnifiedMachineLogPath
    Set-LogButtonState "Machine"
}
else {
    Set-LogButtonState "None"
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
    if ($logPanelGroup.Visibility -eq "Visible" -and $txtLogViewer.Tag -eq "Human") {
        $config.HumanLog = $false
        $config.MachineLog = $false
        Save-Config $config
        Hide-LogPanel
        Set-LogButtonState "None"
        return
    }

    $txtLogViewer.Tag = "Human"
    $config.HumanLog = $true
    $config.MachineLog = $false
    Save-Config $config

    Show-LogPanel $Global:UnifiedHumanLogPath
    Set-LogButtonState "Human"
})

$btnOpenMachineLog.Add_Click({
    if ($logPanelGroup.Visibility -eq "Visible" -and $txtLogViewer.Tag -eq "Machine") {
        $config.HumanLog = $false
        $config.MachineLog = $false
        Save-Config $config
        Hide-LogPanel
        Set-LogButtonState "None"
        return
    }

    $txtLogViewer.Tag = "Machine"
    $config.HumanLog = $false
    $config.MachineLog = $true
    Save-Config $config

    Show-LogPanel $Global:UnifiedMachineLogPath
    Set-LogButtonState "Machine"
})

$btnClearLogs.Add_Click({
    $msg = "This action will permanently delete the log files.`n" +
           "This cannot be undone and may require a full library rescan.`n`n" +
           "Do you want to continue?"

    $result = [System.Windows.MessageBox]::Show($msg, "Confirm Delete", "YesNo", "Warning")

    if ($result -eq "Yes") {
        try {
            if (Test-Path $Global:UnifiedHumanLogPath) { Remove-Item $Global:UnifiedHumanLogPath -Force }
            if (Test-Path $Global:UnifiedMachineLogPath) { Remove-Item $Global:UnifiedMachineLogPath -Force }

            $txtLogViewer.Text = "Logs cleared."
        }
        catch {
            [System.Windows.MessageBox]::Show("Failed to delete logs: $($_.Exception.Message)", "Error")
        }
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

	if ($config.Mode -in @("Full","ScanOnly")) {

		if ([string]::IsNullOrWhiteSpace($config.RootPath)) {
			[System.Windows.MessageBox]::Show("Please select a Library Root path.","Error")
			return
		}

		if (-not (Test-Path $config.RootPath)) {
			[System.Windows.MessageBox]::Show("Invalid Library Root path.","Error")
			return
		}
	}

	# Allow empty repaired path → default to project root
	if ([string]::IsNullOrWhiteSpace($config.RepairedPath)) {
		$config.RepairedPath = $PSScriptRoot
		Save-Config $config
	}
	elseif (-not (Test-Path $config.RepairedPath)) {
		[System.Windows.MessageBox]::Show("Invalid Repaired Output path.","Error")
		return
	}



    $txtConsole.Clear()
    Set-Status "Running..."
    Set-RunningState $true
	
	# ------------------------------------------------------------
	# 1. Set Phase1 BEFORE printing anything
	# ------------------------------------------------------------
	$Global:UM_HeartbeatPhase = "Phase1"

	# ------------------------------------------------------------
	# 2. Reset timers BEFORE printing Phase1
	# ------------------------------------------------------------
	$Global:UM_ElapsedSeconds = 0
	$Global:UM_FileSeconds    = 0
	$Global:UM_AttemptSeconds = 0

	# ------------------------------------------------------------
	# 3. Initialize GUI Output Router BEFORE printing Phase1
	# ------------------------------------------------------------
	$Global:IsGUI = $true
	$Global:AppendConsole = { param($msg) Append-Console $msg }

	# ------------------------------------------------------------
	# 4. Reset Phase 2 tracking BEFORE printing Phase1
	# ------------------------------------------------------------
	$Global:UM_LastScanProgressCount = 0

	# ------------------------------------------------------------
	# 5. Print Phase 1 in GUI thread (NOW it will stay visible)
	# ------------------------------------------------------------
	UM-OutputPhaseOne $config

    # ------------------------------------------------------------
    # If starting in Repair Only, pre-seed Phase 3 from UnifiedLog
    # so the console shows resume info immediately
    # ------------------------------------------------------------
    if ($config.Mode -eq "RepairOnly") {

        try {
            # We can call these directly; modules are already imported in GUI runspace
            $queue = @(UM-GetRepairQueue)
            if ($queue.Count -gt 0) {

                $firstItem = $queue[0]
                $sourcePath = $firstItem.Path

                $log = UM-ReadUnifiedLog

                $attempts = $log | Where-Object {
                    $_.Type -eq "RepairAttempt" -and $_.Path -eq $sourcePath
                }

                if ($attempts.Count -gt 0) {
                    $lastAttempt = $attempts |
                        Sort-Object Timestamp -Descending |
                        Select-Object -First 1

                    # Map StageFriendly back to internal friendly name (already stored)
                    $stageFriendly = $lastAttempt.StageFriendly
                    $crf           = [int]$lastAttempt.CRF
                    $attemptCount  = $attempts.Count

                    # Seed globals for Phase 3 heartbeat
                    $Global:UM_RepairItemIndex     = 1
                    $Global:UM_RepairTotalItems    = $queue.Count
                    $Global:UM_RepairStageFriendly = $stageFriendly
                    $Global:UM_RepairCRF           = $crf
                    $Global:UM_RepairSourcePath    = $sourcePath
                    $Global:UM_RepairAttemptCount  = $attemptCount

                    # Switch heartbeat to Phase 3 and reset timers
                    $Global:UM_HeartbeatPhase = "Phase3"
                    $Global:UM_ElapsedSeconds = 0
                    $Global:UM_FileSeconds    = 0
                    $Global:UM_AttemptSeconds = 0

                    # Force an immediate render so console isn't blank
                    Append-Console "__CLEAR__"
                    UM-OutputRepairProgressLive
                }
            }
        } catch {
            # Fail silently; worst case we fall back to normal behavior
        }
    }


    # Start job
    $script:CurrentJob = Start-Job -ScriptBlock {
        param($cfg,$moduleRoot)

        #
        # ⭐ Load ALL modules first — Phase 1 must come AFTER this
        #
        $modules = @(
            "UnifiedMedia.Common.psm1",
            "UnifiedMedia.Logging.psm1",
            "UnifiedMedia.Config.psm1",
            "UnifiedMedia.Scan.psm1",
            "UnifiedMedia.Repair.psm1",
            "UnifiedMedia.Quality.psm1",
            "UnifiedMedia.Output.psm1"
        )
        foreach ($m in $modules) {
            Import-Module (Join-Path $moduleRoot $m) -Force
        }

        # GUI output router inside job
        $Global:IsGUI = $true
        $Global:AppendConsole = { param($msg) Write-Output $msg }

        $ctx = Initialize-UMConfig -Mode $cfg.Mode -RootPath $cfg.RootPath -RepairedRootOverride $cfg.RepairedPath
        $ctx | Add-Member -NotePropertyName IsGUI -NotePropertyValue $true -Force

        UM-LogInit

        if (-not (Test-Path $ctx.RepairedRoot)) {
            New-Item -ItemType Directory -Path $ctx.RepairedRoot -Force | Out-Null
        }

        $Global:Context = $ctx
        $Global:UnifiedHumanLogPath   = $ctx.UnifiedHumanLogPath
        $Global:UnifiedMachineLogPath = $ctx.UnifiedMachineLogPath

        $ctx | Add-Member -NotePropertyName ScanAllEpisodes -NotePropertyValue $cfg.ScanAllEpisodes -Force

		if ($cfg.Mode -in @("Full","ScanOnly")) {
			Invoke-UMScan
		}
        if ($cfg.Mode -in @("Full","RepairOnly")) {
            Invoke-UMRepair -Context $ctx
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


    # ------------------------------------------------------------
    # Fresh timer for each run
    # ------------------------------------------------------------
    if ($script:JobTimer) {
        $script:JobTimer.Stop()
        $script:JobTimer = $null
    }

    $script:JobTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:JobTimer.Interval = [TimeSpan]::FromSeconds(1)

	$script:JobTimer.Add_Tick({


		if (-not $script:CurrentJob) { return }

		$state  = $script:CurrentJob.State
		$output = Receive-Job $script:CurrentJob -Keep -ErrorAction SilentlyContinue

		# Phase 2: ScanProgress objects
		$progressObjects = $output | Where-Object {
			$_ -is [pscustomobject] -and $_.Type -eq "ScanProgress"
		}

		# Phase 3: RepairProgress objects
		$repairObjects = $output | Where-Object {
			$_ -is [pscustomobject] -and $_.Type -eq "RepairProgress"
		}

		#
		# Handle Phase 3 first (if any repair progress exists)
		#
		if ($repairObjects.Count -gt 0) {
			$r = $repairObjects[-1]

			$Global:UM_RepairItemIndex     = [int]$r.ItemIndex
			$Global:UM_RepairTotalItems    = [int]$r.TotalItems
			$Global:UM_RepairStageFriendly = $r.StageFriendly
			$Global:UM_RepairCRF           = [int]$r.CRF
			$Global:UM_RepairSourcePath    = $r.SourcePath
			$Global:UM_RepairAttemptCount  = [int]$r.AttemptCount

			# --- NEW: detect file/attempt changes in GUI runspace ---
			$isNewFile    = ($Global:UM_LastRepairItemIndex    -ne $Global:UM_RepairItemIndex)
			$isNewAttempt = ($Global:UM_LastRepairAttemptCount -ne $Global:UM_RepairAttemptCount)

			if ($isNewFile) {
				# New file → reset file + attempt timers
				$Global:UM_FileSeconds    = 0
				$Global:UM_AttemptSeconds = 0
			}
			elseif ($isNewAttempt) {
				# Same file, new attempt → reset attempt timer only
				$Global:UM_AttemptSeconds = 0
			}

			$Global:UM_LastRepairItemIndex    = $Global:UM_RepairItemIndex
			$Global:UM_LastRepairAttemptCount = $Global:UM_RepairAttemptCount
			# --- END NEW ---

			if ($Global:UM_HeartbeatPhase -ne "Phase3") {
				$Global:UM_HeartbeatPhase = "Phase3"
				$Global:UM_ElapsedSeconds = 0
				$Global:UM_FileSeconds    = 0
				$Global:UM_AttemptSeconds = 0
			}
		}


		#
		# Phase 2: detect NEW ScanProgress
		#
		$currentCount    = $progressObjects.Count
		$newScanProgress = ($currentCount -gt $Global:UM_LastScanProgressCount)
		$Global:UM_LastScanProgressCount = $currentCount

		if ($newScanProgress -and $Global:UM_HeartbeatPhase -ne "Phase3") {
			$o = $progressObjects[-1]

			$Global:UM_CurrentScanFile    = $o.File
			$Global:UM_CurrentScanElapsed = $o.Elapsed
			$Global:UM_ScannedFiles       = [int]$o.Scanned
			$Global:UM_TotalFiles         = [int]$o.Total

			$Global:UM_HeartbeatPhase = "Phase2"
		}

		#
		# Ignore all job-emitted strings and info records here
		#
		if ($output) {
			foreach ($o in $output) {
				if ($o -is [pscustomobject] -and $o.Type -eq "ScanProgress")  { continue }
				if ($o -is [pscustomobject] -and $o.Type -eq "RepairProgress") { continue }
				if ($o -is [string])                                           { continue }
				if ($o -is [System.Management.Automation.InformationRecord])   { continue }
			}
		}

		#
		# Job finished?
		#
		if ($state -ne "Running") {

			$script:JobTimer.Stop()
			$script:JobTimer = $null

			$result   = Receive-Job $script:CurrentJob -ErrorAction SilentlyContinue
			$jobState = $script:CurrentJob.State

			Remove-Job $script:CurrentJob -ErrorAction SilentlyContinue
			$script:CurrentJob = $null

			if ($result -is [array]) { $result = $result[-1] }

			$rootPath = $result.Context.RootPath

			if ($Global:UM_HeartbeatPhase -eq "Phase2") {
				Append-Console "__CLEAR__"
				UM-OutputScanProgressLive
				Append-Console ""
				Append-Console "Scan of $rootPath complete. Select the next task."
			}

			if ($Global:UM_HeartbeatTimer) {
				$Global:UM_HeartbeatTimer.Stop()
			}

			Set-Status "Completed"
			Set-RunningState $false

			$Global:UM_ElapsedSeconds = 0
			$Global:UM_FileSeconds    = 0
			$Global:UM_AttemptSeconds = 0

			return
		}
	})

    $script:JobTimer.Start()
	# Restart global heartbeat for new run
	$Global:UM_HeartbeatTimer.Start()

})

# ------------------------------------------------------------
# Cancel button
# ------------------------------------------------------------
$btnCancel.Add_Click({
    if ($script:CurrentJob -and $script:CurrentJob.State -eq "Running") {
        Append-Console ""
        Append-Console "Cancellation requested..."
        Set-Status "Cancelling..."

        try {
            Stop-Job -Job $script:CurrentJob -ErrorAction SilentlyContinue
            Receive-Job -Job $script:CurrentJob -ErrorAction SilentlyContinue | Out-Null
            Remove-Job -Job $script:CurrentJob -ErrorAction SilentlyContinue
        } catch {
            Append-Console "Error while cancelling: $($_.Exception.Message)"
        }

        # ⭐ STOP HEARTBEAT SO TIMERS FREEZE
        if ($Global:UM_HeartbeatTimer) {
            $Global:UM_HeartbeatTimer.Stop()
        }

        # ⭐ SET PHASE TO IDLE SO NOTHING REDRAWS
        $Global:UM_HeartbeatPhase = "Idle"

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
	$config.LogPanelWidth = $colLog.Width.Value
    Save-Config $config
})

# ------------------------------------------------------------
# GLOBAL ALWAYS-ON HEARTBEAT TIMER
# ------------------------------------------------------------
$Global:UM_ElapsedSeconds = 0

$Global:UM_HeartbeatTimer = New-Object System.Windows.Threading.DispatcherTimer
$Global:UM_HeartbeatTimer.Interval = [TimeSpan]::FromSeconds(1)

$Global:UM_HeartbeatTimer.Add_Tick({

    # Increment timers
    $Global:UM_ElapsedSeconds++
    $Global:UM_FileSeconds++
    $Global:UM_AttemptSeconds++

	if ($Global:UM_HeartbeatPhase -ne "Phase1","Phase2") {
		Append-Console "__CLEAR__"
	}

	UM-RenderHeartbeat
	Refresh-LogViewer

})

$Global:UM_HeartbeatTimer.Start()

# ------------------------------------------------------------
# Show window
# ------------------------------------------------------------
$window.ShowDialog() | Out-Null
