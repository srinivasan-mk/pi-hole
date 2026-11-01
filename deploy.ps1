<#
.SYNOPSIS
    Remote deployment script for Pi-hole configuration from Windows.
.DESCRIPTION
    Transfers configuration files and deploys them to the Pi-hole host via SSH.
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
$customLists = Join-Path $configDir "custom-blocklists.list"
$confFile = Join-Path $configDir "pihole-updatelists.conf"

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  Remote Pi-hole Deployment to ${User}@${Hostname}" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

# 1. Transfer files to /tmp/ via SCP
Write-Host "[*] Uploading configuration files to ${Hostname}:/tmp/ ..." -ForegroundColor Yellow
scp $customLists "${User}@${Hostname}:/tmp/custom-blocklists.list"
scp $confFile "${User}@${Hostname}:/tmp/pihole-updatelists.conf"

# 2. Deploy and run on remote host via SSH
Write-Host "[*] Executing deployment on remote host..." -ForegroundColor Yellow
$remoteCmd = @"
sudo cp /tmp/custom-blocklists.list /etc/pihole/custom-blocklists.list && \
sudo cp /tmp/pihole-updatelists.conf /etc/pihole-updatelists.conf && \
sudo sed -i 's/\r$//' /etc/pihole/custom-blocklists.list && \
sudo sed -i 's/\r$//' /etc/pihole-updatelists.conf && \
sudo /usr/local/sbin/pihole-updatelists
"@

ssh -t "${User}@${Hostname}" $remoteCmd

Write-Host "[+] Remote deployment finished successfully!" -ForegroundColor Green

