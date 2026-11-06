<#
.SYNOPSIS
    Remote installation script for minimal Chromium browser on Raspberry Pi OS Lite from Windows.
.DESCRIPTION
    Transfers scripts/install-chrome.sh to the Raspberry Pi via SCP and runs it via SSH.
.PARAMETER Hostname
    Hostname or IP of the Raspberry Pi (default: pi.hole)
.PARAMETER User
    SSH username (default: rpi4b-admin)
.EXAMPLE
    .\deploy-chrome.ps1
.EXAMPLE
    .\deploy-chrome.ps1 -Hostname 192.168.31.32 -User rpi4b-admin
#>
[CmdletBinding()]
param(
    [string]$Hostname = "pi.hole",
    [string]$User = "rpi4b-admin"
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$chromeScript = Join-Path $scriptDir "scripts\install-chrome.sh"

if (-not (Test-Path $chromeScript)) {
    Write-Error "Could not find $chromeScript"
    exit 1
}

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  Deploying Minimal Chromium to ${User}@${Hostname}" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

# 1. Transfer install-chrome.sh to /tmp/ via SCP
Write-Host "[*] Uploading scripts/install-chrome.sh to ${Hostname}:/tmp/ ..." -ForegroundColor Yellow
scp $chromeScript "${User}@${Hostname}:/tmp/install-chrome.sh"

# 2. Run script on remote host via SSH
Write-Host "[*] Executing installer on remote host..." -ForegroundColor Yellow
$remoteCmd = @"
sed -i 's/\r$//' /tmp/install-chrome.sh && chmod +x /tmp/install-chrome.sh && sudo /tmp/install-chrome.sh
"@

ssh -t "${User}@${Hostname}" $remoteCmd

Write-Host "[+] Chromium deployment finished successfully!" -ForegroundColor Green
Write-Host "You can now run 'chrome' or 'start-chrome' on your Raspberry Pi." -ForegroundColor Cyan
