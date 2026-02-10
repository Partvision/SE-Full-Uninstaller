# Game Uninstaller Pro - GUI Version
# Requires Administrator privileges

# Hide PowerShell console window
Add-Type -Name Window -Namespace Console -MemberDefinition '
[DllImport("Kernel32.dll")]
public static extern IntPtr GetConsoleWindow();

[DllImport("user32.dll")]
public static extern bool ShowWindow(IntPtr hWnd, Int32 nCmdShow);
'

$consolePtr = [Console.Window]::GetConsoleWindow()
[Console.Window]::ShowWindow($consolePtr, 0) | Out-Null

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Check for admin privileges
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    [System.Windows.Forms.MessageBox]::Show("This application requires Administrator privileges. Please run as Administrator.", "Admin Required", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
    exit
}

# Global variables
$global:gamesList = @()
$global:selectedGame = $null

#region Functions

function Get-SteamGames {
    $games = @()
    try {
        $steamPath = (Get-ItemProperty -Path "HKCU:\Software\Valve\Steam" -Name "SteamPath" -ErrorAction SilentlyContinue).SteamPath
        if ($steamPath) {
            $steamPath = $steamPath -replace '/', '\'
            $steamApps = Join-Path $steamPath "steamapps"
            
            if (Test-Path $steamApps) {
                $manifests = Get-ChildItem -Path $steamApps -Filter "appmanifest_*.acf"
                
                foreach ($manifest in $manifests) {
                    $content = Get-Content $manifest.FullName -Raw
                    $name = if ($content -match '"name"\s+"([^"]+)"') { $matches[1] } else { "Unknown" }
                    $installdir = if ($content -match '"installdir"\s+"([^"]+)"') { $matches[1] } else { "" }
                    $appid = if ($content -match '"appid"\s+"([^"]+)"') { $matches[1] } else { "" }
                    
                    $installPath = Join-Path (Join-Path $steamApps "common") $installdir
                    
                    $games += [PSCustomObject]@{
                        Name = $name
                        Platform = "Steam"
                        InstallPath = $installPath
                        ManifestPath = $manifest.FullName
                        AppID = $appid
                        DisplayName = "[$($name)] (Steam)"
                    }
                }
            }
        }
    } catch {
        Write-Host "Error scanning Steam games: $_"
    }
    return $games
}

function Get-EpicGames {
    $games = @()
    try {
        $epicManifests = "$env:ProgramData\Epic\EpicGamesLauncher\Data\Manifests"
        
        if (Test-Path $epicManifests) {
            $manifests = Get-ChildItem -Path $epicManifests -Filter "*.item"
            
            foreach ($manifest in $manifests) {
                $content = Get-Content $manifest.FullName -Raw | ConvertFrom-Json
                
                $name = $content.DisplayName
                $installPath = $content.InstallLocation
                $appName = $content.AppName
                
                if ($name -and $installPath) {
                    $games += [PSCustomObject]@{
                        Name = $name
                        Platform = "Epic"
                        InstallPath = $installPath
                        ManifestPath = $manifest.FullName
                        AppID = $appName
                        DisplayName = "[$($name)] (Epic Games)"
                    }
                }
            }
        }
    } catch {
        Write-Host "Error scanning Epic games: $_"
    }
    return $games
}

function Refresh-GamesList {
    $global:gamesList = @()
    $global:gamesList += Get-SteamGames
    $global:gamesList += Get-EpicGames
    
    $listBox.Items.Clear()
    foreach ($game in $global:gamesList) {
        $listBox.Items.Add($game.DisplayName) | Out-Null
    }
    
    $statusLabel.Text = "Found $($global:gamesList.Count) games"
}

function Remove-Game {
    param($game)
    
    $progressBar.Value = 0
    $progressBar.Visible = $true
    $statusLabel.Text = "Uninstalling $($game.Name)..."
    
    # Step 1: Delete game files
    $progressBar.Value = 20
    if (Test-Path $game.InstallPath) {
        Remove-Item -Path $game.InstallPath -Recurse -Force -ErrorAction SilentlyContinue
    }
    
    # Step 2: Delete manifest
    $progressBar.Value = 40
    if (Test-Path $game.ManifestPath) {
        Remove-Item -Path $game.ManifestPath -Force -ErrorAction SilentlyContinue
    }
    
    # Step 3: Remove shortcuts
    $progressBar.Value = 60
    Remove-GameShortcuts -game $game
    
    # Step 4: Clean registry
    $progressBar.Value = 80
    if ($game.Platform -eq "Steam") {
        Remove-Item -Path "HKCU:\Software\Valve\Steam\Apps\$($game.AppID)" -Force -ErrorAction SilentlyContinue
    } elseif ($game.Platform -eq "Epic") {
        Remove-Item -Path "HKCU:\Software\Epic Games\$($game.AppID)" -Force -ErrorAction SilentlyContinue
        Remove-Item -Path "HKLM:\SOFTWARE\Epic Games\$($game.AppID)" -Force -ErrorAction SilentlyContinue
    }
    
    $progressBar.Value = 100
    $statusLabel.Text = "Successfully uninstalled: $($game.Name)"
    
    Start-Sleep -Milliseconds 500
    $progressBar.Visible = $false
}

