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
.PARAMETER ConditionalForwarding
    If specified, enables Conditional Forwarding to resolve local client/device names
.PARAMETER RouterIp
    Router / DHCP server IP for Conditional Forwarding (auto-detected if omitted)
.PARAMETER LocalSubnet
    Local subnet in CIDR notation (e.g. 192.168.1.0/24)
.PARAMETER LocalDomain
    Local domain name (default: lan)
.EXAMPLE
    .\deploy.ps1
.EXAMPLE
    .\deploy.ps1 -Hostname 192.168.1.100 -User pi -InstallPihole -InstallUpdateLists
.EXAMPLE
    .\deploy.ps1 -Hostname pi.hole -User rpi4b-admin -ConditionalForwarding
.EXAMPLE
    .\deploy.ps1 -Hostname pi.hole -User rpi4b-admin -PiholePassword "MySecurePass123"
#>
[CmdletBinding()]
param(
    [string]$Hostname = "pi.hole",
    [string]$User = "rpi4b-admin",
    [switch]$InstallPihole,
    [switch]$InstallUpdateLists,
    [switch]$OptimizeSDCard,
    [string]$OptimizationProfile = "extreme",
    [string]$PiholePassword = "",
    [switch]$ConditionalForwarding,
    [string]$RouterIp = "",
    [string]$LocalSubnet = "",
    [string]$LocalDomain = "lan"
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$configDir = Join-Path $scriptDir "config"
$scriptsDir = Join-Path $scriptDir "scripts"

$customLists = Join-Path $configDir "custom-blocklists.list"
$customBlacklist = Join-Path $configDir "custom-blacklist.list"
$customAllowlists = Join-Path $configDir "custom-allowlists.list"
$indiaWhitelist = Join-Path $configDir "india-whitelist.list"
$indiaRegexBlacklist = Join-Path $configDir "india-regex-blacklist.list"
$indiaRegexWhitelist = Join-Path $configDir "india-regex-whitelist.list"
$confFile = Join-Path $configDir "pihole-updatelists.conf"
$cloudConfFile = Join-Path $configDir "pihole-cloud-updater.conf.example"
$updaterPy = Join-Path $scriptsDir "pihole-cloud-updater.py"
$updaterSh = Join-Path $scriptsDir "pihole-cloud-updater"
$installPiholeSh = Join-Path $scriptsDir "install-pihole.sh"
$installUpdateListsSh = Join-Path $scriptsDir "install-pihole-updatelists.sh"
$condFwdSh = Join-Path $scriptsDir "configure-conditional-forwarding.sh"
$optimizeSdSh = Join-Path $scriptsDir "optimize-sd-card.sh"
$optimizationDir = Join-Path $scriptsDir "optimization"

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  Remote Pi-hole Deployment to ${User}@${Hostname}" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

# 1. Transfer files to /tmp/ via SCP
Write-Host "[*] Uploading configuration and updater files to ${Hostname}:/tmp/ ..." -ForegroundColor Yellow
scp $customLists "${User}@${Hostname}:/tmp/custom-blocklists.list"
if (Test-Path $customBlacklist) { scp $customBlacklist "${User}@${Hostname}:/tmp/custom-blacklist.list" }
if (Test-Path $customAllowlists) { scp $customAllowlists "${User}@${Hostname}:/tmp/custom-allowlists.list" }
if (Test-Path $indiaWhitelist) { scp $indiaWhitelist "${User}@${Hostname}:/tmp/india-whitelist.list" }
if (Test-Path $indiaRegexBlacklist) { scp $indiaRegexBlacklist "${User}@${Hostname}:/tmp/india-regex-blacklist.list" }
if (Test-Path $indiaRegexWhitelist) { scp $indiaRegexWhitelist "${User}@${Hostname}:/tmp/india-regex-whitelist.list" }
scp $confFile "${User}@${Hostname}:/tmp/pihole-updatelists.conf"
if (Test-Path $cloudConfFile) { scp $cloudConfFile "${User}@${Hostname}:/tmp/pihole-cloud-updater.conf.example" }
if (Test-Path $updaterPy) { scp $updaterPy "${User}@${Hostname}:/tmp/pihole-cloud-updater.py" }
if (Test-Path $updaterSh) { scp $updaterSh "${User}@${Hostname}:/tmp/pihole-cloud-updater" }
if (Test-Path $installPiholeSh) { scp $installPiholeSh "${User}@${Hostname}:/tmp/install-pihole.sh" }
if (Test-Path $installUpdateListsSh) { scp $installUpdateListsSh "${User}@${Hostname}:/tmp/install-pihole-updatelists.sh" }
if (Test-Path $condFwdSh) { scp $condFwdSh "${User}@${Hostname}:/tmp/configure-conditional-forwarding.sh" }
if (Test-Path $optimizeSdSh) { scp $optimizeSdSh "${User}@${Hostname}:/tmp/optimize-sd-card.sh" }
if (Test-Path $optimizationDir) {
    ssh "${User}@${Hostname}" "mkdir -p /tmp/optimization"
    scp (Get-ChildItem -Path "$optimizationDir\*.sh").FullName "${User}@${Hostname}:/tmp/optimization/"
}

# 2. Build remote command string
$commands = @()
$commands += "sudo sed -i 's/\r$//' /tmp/*.sh /tmp/optimization/*.sh /tmp/*.list /tmp/*.conf* 2>/dev/null || true"
$commands += "sudo chmod +x /tmp/*.sh /tmp/optimization/*.sh /tmp/pihole-cloud-updater 2>/dev/null || true"

# Optional: Install Pi-hole
if ($InstallPihole) {
    Write-Host "[*] Will install Pi-hole on remote host..." -ForegroundColor Yellow
    $piholeArgs = @("-y")
    if ($PiholePassword) { $piholeArgs += "-p `"$PiholePassword`"" }
    if ($ConditionalForwarding) {
        $piholeArgs += "--cf"
        if ($RouterIp) { $piholeArgs += "--router-ip `"$RouterIp`"" }
        if ($LocalSubnet) { $piholeArgs += "--local-subnet `"$LocalSubnet`"" }
        if ($LocalDomain) { $piholeArgs += "--local-domain `"$LocalDomain`"" }
    }
    $commands += "sudo /tmp/install-pihole.sh $($piholeArgs -join ' ')"
}

# Optional: Install pihole-updatelists
if ($InstallUpdateLists) {
    Write-Host "[*] Will install pihole-updatelists on remote host..." -ForegroundColor Yellow
    $commands += "sudo /tmp/install-pihole-updatelists.sh"
}

# Optional: Apply SD card longevity and hardware optimizations
if ($OptimizeSDCard) {
    Write-Host "[*] Will apply SD card & 24/7 hardware longevity optimizations (Profile: ${OptimizationProfile})..." -ForegroundColor Yellow
    $commands += "sudo /tmp/optimize-sd-card.sh -p `"${OptimizationProfile}`" -y"
}

# Core deployment of configs and updater
$commands += "sudo mkdir -p /etc/pihole /usr/local/share/pihole-cloud-updater /usr/local/sbin /var/cache/pihole-cloud-updater"
$commands += "sudo cp /tmp/custom-blocklists.list /etc/pihole/custom-blocklists.list"
$commands += "(test -f /tmp/custom-blacklist.list && sudo cp /tmp/custom-blacklist.list /etc/pihole/custom-blacklist.list && sudo chmod 644 /etc/pihole/custom-blacklist.list || true)"
$commands += "(test -f /tmp/custom-allowlists.list && sudo cp /tmp/custom-allowlists.list /etc/pihole/custom-allowlists.list || true)"
$commands += "(test -f /tmp/india-whitelist.list && sudo cp /tmp/india-whitelist.list /etc/pihole/india-whitelist.list || true)"
$commands += "(test -f /tmp/india-regex-blacklist.list && sudo cp /tmp/india-regex-blacklist.list /etc/pihole/india-regex-blacklist.list || true)"
$commands += "(test -f /tmp/india-regex-whitelist.list && sudo cp /tmp/india-regex-whitelist.list /etc/pihole/india-regex-whitelist.list || true)"
$commands += "sudo cp /tmp/pihole-updatelists.conf /etc/pihole-updatelists.conf"
$commands += "(test -f /tmp/pihole-cloud-updater.conf.example && sudo cp /tmp/pihole-cloud-updater.conf.example /etc/pihole-cloud-updater.conf || true)"
$commands += "(test -f /tmp/pihole-cloud-updater.py && sudo cp /tmp/pihole-cloud-updater.py /usr/local/share/pihole-cloud-updater/pihole-cloud-updater.py && sudo chmod 755 /usr/local/share/pihole-cloud-updater/pihole-cloud-updater.py || true)"
$commands += "(test -f /tmp/pihole-cloud-updater && sudo cp /tmp/pihole-cloud-updater /usr/local/sbin/pihole-cloud-updater && sudo chmod 755 /usr/local/sbin/pihole-cloud-updater || true)"
$commands += "sudo sqlite3 /etc/pihole/gravity.db `"DELETE FROM adlist WHERE address LIKE '%urlhaus.abuse.ch%';`" 2>/dev/null || true"

# Optional custom password set if Pi-hole is already installed
if ($PiholePassword -and -not $InstallPihole) {
    $commands += "sudo pihole -a -p `"$PiholePassword`""
}

# Optional: Enable Conditional Forwarding on existing Pi-hole
if ($ConditionalForwarding -and -not $InstallPihole) {
    Write-Host "[*] Configuring Conditional Forwarding on remote host..." -ForegroundColor Yellow
    $cfArgs = @("-y")
    if ($RouterIp) { $cfArgs += "-r `"$RouterIp`"" }
    if ($LocalSubnet) { $cfArgs += "-s `"$LocalSubnet`"" }
    if ($LocalDomain) { $cfArgs += "-d `"$LocalDomain`"" }
    $commands += "sudo /tmp/configure-conditional-forwarding.sh $($cfArgs -join ' ')"
}

# Run synchronization
$commands += "(command -v /usr/local/sbin/pihole-cloud-updater >/dev/null 2>&1 && sudo /usr/local/sbin/pihole-cloud-updater || sudo /usr/local/sbin/pihole-updatelists)"

$remoteCmd = $commands -join " && `n"

Write-Host "[*] Executing deployment on remote host..." -ForegroundColor Yellow
ssh -t "${User}@${Hostname}" $remoteCmd

Write-Host "[+] Remote deployment finished successfully!" -ForegroundColor Green
