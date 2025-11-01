param(
    [string]$Action,
    [string]$SSID,
    [string]$Proxy
)

# ========================================
# Paths & Initialization
# ========================================
$configFile = "$env:USERPROFILE\.proxy_config.json"
$logFile = "$env:USERPROFILE\.proxy_manager.log"

if (Test-Path $configFile) {
    $config = Get-Content $configFile | ConvertFrom-Json
} else {
    $config = [pscustomobject]@{
        default = ""
        rules = @{}
    }
}

function Save-Config {
    $config | ConvertTo-Json -Depth 5 | Set-Content $configFile -Encoding UTF8
}

function Write-Log($msg) {
    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    Add-Content -Path $logFile -Value "[$timestamp] $msg"
}

# ========================================
# Network Functions
# ========================================
function Get-SSID {
    $ssidLine = netsh wlan show interfaces | Select-String '^ *SSID *: (.+)$'
    if ($ssidLine) { return ($ssidLine.Matches.Groups[1].Value.Trim()) }
    return $null
}

function List-SSIDs {
    $networks = netsh wlan show networks | Select-String 'SSID [0-9]+ : (.+)$'
    return $networks.Matches | ForEach-Object { $_.Groups[1].Value.Trim() }
}

# ========================================
# Proxy Engine
# ========================================
function Set-Proxy($proxyAddress) {
    if ([string]::IsNullOrEmpty($proxyAddress)) {
        # Reset WinHTTP proxy
        netsh winhttp reset proxy | Out-Null
        
        # Disable IE/WinINET proxy
        Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings" -Name ProxyEnable -Value 0
        Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings" -Name ProxyServer -Value ""
        
        Write-Host "[Proxy] Reset to direct connection."
        Write-Log "Proxy reset to direct connection (WinHTTP + WinINET)"
    } else {
        # Set WinHTTP proxy
        netsh winhttp set proxy "http=$proxyAddress;https=$proxyAddress" bypass-list="localhost" | Out-Null
        
        # Enable and set IE/WinINET proxy
        Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings" -Name ProxyEnable -Value 1
        Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings" -Name ProxyServer -Value $proxyAddress
        Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings" -Name ProxyOverride -Value "localhost;<local>"
        
        Write-Host "[Proxy] Set to $proxyAddress (WinHTTP + WinINET enabled)"
        Write-Log "Proxy set to $proxyAddress (WinHTTP + WinINET enabled)"
    }
    
    # Notify system of proxy changes
    $signature = @'
[DllImport("wininet.dll", SetLastError = true)]
public static extern bool InternetSetOption(IntPtr hInternet, int dwOption, IntPtr lpBuffer, int dwBufferLength);
'@
    
    try {
        $type = Add-Type -MemberDefinition $signature -Name WinINet -Namespace InternetSettings -PassThru -ErrorAction SilentlyContinue
        $INTERNET_OPTION_SETTINGS_CHANGED = 39
        $INTERNET_OPTION_REFRESH = 37
        [void]$type::InternetSetOption([IntPtr]::Zero, $INTERNET_OPTION_SETTINGS_CHANGED, [IntPtr]::Zero, 0)
        [void]$type::InternetSetOption([IntPtr]::Zero, $INTERNET_OPTION_REFRESH, [IntPtr]::Zero, 0)
    } catch {
        # If notify fails, continue anyway
    }
}

function Show-Proxy {
    Write-Host "`n=== WinHTTP Proxy (System Services) ===" -ForegroundColor Cyan
    netsh winhttp show proxy
    
    Write-Host "`n=== WinINET Proxy (Internet Explorer/Browsers) ===" -ForegroundColor Cyan
    $ieSettings = Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings"
    Write-Host "Proxy Enabled: " -NoNewline
    if ($ieSettings.ProxyEnable -eq 1) {
        Write-Host "Yes" -ForegroundColor Green
    } else {
        Write-Host "No" -ForegroundColor Red
    }
    Write-Host "Proxy Server: $($ieSettings.ProxyServer)"
    Write-Host "Proxy Override: $($ieSettings.ProxyOverride)"
}