function Remove-GameShortcuts {
    param($game)
    
    $desktopPaths = @(
        [Environment]::GetFolderPath('Desktop'),
        [Environment]::GetFolderPath('CommonDesktopDirectory')
    )
    
    $startMenuPaths = @(
        [Environment]::GetFolderPath('StartMenu'),
        [Environment]::GetFolderPath('CommonStartMenu')
    )
    
    $allPaths = $desktopPaths + $startMenuPaths
    
    foreach ($path in $allPaths) {
        if (Test-Path $path) {
            $shortcuts = Get-ChildItem -Path $path -Include *.lnk, *.url -Recurse -ErrorAction SilentlyContinue
            
            foreach ($shortcut in $shortcuts) {
                $shouldDelete = $false
                
                if ($shortcut.Extension -eq '.lnk') {
                    try {
                        $shell = New-Object -ComObject WScript.Shell
                        $link = $shell.CreateShortcut($shortcut.FullName)
                        
                        if ($link.TargetPath -like "*$($game.InstallPath)*" -or 
                            $link.WorkingDirectory -like "*$($game.InstallPath)*") {
                            $shouldDelete = $true
                        }
                        
                        if ($game.Platform -eq "Steam" -and $link.Arguments -like "*$($game.AppID)*") {
                            $shouldDelete = $true
                        }
                        
                        if ($game.Platform -eq "Epic" -and $link.Arguments -like "*$($game.AppID)*") {
                            $shouldDelete = $true
                        }
                    } catch {}
                }
                
                if ($shouldDelete) {
                    Remove-Item -Path $shortcut.FullName -Force -ErrorAction SilentlyContinue
                }
            }
        }
    }
}

function Restart-Launcher {
    param($launcher)
    
    if ($launcher -eq "Steam") {
        Stop-Process -Name "steam" -Force -ErrorAction SilentlyContinue
        Stop-Process -Name "steamwebhelper" -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        
        $steamExe = (Get-ItemProperty -Path "HKCU:\Software\Valve\Steam" -Name "SteamExe" -ErrorAction SilentlyContinue).SteamExe
        if ($steamExe -and (Test-Path $steamExe)) {
            Start-Process $steamExe
            $statusLabel.Text = "Steam restarted"
        } else {
            $statusLabel.Text = "Steam executable not found"
        }
    } elseif ($launcher -eq "Epic") {
        Stop-Process -Name "EpicGamesLauncher" -Force -ErrorAction SilentlyContinue
        Stop-Process -Name "EpicWebHelper" -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        
        $epicExe = "$env:ProgramFiles(x86)\Epic Games\Launcher\Portal\Binaries\Win64\EpicGamesLauncher.exe"
        if (-not (Test-Path $epicExe)) {
            $epicExe = "$env:ProgramFiles\Epic Games\Launcher\Portal\Binaries\Win64\EpicGamesLauncher.exe"
        }
        
        if (Test-Path $epicExe) {
            Start-Process $epicExe
            $statusLabel.Text = "Epic Games Launcher restarted"
        } else {
            $statusLabel.Text = "Epic Games Launcher executable not found"
        }
    }
}

function Clear-LauncherCache {
    param($launcher)
    
    if ($launcher -eq "Steam") {
        $steamPath = (Get-ItemProperty -Path "HKCU:\Software\Valve\Steam" -Name "SteamPath" -ErrorAction SilentlyContinue).SteamPath
        if ($steamPath) {
            $steamPath = $steamPath -replace '/', '\'
            $cachePath = Join-Path $steamPath "appcache"
            
            if (Test-Path $cachePath) {
                Remove-Item -Path $cachePath -Recurse -Force -ErrorAction SilentlyContinue
                $statusLabel.Text = "Steam cache cleared"
            } else {
                $statusLabel.Text = "Steam cache not found"
            }
        }
    } elseif ($launcher -eq "Epic") {
        $cachePath = "$env:LOCALAPPDATA\EpicGamesLauncher\Saved\webcache"
        
        if (Test-Path $cachePath) {
            Remove-Item -Path $cachePath -Recurse -Force -ErrorAction SilentlyContinue
            $statusLabel.Text = "Epic cache cleared"
        } else {
            $statusLabel.Text = "Epic cache not found"
        }
    }
}

