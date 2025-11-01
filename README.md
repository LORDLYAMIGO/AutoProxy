# Proxy Manager (Windows PowerShell)

A practical PowerShell utility for Windows that manages system proxy settings (both WinHTTP and WinINET) based on the currently connected Wi‑Fi SSID. It supports per‑network rules, a global default proxy, a background auto‑apply mode, and an interactive TUI for editing configuration. Configuration and logs are stored under the current user profile.

This script is Windows-only and intended for laptops and desktops that move across different Wi‑Fi networks and need different proxy settings applied automatically.

---

## Features

- Per‑SSID proxy rules (e.g., apply proxy only on "CorpNet")
- Optional default proxy for any SSID without a rule
- Applies both:
  - WinHTTP proxy (used by Windows system services and some tools)
  - WinINET/IE proxy (used by most desktop apps and browsers)
- Background monitor that detects SSID changes and applies the correct proxy automatically
- Interactive TUI to add, edit, and review rules
- Command‑line interface for scripting and automation
- Configuration persisted to a JSON file; actions logged to a rotating log

---

## Requirements

- Windows 10/11 (or Windows Server with WLAN and registry access)
- PowerShell 5.1 or newer (Windows PowerShell or PowerShell 7+ on Windows)
- Administrative privileges are required to modify WinHTTP proxy via `netsh winhttp`
  - Without elevation, WinINET (per‑user) proxy changes will still apply
- WLAN interface (for SSID detection); Ethernet‑only environments will show “No SSID detected”

---

## Files and Locations

- Configuration file: `%USERPROFILE%\.proxy_config.json`
- Log file: `%USERPROFILE%\.proxy_manager.log`

Example configuration:
```json
{
  "default": "10.0.0.10:8080",
  "rules": {
    "CorpNet": "10.0.0.10:8080",
    "GuestWiFi": "192.168.1.2:3128",
    "Home WiFi": "127.0.0.1:8888"
  }
}
```

Notes:
- Keys under `rules` are SSID names (case sensitive as reported by Windows).
- Proxy format is `host:port` (do not include `http://` or `https://`).
- The script sets WinHTTP to `http=host:port;https=host:port` and WinINET to `host:port`.

---

## Installation

1. Save the script as `proxy-manager.ps1` in a directory of your choice (ideally one on your PATH).
2. If your execution policy blocks scripts, allow local scripts (one-time):
   ```powershell
   Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
   ```
   Or run ad‑hoc with:
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\proxy-manager.ps1 ...
   ```
3. For WinHTTP changes, run PowerShell as Administrator.

---

## Quick Start

- Add a rule for a Wi‑Fi network (SSID with spaces must be quoted):
  ```powershell
  .\proxy-manager.ps1 add "CorpNet" "10.0.0.10:8080"
  ```
- Set a default proxy (used when no SSID‑specific rule exists):
  ```powershell
  .\proxy-manager.ps1 default "10.0.0.10:8080"
  ```
- Apply for current SSID (once, immediate):
  ```powershell
  .\proxy-manager.ps1 auto
  ```
- Start background monitor (checks every 2 seconds):
  ```powershell
  .\proxy-manager.ps1 background
  ```
  Stop it later:
  ```powershell
  Get-Job -Name AutoProxy | Stop-Job
  Get-Job -Name AutoProxy | Remove-Job
  ```
- Interactive TUI:
  ```powershell
  .\proxy-manager.ps1 tui
  ```

---

## Command Reference

The script accepts up to three parameters:
- `Action` (required): command name
- `SSID` (optional): Wi‑Fi SSID used by some commands
- `Proxy` (optional): proxy in `host:port` format

Actions:

- `add <SSID> <proxy:port>`
  - Adds or updates a per‑SSID proxy rule.
  - Example:
    ```powershell
    .\proxy-manager.ps1 add "GuestWiFi" "192.168.1.2:3128"
    ```

- `remove <SSID>`
  - Removes a per‑SSID proxy rule.
  - Example:
    ```powershell
    .\proxy-manager.ps1 remove "GuestWiFi"
    ```

- `default <proxy:port>`
  - Sets the default proxy used when no SSID rule matches.
  - Example:
    ```powershell
    .\proxy-manager.ps1 default "10.0.0.10:8080"
    ```

- `auto`
  - Detects the current SSID and applies, in order:
    1) the matching SSID rule
    2) the default proxy
    3) or resets to direct connection (no proxy)

- `list`
  - Displays configured rules, default proxy, and currently visible Wi‑Fi networks.

- `show-current`
  - Displays current WinHTTP and WinINET proxy settings.

- `background`
  - Starts a background job (`AutoProxy`) that monitors SSID changes every two seconds and applies rules.

- `tui`
  - Launches an interactive text UI to add/edit rules and set a default proxy.

- No or unknown `Action`
  - Prints a help summary of available commands.

---

<img width="955" height="912" alt="TUI" src="https://github.com/user-attachments/assets/63ab35dd-2055-44f5-b25b-a600c87ad447" />
<img width="955" height="912" alt="TUI" src="https://github.com/user-attachments/assets/e93a6ae1-1148-444e-8d79-ff25a9f046cf" />
<img width="1305" height="610" alt="log" src="https://github.com/user-attachments/assets/22401dda-9745-44d3-968d-26c18ed250f4" />




## Interactive TUI

The TUI offers:
- View/Edit existing networks
- Add new network rule (select from visible networks or enter SSID manually)
- Set default proxy
- View all rules and visible SSIDs

Use quoted SSIDs when they include spaces. Proxy values must be `host:port`.

---

## Background Mode

- Starts a PowerShell background job named `AutoProxy`.
- Polls the current SSID every 2 seconds and applies:
  - SSID rule if present,
  - otherwise the default,
  - otherwise resets to direct (no proxy).
- Logs status transitions to `%USERPROFILE%\.proxy_manager.log`.

Manage the job:
```powershell
# Check status
Get-Job -Name AutoProxy