# ========================================
# Background Mode (auto every 2s)
# ========================================
function Start-AutoProxy {
    Write-Host "Starting background auto-proxy monitor (checks every 2s)..."
    Write-Log "Background proxy monitor started."

    Start-Job -Name "AutoProxy" -ScriptBlock {
        $configFile = "$env:USERPROFILE\.proxy_config.json"
        $logFile = "$env:USERPROFILE\.proxy_manager.log"

        function Write-Log($msg) {
            $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            Add-Content -Path $logFile -Value "[$timestamp] $msg"
        }

        function Get-SSID {
            $ssidLine = netsh wlan show interfaces | Select-String '^ *SSID *: (.+)$'
            if ($ssidLine) { return ($ssidLine.Matches.Groups[1].Value.Trim()) }
            return $null
        }

        function Set-Proxy($proxyAddress) {
            if ([string]::IsNullOrEmpty($proxyAddress)) {
                # Reset WinHTTP proxy
                netsh winhttp reset proxy | Out-Null
                
                # Disable IE/WinINET proxy
                Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings" -Name ProxyEnable -Value 0
                Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings" -Name ProxyServer -Value ""
                
                Write-Log "Proxy reset to direct connection (WinHTTP + WinINET)"
            } else {
                # Set WinHTTP proxy
                netsh winhttp set proxy "http=$proxyAddress;https=$proxyAddress" bypass-list="localhost" | Out-Null
                
                # Enable and set IE/WinINET proxy
                Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings" -Name ProxyEnable -Value 1
                Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings" -Name ProxyServer -Value $proxyAddress
                Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings" -Name ProxyOverride -Value "localhost;<local>"
                
                Write-Log "Proxy set to $proxyAddress (WinHTTP + WinINET enabled)"
            }
            
            # Notify system of proxy changes
            try {
                $signature = @'
[DllImport("wininet.dll", SetLastError = true)]
public static extern bool InternetSetOption(IntPtr hInternet, int dwOption, IntPtr lpBuffer, int dwBufferLength);
'@
                $type = Add-Type -MemberDefinition $signature -Name WinINet -Namespace InternetSettings -PassThru -ErrorAction SilentlyContinue
                $INTERNET_OPTION_SETTINGS_CHANGED = 39
                $INTERNET_OPTION_REFRESH = 37
                [void]$type::InternetSetOption([IntPtr]::Zero, $INTERNET_OPTION_SETTINGS_CHANGED, [IntPtr]::Zero, 0)
                [void]$type::InternetSetOption([IntPtr]::Zero, $INTERNET_OPTION_REFRESH, [IntPtr]::Zero, 0)
            } catch {
                # If notify fails, continue anyway
            }
        }

        if (Test-Path $configFile) {
            $config = Get-Content $configFile | ConvertFrom-Json
        } else {
            Write-Log "No config found — exiting background job."
            return
        }

        $lastSSID = ""

        while ($true) {
            $ssid = Get-SSID
            if ($ssid -ne $lastSSID) {
                if ($null -eq $ssid) {
                    Set-Proxy $null
                    Write-Log "Disconnected from Wi-Fi."
                } elseif ($config.rules.PSObject.Properties.Name -contains $ssid) {
                    Set-Proxy $config.rules.$ssid
                    Write-Log "Connected to $ssid → Applied $($config.rules.$ssid)"
                } elseif ($config.default) {
                    Set-Proxy $config.default
                    Write-Log "Connected to $ssid → Applied default proxy $($config.default)"
                } else {
                    Set-Proxy $null
                    Write-Log "Connected to $ssid → No rule found, reset proxy."
                }
                $lastSSID = $ssid
            }
            Start-Sleep -Seconds 2
        }
    }
}

