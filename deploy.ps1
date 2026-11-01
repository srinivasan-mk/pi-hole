<#
.SYNOPSIS
    Remote deployment script for Pi-hole configuration and cloud updater from Windows.
.DESCRIPTION
    Transfers configuration and updater files and deploys them to the Pi-hole host via SSH.
.PARAMETER Hostname
    Hostname or IP of the Pi-hole server (default: pi.hole)
.PARAMETER User
    SSH username (default: rpi4b-admin)
.EXAMPLE
    .\deploy.ps1
.EXAMPLE
    .\deploy.ps1 -Hostname 192.168.1.100 -User pi
#>
[CmdletBinding()]
param(
    [string]$Hostname = "pi.hole",
    [string]$User = "rpi4b-admin"
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

# 2. Deploy and run on remote host via SSH
Write-Host "[*] Executing deployment on remote host..." -ForegroundColor Yellow
$remoteCmd = @"
sudo mkdir -p /etc/pihole /usr/local/share/pihole-cloud-updater /usr/local/sbin /var/cache/pihole-cloud-updater && \
sudo cp /tmp/custom-blocklists.list /etc/pihole/custom-blocklists.list && \
sudo cp /tmp/pihole-updatelists.conf /etc/pihole-updatelists.conf && \
(test -f /tmp/pihole-cloud-updater.conf.example && sudo cp /tmp/pihole-cloud-updater.conf.example /etc/pihole-cloud-updater.conf || true) && \
(test -f /tmp/pihole-cloud-updater.py && sudo cp /tmp/pihole-cloud-updater.py /usr/local/share/pihole-cloud-updater/pihole-cloud-updater.py && sudo chmod 755 /usr/local/share/pihole-cloud-updater/pihole-cloud-updater.py || true) && \
(test -f /tmp/pihole-cloud-updater && sudo cp /tmp/pihole-cloud-updater /usr/local/sbin/pihole-cloud-updater && sudo chmod 755 /usr/local/sbin/pihole-cloud-updater || true) && \
sudo sed -i 's/\r$//' /etc/pihole/custom-blocklists.list && \
sudo sed -i 's/\r$//' /etc/pihole-updatelists.conf && \
(command -v /usr/local/sbin/pihole-cloud-updater >/dev/null 2>&1 && sudo /usr/local/sbin/pihole-cloud-updater || sudo /usr/local/sbin/pihole-updatelists)
"@

ssh -t "${User}@${Hostname}" $remoteCmd

Write-Host "[+] Remote deployment finished successfully!" -ForegroundColor Green