function Clear-TempFiles {
    $beforeSpace = (Get-PSDrive C).Free / 1MB
    
    $progressBar.Value = 0
    $progressBar.Visible = $true
    $statusLabel.Text = "Cleaning temporary files..."
    
    # User temp
    $progressBar.Value = 10
    Remove-Item -Path "$env:TEMP\*" -Recurse -Force -ErrorAction SilentlyContinue
    
    # Windows temp
    $progressBar.Value = 25
    Remove-Item -Path "C:\Windows\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue
    
    # Prefetch
    $progressBar.Value = 40
    Remove-Item -Path "C:\Windows\Prefetch\*" -Force -ErrorAction SilentlyContinue
    
    # Windows Update cache
    $progressBar.Value = 55
    Remove-Item -Path "C:\Windows\SoftwareDistribution\Download\*" -Recurse -Force -ErrorAction SilentlyContinue
    
    # Recycle Bin
    $progressBar.Value = 70
    Clear-RecycleBin -Force -ErrorAction SilentlyContinue
    
    # Chrome cache
    $progressBar.Value = 85
    Remove-Item -Path "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache\*" -Recurse -Force -ErrorAction SilentlyContinue
    
    $progressBar.Value = 100
    
    $afterSpace = (Get-PSDrive C).Free / 1MB
    $freed = [math]::Round($afterSpace - $beforeSpace, 2)
    
    $statusLabel.Text = "Cleanup complete! Freed: $freed MB"
    
    Start-Sleep -Seconds 2
    $progressBar.Visible = $false
}

#endregion

#region UI Creation

# Main Form
$form = New-Object System.Windows.Forms.Form
$form.Text = "Game Uninstaller Pro"
$form.Size = New-Object System.Drawing.Size(800, 600)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false

# Tab Control
$tabControl = New-Object System.Windows.Forms.TabControl
$tabControl.Location = New-Object System.Drawing.Point(10, 10)
$tabControl.Size = New-Object System.Drawing.Size(760, 500)

# Tab 1: Uninstall Games
$tabUninstall = New-Object System.Windows.Forms.TabPage
$tabUninstall.Text = "Uninstall Games"
$tabControl.Controls.Add($tabUninstall)

# Games ListBox
$listBox = New-Object System.Windows.Forms.ListBox
$listBox.Location = New-Object System.Drawing.Point(10, 50)
$listBox.Size = New-Object System.Drawing.Size(730, 300)
$listBox.Font = New-Object System.Drawing.Font("Consolas", 10)
$tabUninstall.Controls.Add($listBox)

# Refresh Button
$btnRefresh = New-Object System.Windows.Forms.Button
$btnRefresh.Location = New-Object System.Drawing.Point(10, 10)
$btnRefresh.Size = New-Object System.Drawing.Size(100, 30)
$btnRefresh.Text = "Refresh List"
$btnRefresh.Add_Click({
    Refresh-GamesList
})
$tabUninstall.Controls.Add($btnRefresh)

# Game Info Label
$gameInfoLabel = New-Object System.Windows.Forms.Label
$gameInfoLabel.Location = New-Object System.Drawing.Point(10, 360)
$gameInfoLabel.Size = New-Object System.Drawing.Size(730, 60)
$gameInfoLabel.Text = "Select a game to see details"
$gameInfoLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$tabUninstall.Controls.Add($gameInfoLabel)