# ========================================
# Interactive CLI
# ========================================
function Show-TUI {
    Write-Log "TUI: Interactive mode started"
    do {
        Clear-Host
        Write-Host "╔════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
        Write-Host "║       Proxy Manager - Interactive Configuration           ║" -ForegroundColor Cyan
        Write-Host "╚════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
        Write-Host ""
        
        Write-Host "1. View/Edit Existing Networks" -ForegroundColor Yellow
        Write-Host "2. Add New Network Proxy Rule" -ForegroundColor Green
        Write-Host "3. Set Default Proxy" -ForegroundColor Magenta
        Write-Host "4. View All Rules" -ForegroundColor White
        Write-Host "5. Exit TUI" -ForegroundColor Red
        Write-Host ""
        
        $choice = Read-Host "Select option (1-5)"
        
        switch ($choice) {
            "1" {
                Write-Log "TUI: User selected Edit Existing Networks"
                Show-EditNetworks
            }
            "2" {
                Write-Log "TUI: User selected Add New Network"
                Show-AddNetwork
            }
            "3" {
                Write-Log "TUI: User selected Set Default Proxy"
                Show-SetDefault
            }
            "4" {
                Write-Log "TUI: User selected View All Rules"
                Show-AllRules
                Read-Host "`nPress Enter to continue"
            }
            "5" {
                Write-Host "`nExiting TUI..." -ForegroundColor Green
                Write-Log "TUI: Interactive mode exited by user"
                return
            }
            default {
                Write-Host "`nInvalid option. Press Enter to continue..." -ForegroundColor Red
                Write-Log "TUI: Invalid menu option selected: $choice"
                Read-Host
            }
        }
    } while ($true)
}

function Show-EditNetworks {
    Write-Host "`n=== Edit Existing Networks ===" -ForegroundColor Cyan
    
    $ssids = List-SSIDs
    if ($ssids.Count -eq 0) {
        Write-Host "No Wi-Fi networks visible." -ForegroundColor Yellow
        Read-Host "`nPress Enter to continue"
        return
    }

    Write-Host ""
    Write-Host "Available Networks:" -ForegroundColor Yellow
    Write-Host ("─" * 60) -ForegroundColor Gray
    
    $index = 1
    $ssidList = @()
    foreach ($ssid in $ssids) {
        $currentProxy = if ($config.rules.PSObject.Properties.Name -contains $ssid) { 
            $config.rules.$ssid 
        } else { 
            "(not configured)" 
        }
        $ssidList += [PSCustomObject]@{
            Index = $index
            SSID = $ssid
            CurrentProxy = $currentProxy
        }
        
        Write-Host "  [$index] " -NoNewline -ForegroundColor Cyan
        Write-Host "$ssid " -NoNewline -ForegroundColor White
        Write-Host "→ $currentProxy" -ForegroundColor Gray
        $index++
    }
    
    Write-Host ""
    $selection = Read-Host "Select network number (1-$($ssids.Count)) or 0 to cancel"
    
    if ($selection -eq "0" -or [string]::IsNullOrWhiteSpace($selection)) {
        Write-Log "TUI: Edit networks cancelled by user"
        return
    }
    
    $selectionNum = 0
    if ([int]::TryParse($selection, [ref]$selectionNum) -and $selectionNum -ge 1 -and $selectionNum -le $ssids.Count) {
        $selectedSSID = $ssidList[$selectionNum - 1].SSID
        
        Write-Host ""
        Write-Host "Selected Network: $selectedSSID" -ForegroundColor Green
        
        if ($config.rules.PSObject.Properties.Name -contains $selectedSSID) {
            Write-Host "Current Proxy: $($config.rules.$selectedSSID)" -ForegroundColor Yellow
        } else {
            Write-Host "Current Proxy: (not configured)" -ForegroundColor Gray
        }
        
        Write-Host ""
        $newProxy = Read-Host "Enter new proxy (format: host:port) or leave blank to remove"
        
        if ([string]::IsNullOrWhiteSpace($newProxy)) {
            if ($config.rules.PSObject.Properties.Name -contains $selectedSSID) {
                $config.rules.PSObject.Properties.Remove($selectedSSID)
                Save-Config
                Write-Log "TUI: Removed proxy for $selectedSSID"
                Write-Host "✓ Removed proxy rule for $selectedSSID" -ForegroundColor Green
            } else {
                Write-Host "No rule to remove." -ForegroundColor Gray
                Write-Log "TUI: No rule to remove for $selectedSSID"
            }
        } else {
            if ($config.rules.PSObject.Properties.Name -contains $selectedSSID) {
                $oldProxy = $config.rules.$selectedSSID
                $config.rules.$selectedSSID = $newProxy
                Write-Log "TUI: Updated proxy for $selectedSSID from $oldProxy to $newProxy"
            } else {
                $config.rules | Add-Member -MemberType NoteProperty -Name $selectedSSID -Value $newProxy -Force
                Write-Log "TUI: Added proxy $newProxy for $selectedSSID"
            }
            Save-Config
            Write-Host "✓ Set proxy $newProxy for $selectedSSID" -ForegroundColor Green
        }
    } else {
        Write-Host "Invalid selection." -ForegroundColor Red
        Write-Log "TUI: Invalid selection in edit networks: $selection"
    }
    
    Read-Host "`nPress Enter to continue"
}