# Stop and remove
Stop-Job -Name AutoProxy
Remove-Job -Name AutoProxy
```

---

## How It Works

- SSID detection:
  - Uses `netsh wlan show interfaces` to get the currently connected SSID.
  - Uses `netsh wlan show networks` to list visible SSIDs.
- Proxy application:
  - WinHTTP proxy set via `netsh winhttp set proxy "http=...;https=..." bypass-list="localhost"`.
  - WinINET (per‑user) proxy updated under `HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings`:
    - `ProxyEnable`, `ProxyServer`, `ProxyOverride` (defaults to `localhost;<local>`).
  - Triggers system notification via `InternetSetOption` (wininet.dll) to make changes effective immediately.
- State:
  - Configuration stored in `%USERPROFILE%\.proxy_config.json`.
  - Logging appended to `%USERPROFILE%\.proxy_manager.log`.

---

## Required Permissions

- WinINET changes (per‑user registry) do not require elevation.
- WinHTTP changes require an elevated PowerShell session (Run as Administrator). If not elevated:
  - WinHTTP calls may fail silently or report errors.
  - WinINET settings will still be applied.

To ensure full functionality, run:
- The first time (to establish WinHTTP behavior): as Administrator.
- Background mode as Administrator if you want WinHTTP changes to apply to system services.

---

## Troubleshooting

- Permission denied / “Access is denied” when setting WinHTTP:
  - Run PowerShell as Administrator.
- “No SSID detected”:
  - Not connected to Wi‑Fi (Ethernet‑only), WLAN disabled, or no active interface.
- Background job already exists:
  - Stop and remove the existing job:
    ```powershell
    Stop-Job -Name AutoProxy
    Remove-Job -Name AutoProxy
    ```
- Changes not reflected in apps:
  - Some apps cache proxy settings; restart the application.
- Reset to direct connection (no proxy):
  - Either disconnect Wi‑Fi and run:
    ```powershell
    .\proxy-manager.ps1 auto
    ```
  - Or manually reset:
    ```powershell
    # WinHTTP (Admin required)
    netsh winhttp reset proxy

    # WinINET (per-user)
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings" -Name ProxyEnable -Value 0
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings" -Name ProxyServer -Value ""
    ```
- Add additional bypasses (besides `localhost;<local>`):
  - Not currently configurable via CLI/TUI. You can extend the script or manually set `ProxyOverride` in the registry.

---

## Security Considerations

- The configuration file is stored in your user profile in plain text. Avoid storing credentials in proxy addresses.
- If your environment requires authenticated proxies, prefer system credential managers or PAC files; this script does not manage credentials.
- Use administrative sessions only when needed.

---

## Uninstall / Cleanup

1. Stop and remove background job:
   ```powershell
   Stop-Job -Name AutoProxy -ErrorAction SilentlyContinue
   Remove-Job -Name AutoProxy -ErrorAction SilentlyContinue
   ```
2. Reset proxies to direct connection:
   ```powershell
   netsh winhttp reset proxy
   Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings" -Name ProxyEnable -Value 0
   Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings" -Name ProxyServer -Value ""
   ```
3. Delete configuration and log files (optional):
   ```powershell
   Remove-Item "$env:USERPROFILE\.proxy_config.json" -ErrorAction SilentlyContinue
   Remove-Item "$env:USERPROFILE\.proxy_manager.log" -ErrorAction SilentlyContinue
   ```

---

## Notes and Limitations

- SSID matching is string‑based; ensure the SSID string matches exactly.
- Only Wi‑Fi SSIDs are considered; Ethernet scenarios require manual control (e.g., default proxy or manual invocation).
- Poll interval in background mode is fixed at 2 seconds.
- Visible SSIDs are discovered via `netsh`; corporate policies may restrict this.
- Multiple WLAN interfaces are not explicitly handled and may yield unpredictable SSID detection if more than one is active.

---