# Uninstall Button
$btnUninstall = New-Object System.Windows.Forms.Button
$btnUninstall.Location = New-Object System.Drawing.Point(10, 430)
$btnUninstall.Size = New-Object System.Drawing.Size(150, 35)
$btnUninstall.Text = "Uninstall Selected"
$btnUninstall.BackColor = [System.Drawing.Color]::IndianRed
$btnUninstall.ForeColor = [System.Drawing.Color]::White
$btnUninstall.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$btnUninstall.Add_Click({
    $selectedIndex = $listBox.SelectedIndex
    if ($selectedIndex -ge 0) {
        $game = $global:gamesList[$selectedIndex]
        
        $result = [System.Windows.Forms.MessageBox]::Show(
            "Are you sure you want to permanently uninstall:`n`n$($game.Name)`n`nThis action cannot be undone!",
            "Confirm Uninstall",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
        
        if ($result -eq [System.Windows.Forms.DialogResult]::Yes) {
            Remove-Game -game $game
            Refresh-GamesList
        }
    } else {
        [System.Windows.Forms.MessageBox]::Show("Please select a game first.", "No Selection", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
    }
})
$tabUninstall.Controls.Add($btnUninstall)

# ListBox selection changed event
$listBox.Add_SelectedIndexChanged({
    $selectedIndex = $listBox.SelectedIndex
    if ($selectedIndex -ge 0) {
        $game = $global:gamesList[$selectedIndex]
        $gameInfoLabel.Text = "Name: $($game.Name)`nPlatform: $($game.Platform)`nPath: $($game.InstallPath)`nApp ID: $($game.AppID)"
    }
})

# Tab 2: Launcher Tools
$tabLauncher = New-Object System.Windows.Forms.TabPage
$tabLauncher.Text = "Launcher Tools"
$tabControl.Controls.Add($tabLauncher)

# Steam Group
$groupSteam = New-Object System.Windows.Forms.GroupBox
$groupSteam.Location = New-Object System.Drawing.Point(10, 10)
$groupSteam.Size = New-Object System.Drawing.Size(350, 200)
$groupSteam.Text = "Steam"
$tabLauncher.Controls.Add($groupSteam)

$btnRestartSteam = New-Object System.Windows.Forms.Button
$btnRestartSteam.Location = New-Object System.Drawing.Point(20, 30)
$btnRestartSteam.Size = New-Object System.Drawing.Size(150, 30)
$btnRestartSteam.Text = "Restart Steam"
$btnRestartSteam.Add_Click({ Restart-Launcher -launcher "Steam" })
$groupSteam.Controls.Add($btnRestartSteam)

$btnClearSteamCache = New-Object System.Windows.Forms.Button
$btnClearSteamCache.Location = New-Object System.Drawing.Point(20, 70)
$btnClearSteamCache.Size = New-Object System.Drawing.Size(150, 30)
$btnClearSteamCache.Text = "Clear Steam Cache"
$btnClearSteamCache.Add_Click({ Clear-LauncherCache -launcher "Steam" })
$groupSteam.Controls.Add($btnClearSteamCache)

$btnOpenSteamFolder = New-Object System.Windows.Forms.Button
$btnOpenSteamFolder.Location = New-Object System.Drawing.Point(20, 110)
$btnOpenSteamFolder.Size = New-Object System.Drawing.Size(150, 30)
$btnOpenSteamFolder.Text = "Open Library Folder"
$btnOpenSteamFolder.Add_Click({
    $steamPath = (Get-ItemProperty -Path "HKCU:\Software\Valve\Steam" -Name "SteamPath" -ErrorAction SilentlyContinue).SteamPath
    if ($steamPath) {
        $steamPath = $steamPath -replace '/', '\'
        $libraryPath = Join-Path $steamPath "steamapps\common"
        if (Test-Path $libraryPath) {
            Start-Process explorer.exe $libraryPath
        }
    }
})
$groupSteam.Controls.Add($btnOpenSteamFolder)

# Epic Group
$groupEpic = New-Object System.Windows.Forms.GroupBox
$groupEpic.Location = New-Object System.Drawing.Point(380, 10)
$groupEpic.Size = New-Object System.Drawing.Size(350, 200)
$groupEpic.Text = "Epic Games Launcher"
$tabLauncher.Controls.Add($groupEpic)

$btnRestartEpic = New-Object System.Windows.Forms.Button
$btnRestartEpic.Location = New-Object System.Drawing.Point(20, 30)
$btnRestartEpic.Size = New-Object System.Drawing.Size(180, 30)
$btnRestartEpic.Text = "Restart Epic Launcher"
$btnRestartEpic.Add_Click({ Restart-Launcher -launcher "Epic" })
$groupEpic.Controls.Add($btnRestartEpic)

$btnClearEpicCache = New-Object System.Windows.Forms.Button
$btnClearEpicCache.Location = New-Object System.Drawing.Point(20, 70)
$btnClearEpicCache.Size = New-Object System.Drawing.Size(180, 30)
$btnClearEpicCache.Text = "Clear Epic Cache"
$btnClearEpicCache.Add_Click({ Clear-LauncherCache -launcher "Epic" })
$groupEpic.Controls.Add($btnClearEpicCache)

# Tab 3: Maintenance
$tabMaintenance = New-Object System.Windows.Forms.TabPage
$tabMaintenance.Text = "Maintenance"
$tabControl.Controls.Add($tabMaintenance)

$btnTempCleaner = New-Object System.Windows.Forms.Button
$btnTempCleaner.Location = New-Object System.Drawing.Point(20, 20)
$btnTempCleaner.Size = New-Object System.Drawing.Size(200, 40)
$btnTempCleaner.Text = "Clean Temporary Files"
$btnTempCleaner.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$btnTempCleaner.Add_Click({ Clear-TempFiles })
$tabMaintenance.Controls.Add($btnTempCleaner)

$btnRestartExplorer = New-Object System.Windows.Forms.Button
$btnRestartExplorer.Location = New-Object System.Drawing.Point(20, 70)
$btnRestartExplorer.Size = New-Object System.Drawing.Size(200, 40)
$btnRestartExplorer.Text = "Restart Windows Explorer"
$btnRestartExplorer.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$btnRestartExplorer.Add_Click({
    Stop-Process -Name explorer -Force
    Start-Sleep -Milliseconds 500
    Start-Process explorer.exe
    $statusLabel.Text = "Explorer restarted"
})
$tabMaintenance.Controls.Add($btnRestartExplorer)

$btnClearDNS = New-Object System.Windows.Forms.Button
$btnClearDNS.Location = New-Object System.Drawing.Point(20, 120)
$btnClearDNS.Size = New-Object System.Drawing.Size(200, 40)
$btnClearDNS.Text = "Clear DNS Cache"
$btnClearDNS.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$btnClearDNS.Add_Click({
    ipconfig /flushdns | Out-Null
    $statusLabel.Text = "DNS cache cleared"
})
$tabMaintenance.Controls.Add($btnClearDNS)

$btnDiskCleanup = New-Object System.Windows.Forms.Button
$btnDiskCleanup.Location = New-Object System.Drawing.Point(20, 170)
$btnDiskCleanup.Size = New-Object System.Drawing.Size(200, 40)
$btnDiskCleanup.Text = "Open Disk Cleanup"
$btnDiskCleanup.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$btnDiskCleanup.Add_Click({
    Start-Process cleanmgr.exe -ArgumentList "/d C:"
})
$tabMaintenance.Controls.Add($btnDiskCleanup)

# System Info Display
$sysInfoTextBox = New-Object System.Windows.Forms.TextBox
$sysInfoTextBox.Location = New-Object System.Drawing.Point(250, 20)
$sysInfoTextBox.Size = New-Object System.Drawing.Size(480, 400)
$sysInfoTextBox.Multiline = $true
$sysInfoTextBox.ScrollBars = "Vertical"
$sysInfoTextBox.Font = New-Object System.Drawing.Font("Consolas", 9)
$sysInfoTextBox.ReadOnly = $true
$tabMaintenance.Controls.Add($sysInfoTextBox)

$btnGetSysInfo = New-Object System.Windows.Forms.Button
$btnGetSysInfo.Location = New-Object System.Drawing.Point(20, 220)
$btnGetSysInfo.Size = New-Object System.Drawing.Size(200, 40)
$btnGetSysInfo.Text = "Get System Info"
$btnGetSysInfo.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$btnGetSysInfo.Add_Click({
    $sysInfo = systeminfo | Select-String "OS Name", "OS Version", "System Type", "Total Physical Memory"
    $diskInfo = Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Used } | 
        ForEach-Object { 
            $used = [math]::Round($_.Used/1GB, 2)
            $free = [math]::Round($_.Free/1GB, 2)
            $total = $used + $free
            "$($_.Name): - Used: $used GB - Free: $free GB - Total: $total GB"
        }
    
    $sysInfoTextBox.Text = "=== SYSTEM INFORMATION ===`r`n`r`n"
    $sysInfoTextBox.Text += ($sysInfo -join "`r`n")
    $sysInfoTextBox.Text += "`r`n`r`n=== DISK INFORMATION ===`r`n`r`n"
    $sysInfoTextBox.Text += ($diskInfo -join "`r`n")
})
$tabMaintenance.Controls.Add($btnGetSysInfo)

$form.Controls.Add($tabControl)

# Progress Bar
$progressBar = New-Object System.Windows.Forms.ProgressBar
$progressBar.Location = New-Object System.Drawing.Point(10, 515)
$progressBar.Size = New-Object System.Drawing.Size(760, 20)
$progressBar.Visible = $false
$form.Controls.Add($progressBar)

# Status Label
$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Location = New-Object System.Drawing.Point(10, 540)
$statusLabel.Size = New-Object System.Drawing.Size(760, 20)
$statusLabel.Text = "Ready"
$statusLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$form.Controls.Add($statusLabel)

#endregion

# Initialize
Refresh-GamesList

# Show Form
[void]$form.ShowDialog()