function Show-AddNetwork {
    Write-Host "`n=== Add New Network Proxy Rule ===" -ForegroundColor Cyan
    Write-Host ""
    
    Write-Host "You can either:" -ForegroundColor Yellow
    Write-Host "  1. Select from visible networks"
    Write-Host "  2. Manually enter an SSID name"
    Write-Host ""
    
    $addChoice = Read-Host "Choose option (1 or 2)"
    
    $newSSID = ""
    
    if ($addChoice -eq "1") {
        $ssids = List-SSIDs
        if ($ssids.Count -eq 0) {
            Write-Host "No Wi-Fi networks visible." -ForegroundColor Yellow
            Write-Log "TUI: No Wi-Fi networks visible for adding"
            Read-Host "`nPress Enter to continue"
            return
        }
        
        Write-Host ""
        Write-Host "Available Networks:" -ForegroundColor Yellow
        Write-Host ("─" * 60) -ForegroundColor Gray
        
        $index = 1
        $ssidList = @()
        foreach ($ssid in $ssids) {
            $status = if ($config.rules.PSObject.Properties.Name -contains $ssid) { 
                "[Already configured: $($config.rules.$ssid)]"
            } else { 
                "[Not configured]"
            }
            $ssidList += [PSCustomObject]@{
                Index = $index
                SSID = $ssid
                Status = $status
            }
            
            Write-Host "  [$index] " -NoNewline -ForegroundColor Cyan
            Write-Host "$ssid " -NoNewline -ForegroundColor White
            Write-Host "$status" -ForegroundColor Gray
            $index++
        }
        
        Write-Host ""
        $selection = Read-Host "Select network number (1-$($ssids.Count)) or 0 to cancel"
        
        if ($selection -eq "0" -or [string]::IsNullOrWhiteSpace($selection)) {
            Write-Log "TUI: Add network cancelled by user"
            return
        }
        
        $selectionNum = 0
        if ([int]::TryParse($selection, [ref]$selectionNum) -and $selectionNum -ge 1 -and $selectionNum -le $ssids.Count) {
            $newSSID = $ssidList[$selectionNum - 1].SSID
        } else {
            Write-Host "Invalid selection." -ForegroundColor Red
            Write-Log "TUI: Invalid selection in add network: $selection"
            Read-Host "`nPress Enter to continue"
            return
        }
    } elseif ($addChoice -eq "2") {
        $newSSID = Read-Host "Enter SSID name"
        if ([string]::IsNullOrWhiteSpace($newSSID)) {
            Write-Host "Invalid SSID." -ForegroundColor Red
            Write-Log "TUI: Invalid SSID entered (blank)"
            Read-Host "`nPress Enter to continue"
            return
        }
        Write-Log "TUI: Manual SSID entered: $newSSID"
    } else {
        Write-Host "Invalid choice." -ForegroundColor Red
        Write-Log "TUI: Invalid choice in add network menu: $addChoice"
        Read-Host "`nPress Enter to continue"
        return
    }
    
    Write-Host ""
    Write-Host "Network: $newSSID" -ForegroundColor Green
    
    if ($config.rules.PSObject.Properties.Name -contains $newSSID) {
        Write-Host "Current Proxy: $($config.rules.$newSSID)" -ForegroundColor Yellow
        Write-Host "Note: This will overwrite the existing proxy." -ForegroundColor Yellow
    }
    
    Write-Host ""
    $newProxy = Read-Host "Enter proxy address (format: host:port, e.g., 192.168.1.1:8080)"
    
    if ([string]::IsNullOrWhiteSpace($newProxy)) {
        Write-Host "No proxy entered. Operation cancelled." -ForegroundColor Red
        Write-Log "TUI: Add network cancelled - no proxy entered for $newSSID"
    } else {
        if ($config.rules.PSObject.Properties.Name -contains $newSSID) {
            $oldProxy = $config.rules.$newSSID
            $config.rules.$newSSID = $newProxy
            Write-Log "TUI: Updated proxy for $newSSID from $oldProxy to $newProxy"
        } else {
            $config.rules | Add-Member -MemberType NoteProperty -Name $newSSID -Value $newProxy -Force
            Write-Log "TUI: Added new proxy rule: $newSSID → $newProxy"
        }
        Save-Config
        Write-Host "✓ Successfully added: $newSSID → $newProxy" -ForegroundColor Green
    }
    
    Read-Host "`nPress Enter to continue"
}

