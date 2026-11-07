<#
.SYNOPSIS
    Remote deployment and installation script for Pi-hole and list updaters from Windows.
.DESCRIPTION
    Transfers configuration, installers, and updater files and deploys them to the Pi-hole host via SSH.
.PARAMETER Hostname
    Hostname or IP of the Pi-hole server (default: pi.hole)
.PARAMETER User
    SSH username (default: rpi4b-admin)
.PARAMETER InstallPihole
    If specified, installs Pi-hole unattended before deploying lists
.PARAMETER InstallUpdateLists
    If specified, installs jacklul's pihole-updatelists and PHP dependencies
.PARAMETER PiholePassword
    Custom password to set for Pi-hole Web Admin GUI
.EXAMPLE
    .\deploy.ps1
.EXAMPLE
    .\deploy.ps1 -Hostname 192.168.1.100 -User pi -InstallPihole -InstallUpdateLists
.EXAMPLE
    .\deploy.ps1 -Hostname pi.hole -User rpi4b-admin -PiholePassword "MySecurePass123"
#>
[CmdletBinding()]
param(
    [string]$Hostname = "pi.hole",
    [string]$User = "rpi4b-admin",
    [switch]$InstallPihole,
    [switch]$InstallUpdateLists,
    [string]$PiholePassword = ""
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$configDir = Join-Path $scriptDir "config"
$scriptsDir = Join-Path $scriptDir "scripts"

$customLists = Join-Path $configDir "custom-blocklists.list"
$confFile = Join-Path $configDir "pihole-updatelists.conf"
$cloudConfFile = Join-Path $configDir "pihole-cloud-updater.conf.example"
$updaterPy = Join-Path $scriptsDir "pihole-cloud-updater.py"
$updaterSh = Join-Path $scriptsDir "pihole-cloud-updater"
$installPiholeSh = Join-Path $scriptsDir "install-pihole.sh"
$installUpdateListsSh = Join-Path $scriptsDir "install-pihole-updatelists.sh"

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  Remote Pi-hole Deployment to ${User}@${Hostname}" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

# 1. Transfer files to /tmp/ via SCP
Write-Host "[*] Uploading configuration and updater files to ${Hostname}:/tmp/ ..." -ForegroundColor Yellow
scp $customLists "${User}@${Hostname}:/tmp/custom-blocklists.list"
scp $confFile "${User}@${Hostname}:/tmp/pihole-updatelists.conf"
if (Test-Path $cloudConfFile) { scp $cloudConfFile "${User}@${Hostname}:/tmp/pihole-cloud-updater.conf.example" }
if (Test-Path $updaterPy) { scp $updaterPy "${User}@${Hostname}:/tmp/pihole-cloud-updater.py" }
if (Test-Path $updaterSh) { scp $updaterSh "${User}@${Hostname}:/tmp/pihole-cloud-updater" }
if (Test-Path $installPiholeSh) { scp $installPiholeSh "${User}@${Hostname}:/tmp/install-pihole.sh" }
if (Test-Path $installUpdateListsSh) { scp $installUpdateListsSh "${User}@${Hostname}:/tmp/install-pihole-updatelists.sh" }

# 2. Build remote command string
$commands = @()
$commands += "sudo sed -i 's/\r$//' /tmp/*.sh /tmp/*.list /tmp/*.conf* 2>/dev/null || true"
$commands += "sudo chmod +x /tmp/*.sh /tmp/pihole-cloud-updater 2>/dev/null || true"

# Optional: Install Pi-hole
if ($InstallPihole) {
    Write-Host "[*] Will install Pi-hole on remote host..." -ForegroundColor Yellow
    $pwdArg = if ($PiholePassword) { "-p `"$PiholePassword`"" } else { "" }
    $commands += "sudo /tmp/install-pihole.sh -y $pwdArg"
}

# Optional: Install pihole-updatelists
if ($InstallUpdateLists) {
    Write-Host "[*] Will install pihole-updatelists on remote host..." -ForegroundColor Yellow
    $commands += "sudo /tmp/install-pihole-updatelists.sh"
}

# Core deployment of configs and updater
$commands += "sudo mkdir -p /etc/pihole /usr/local/share/pihole-cloud-updater /usr/local/sbin /var/cache/pihole-cloud-updater"
$commands += "sudo cp /tmp/custom-blocklists.list /etc/pihole/custom-blocklists.list"
$commands += "sudo cp /tmp/pihole-updatelists.conf /etc/pihole-updatelists.conf"
$commands += "(test -f /tmp/pihole-cloud-updater.conf.example && sudo cp /tmp/pihole-cloud-updater.conf.example /etc/pihole-cloud-updater.conf || true)"
$commands += "(test -f /tmp/pihole-cloud-updater.py && sudo cp /tmp/pihole-cloud-updater.py /usr/local/share/pihole-cloud-updater/pihole-cloud-updater.py && sudo chmod 755 /usr/local/share/pihole-cloud-updater/pihole-cloud-updater.py || true)"
$commands += "(test -f /tmp/pihole-cloud-updater && sudo cp /tmp/pihole-cloud-updater /usr/local/sbin/pihole-cloud-updater && sudo chmod 755 /usr/local/sbin/pihole-cloud-updater || true)"

# Optional custom password set if Pi-hole is already installed
if ($PiholePassword -and -not $InstallPihole) {
    $commands += "sudo pihole -a -p `"$PiholePassword`""
}

# Run synchronization
$commands += "(command -v /usr/local/sbin/pihole-cloud-updater >/dev/null 2>&1 && sudo /usr/local/sbin/pihole-cloud-updater || sudo /usr/local/sbin/pihole-updatelists)"

$remoteCmd = $commands -join " && `n"

Write-Host "[*] Executing deployment on remote host..." -ForegroundColor Yellow
ssh -t "${User}@${Hostname}" $remoteCmd

Write-Host "[+] Remote deployment finished successfully!" -ForegroundColor Green