function Show-SetDefault {
    Write-Host "`n=== Set Default Proxy ===" -ForegroundColor Cyan
    Write-Host ""
    
    if ($config.default) {
        Write-Host "Current Default: $($config.default)" -ForegroundColor Yellow
    } else {
        Write-Host "Current Default: (not set)" -ForegroundColor Gray
    }
    
    Write-Host ""
    $newDefault = Read-Host "Enter default proxy (format: host:port) or leave blank to remove"
    
    if ([string]::IsNullOrWhiteSpace($newDefault)) {
        if ($config.default) {
            $oldDefault = $config.default
            $config.default = ""
            Save-Config
            Write-Log "TUI: Removed default proxy (was: $oldDefault)"
            Write-Host "✓ Default proxy removed" -ForegroundColor Green
        } else {
            Write-Host "No default proxy to remove." -ForegroundColor Gray
            Write-Log "TUI: No default proxy to remove"
        }
    } else {
        if ($config.default) {
            $oldDefault = $config.default
            $config.default = $newDefault
            Write-Log "TUI: Updated default proxy from $oldDefault to $newDefault"
        } else {
            $config.default = $newDefault
            Write-Log "TUI: Set default proxy to $newDefault"
        }
        Save-Config
        Write-Host "✓ Default proxy set to: $newDefault" -ForegroundColor Green
    }
    
    Read-Host "`nPress Enter to continue"
}

function Show-AllRules {
    Write-Host "`n╔════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║              Current Proxy Configuration                  ║" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
    
    Write-Host "Default Proxy: " -NoNewline -ForegroundColor Yellow
    if ($config.default) {
        Write-Host $config.default -ForegroundColor White
    } else {
        Write-Host "(not set)" -ForegroundColor Gray
    }
    
    Write-Host ""
    Write-Host "Network-Specific Rules:" -ForegroundColor Yellow
    Write-Host ("─" * 60) -ForegroundColor Gray
    
    if ($config.rules.PSObject.Properties.Count -gt 0) {
        $config.rules.PSObject.Properties | ForEach-Object {
            Write-Host ("  {0,-2} → {1}" -f $_.Name, $_.Value) -ForegroundColor White
        }
    } else {
        Write-Host "  (no rules configured)" -ForegroundColor Gray
    }
    
    Write-Host ""
    Write-Host "Visible Wi-Fi Networks:" -ForegroundColor Yellow
    Write-Host ("─" * 60) -ForegroundColor Gray
    $visibleNetworks = List-SSIDs
    if ($visibleNetworks.Count -gt 0) {
        $visibleNetworks | ForEach-Object { 
            $hasRule = $config.rules.PSObject.Properties.Name -contains $_
            if ($hasRule) {
                Write-Host "  $_ " -NoNewline -ForegroundColor White
                Write-Host "[configured]" -ForegroundColor Green
            } else {
                Write-Host "  $_ " -NoNewline -ForegroundColor White
                Write-Host "[not configured]" -ForegroundColor Gray
            }
        }
    } else {
        Write-Host "  (no networks visible)" -ForegroundColor Gray
    }
}

# ========================================
# Command Dispatcher
# ========================================
switch ($Action.ToLower()) {
    "add"       { 
        if (-not $SSID -or -not $Proxy) {
            Write-Host "Usage: add <SSID> <proxy:port>"
        } else {
            if ($config.rules.PSObject.Properties.Name -contains $SSID) {
                $config.rules.$SSID = $Proxy
            } else {
                $config.rules | Add-Member -MemberType NoteProperty -Name $SSID -Value $Proxy -Force
            }
            Save-Config
            Write-Host "Added: $SSID → $Proxy"
            Write-Log "Added: $SSID → $Proxy"
        }
    }
    "remove"    { 
        if (-not $SSID) {
            Write-Host "Usage: remove <SSID>"
        } else {
            if ($config.rules.PSObject.Properties.Name -contains $SSID) {
                $config.rules.PSObject.Properties.Remove($SSID)
                Save-Config
                Write-Host "Removed: $SSID"
                Write-Log "Removed: $SSID"
            } else {
                Write-Host "No rule found for: $SSID"
            }
        }
    }
    "default"   { 
        if (-not $Proxy) {
            Write-Host "Usage: default <proxy:port>"
        } else {
            $config.default = $Proxy
            Save-Config
            Write-Host "Default proxy: $Proxy"
            Write-Log "Default proxy set to $Proxy"
        }
    }
    "auto"      { 
        $ssid = Get-SSID
        if (-not $ssid) {
            Write-Host "No SSID detected"
            Set-Proxy $null
            exit
        }
        if ($config.rules.PSObject.Properties.Name -contains $ssid) {
            Set-Proxy $config.rules.$ssid
        } elseif ($config.default) {
            Set-Proxy $config.default
        } else {
            Set-Proxy $null
        }
    }
    "list"      { 
        Write-Host "=== Configured Proxy Rules ===" -ForegroundColor Cyan
        if ($config.rules.PSObject.Properties.Count -gt 0) {
            $config.rules.PSObject.Properties | ForEach-Object {
                Write-Host ("{0,-20} -> {1}" -f $_.Name, $_.Value)
            }
        } else {
            Write-Host "  (no rules configured)" -ForegroundColor Gray
        }
        Write-Host "`nDefault Proxy: $($config.default)" -ForegroundColor Cyan
        Write-Host "`n=== Visible Wi-Fi Networks ===" -ForegroundColor Cyan
        List-SSIDs | ForEach-Object { Write-Host "  $_" }
    }
    "show-current" { Show-Proxy }
    "background"   { Start-AutoProxy }
    "tui"          { Show-TUI }
    default {
        Write-Host "Commands:" -ForegroundColor Cyan
        Write-Host "  add <SSID> <proxy:port>     - Add proxy rule"
        Write-Host "  remove <SSID>               - Remove rule"
        Write-Host "  default <proxy:port>        - Set default proxy"
        Write-Host "  auto                        - Apply based on current SSID"
        Write-Host "  list                        - Show rules + visible SSIDs"
        Write-Host "  show-current                - Show current proxy"
        Write-Host "  background                  - Start background auto mode"
        Write-Host "  tui                         - Interactive config mode"
    }
}