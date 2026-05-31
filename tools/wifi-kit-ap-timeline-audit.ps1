<#
Wifi-Kit AP Recovery timeline audit for Windows.

DryRun is the default. Real execution requires both:
  -Run -ConfirmText "RUN WIFI-KIT AP AUDIT"

The script does not delete Wi-Fi profiles, flush DNS, reboot, restart
NetworkManager, or modify the Pi beyond calling the existing Wifi-Kit SAFE
wrapper actions requested by the operator.

Network model: the Windows Wi-Fi adapter is used only to join the Wifi-Kit
recovery AP. Access back to the main Flint/LAN side is validated with ping/SSH
to the Pi main IP, normally through Ethernet/RJ45. This script never connects
Windows to the Flint SSID.
#>

[CmdletBinding()]
param(
    [switch]$Run,
    [string]$ConfirmText = "",
    [string]$PiMainIp = "192.168.8.163",
    [string]$PiApIp = "192.168.50.1",
    [string]$SshUser = "warzy",
    [string]$SshIdentityFile = "",
    [string]$SshKnownHostsFile = "",
    [string]$MainSsid = "GL-MT6000-d53",
    [string]$ApSsid = "Wifi-Kit-rpi0-node",
    [ValidateSet("Auto", "Main", "ApAlreadyActive")]
    [string]$StartState = "Auto",
    [int]$TimeoutSeconds = 180,
    [int]$PollSeconds = 2,
    [string]$ReportDir = "reports",
    [string]$WrapperPath = "/opt/seed-kit/wifi-kit/wifi-kit-action-wrapper.sh",
    [string]$NmApLabPath = "/opt/seed-kit/wifi-kit/wifi-kit-nm-ap-lab.sh"
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = "Stop"

$RequiredConfirmation = "RUN WIFI-KIT AP AUDIT"
$IsDryRun = -not $Run

if ($Run -and $ConfirmText -ne $RequiredConfirmation) {
    throw "Real run refused. Pass -Run -ConfirmText `"$RequiredConfirmation`" exactly."
}

$script:StartedAt = Get-Date
$script:Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
$script:Timeline = New-Object System.Collections.Generic.List[object]
$script:Errors = New-Object System.Collections.Generic.List[string]
$script:Metrics = [ordered]@{}
foreach ($metricName in @(
    "ssid_visible_seconds",
    "association_seconds",
    "dhcp_seconds",
    "ping_ap_seconds",
    "http80_seconds",
    "http54321_seconds",
    "ssh_ap_seconds",
    "return_main_seconds"
)) {
    $script:Metrics[$metricName] = $null
}
$script:StartStateResolved = "unknown"
$script:MainSshInitialOk = $null
$script:ApSsidVisibleInitial = $null
$script:ApSshInitialOk = $null
$script:SkippedStartApMode = $false
$script:StartReason = ""
$script:LastSshError = ""
$script:ApReachable = $null
$script:Http80Available = $null
$script:RecoveryUi54321Reachable = $null
$script:SshServiceAnswered = $null
$script:SshAuthOk = $null
$script:ReturnDefaultNetworkSkippedSafely = $false

function Get-ElapsedSeconds {
    return [Math]::Round($script:Stopwatch.Elapsed.TotalSeconds, 3)
}

function Add-TimelineEvent {
    param(
        [string]$Name,
        [string]$Status,
        [string]$Detail = ""
    )
    $event = [ordered]@{
        elapsed_seconds = Get-ElapsedSeconds
        time_local = (Get-Date).ToString("o")
        name = $Name
        status = $Status
        detail = $Detail
    }
    $script:Timeline.Add([pscustomobject]$event) | Out-Null
    $line = "[{0,8:N3}s] {1}: {2}" -f $event.elapsed_seconds, $Name, $Status
    if ($Detail) {
        $line = "$line - $Detail"
    }
    Write-Host $line
}

function Add-Metric {
    param(
        [string]$Name,
        [Nullable[Double]]$Value
    )
    $script:Metrics[$Name] = $Value
}

function Add-AuditError {
    param([string]$Message)
    $script:Errors.Add($Message) | Out-Null
    Add-TimelineEvent -Name "error" -Status "failed" -Detail $Message
}

function Test-Tool {
    param([string]$Name)
    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    if ($null -eq $cmd) {
        Add-AuditError "Missing required tool: $Name"
        return $false
    }
    Add-TimelineEvent -Name "prerequisite" -Status "ok" -Detail "$Name -> $($cmd.Source)"
    return $true
}

function Invoke-LoggedCommand {
    param(
        [string]$Name,
        [string]$FilePath,
        [string[]]$Arguments
    )
    $display = "$FilePath $($Arguments -join ' ')"
    if ($IsDryRun) {
        Add-TimelineEvent -Name $Name -Status "dry-run" -Detail $display
        return [pscustomobject]@{ ExitCode = 0; Output = ""; DryRun = $true }
    }

    Add-TimelineEvent -Name $Name -Status "running" -Detail $display
    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $output = & $FilePath @Arguments 2>&1
        $exitCode = if ($LASTEXITCODE -is [int]) { $LASTEXITCODE } else { 0 }
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    $summary = ($output | Select-Object -First 5) -join " | "
    Add-TimelineEvent -Name $Name -Status "exit-$exitCode" -Detail $summary
    return [pscustomobject]@{ ExitCode = $exitCode; Output = ($output -join "`n"); DryRun = $false }
}

function Get-SshBaseArguments {
    param([string]$TargetHost)
    $args = @(
        "-o", "BatchMode=yes",
        "-o", "StrictHostKeyChecking=no",
        "-o", "ConnectTimeout=5"
    )
    if ($SshKnownHostsFile) {
        $args += @("-o", "UserKnownHostsFile=$SshKnownHostsFile")
    }
    if ($SshIdentityFile) {
        $args += @("-o", "IdentitiesOnly=yes", "-i", $SshIdentityFile)
    }
    $args += "$SshUser@$TargetHost"
    return $args
}

function Wait-Until {
    param(
        [string]$Name,
        [scriptblock]$Condition,
        [int]$Timeout = $TimeoutSeconds
    )
    if ($IsDryRun) {
        Add-TimelineEvent -Name $Name -Status "dry-run" -Detail "would poll for up to $Timeout seconds"
        Add-Metric -Name $Name -Value $null
        return $true
    }

    $deadline = (Get-Date).AddSeconds($Timeout)
    while ((Get-Date) -lt $deadline) {
        try {
            $result = & $Condition
            if ($result) {
                $elapsed = Get-ElapsedSeconds
                Add-Metric -Name $Name -Value $elapsed
                Add-TimelineEvent -Name $Name -Status "ok" -Detail "$elapsed seconds"
                return $true
            }
        }
        catch {
            Add-TimelineEvent -Name $Name -Status "poll-error" -Detail $_.Exception.Message
        }
        Start-Sleep -Seconds $PollSeconds
    }

    Add-Metric -Name $Name -Value $null
    Add-AuditError "$Name timed out after $Timeout seconds"
    return $false
}

function Get-NetshInterfacesText {
    $result = Invoke-LoggedCommand -Name "netsh-wlan-interfaces" -FilePath "netsh.exe" -Arguments @("wlan", "show", "interfaces")
    return $result.Output
}

function Test-VisibleSsid {
    param([string]$Ssid)
    $result = Invoke-LoggedCommand -Name "netsh-wlan-networks" -FilePath "netsh.exe" -Arguments @("wlan", "show", "networks", "mode=bssid")
    return ($result.Output -match [Regex]::Escape($Ssid))
}

function Test-AssociatedSsid {
    param([string]$Ssid)
    $text = Get-NetshInterfacesText
    return ($text -match [Regex]::Escape($Ssid))
}

function Test-DhcpApAddress {
    param([string]$Prefix)
    $result = Invoke-LoggedCommand -Name "ipconfig" -FilePath "ipconfig.exe" -Arguments @("/all")
    return ($result.Output -match [Regex]::Escape($Prefix))
}

function Test-PingHost {
    param([string]$TargetHost)
    $result = Invoke-LoggedCommand -Name "ping-$TargetHost" -FilePath "ping.exe" -Arguments @("-n", "1", "-w", "1000", $TargetHost)
    return ($result.ExitCode -eq 0)
}

function Test-TcpPort {
    param(
        [string]$TargetHost,
        [int]$Port,
        [int]$TimeoutMs = 1000
    )
    if ($IsDryRun) {
        Add-TimelineEvent -Name "tcp-$TargetHost-$Port" -Status "dry-run" -Detail "would connect with ${TimeoutMs}ms timeout"
        return $true
    }

    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $iar = $client.BeginConnect($TargetHost, $Port, $null, $null)
        $ok = $iar.AsyncWaitHandle.WaitOne($TimeoutMs, $false)
        if (-not $ok) {
            return $false
        }
        $client.EndConnect($iar)
        return $client.Connected
    }
    catch {
        return $false
    }
    finally {
        $client.Close()
    }
}

function Test-SshHost {
    param([string]$TargetHost)
    $script:LastSshError = ""
    $args = Get-SshBaseArguments -TargetHost $TargetHost
    $args += "true"
    $result = Invoke-LoggedCommand -Name "ssh-$TargetHost" -FilePath "ssh.exe" -Arguments $args
    if ($result.ExitCode -ne 0) {
        $script:LastSshError = $result.Output
    }
    return ($result.ExitCode -eq 0)
}

function Wait-ForSshHost {
    param(
        [string]$Name,
        [string]$TargetHost,
        [int]$Timeout = $TimeoutSeconds
    )
    if ($IsDryRun) {
        Add-TimelineEvent -Name $Name -Status "dry-run" -Detail "would poll SSH for up to $Timeout seconds"
        Add-Metric -Name $Name -Value $null
        return $true
    }

    $deadline = (Get-Date).AddSeconds($Timeout)
    while ((Get-Date) -lt $deadline) {
        if (Test-SshHost -TargetHost $TargetHost) {
            $script:SshServiceAnswered = $true
            $script:SshAuthOk = $true
            $elapsed = Get-ElapsedSeconds
            Add-Metric -Name $Name -Value $elapsed
            Add-TimelineEvent -Name $Name -Status "ok" -Detail "$elapsed seconds"
            return $true
        }

        if ($script:LastSshError -match "Permission denied") {
            $script:SshServiceAnswered = $true
            $script:SshAuthOk = $false
            Add-Metric -Name $Name -Value $null
            Add-AuditError "$Name authentication failed for $SshUser@$TargetHost; return-default-network is not allowed without SSH auth."
            Add-TimelineEvent -Name $Name -Status "auth-failed" -Detail "SSH service answered but authentication failed."
            return $false
        }

        Start-Sleep -Seconds $PollSeconds
    }

    Add-Metric -Name $Name -Value $null
    Add-AuditError "$Name timed out after $Timeout seconds"
    return $false
}

function Invoke-RemoteSudoCommand {
    param(
        [string]$Name,
        [string]$TargetHost,
        [string]$Command
    )
    $args = Get-SshBaseArguments -TargetHost $TargetHost
    $args += "sudo -n $Command"
    return Invoke-LoggedCommand -Name $Name -FilePath "ssh.exe" -Arguments $args
}

function Invoke-RemoteCommand {
    param(
        [string]$Name,
        [string]$TargetHost,
        [string]$Command
    )
    $args = Get-SshBaseArguments -TargetHost $TargetHost
    $args += $Command
    return Invoke-LoggedCommand -Name $Name -FilePath "ssh.exe" -Arguments $args
}

function Invoke-RemoteSudoCommandDetached {
    param(
        [string]$Name,
        [string]$TargetHost,
        [string]$Command
    )
    $remoteLog = "/tmp/wifi-kit-ap-timeline-$Name.log"
    $remoteCommand = "nohup sudo -n $Command >$remoteLog 2>&1 </dev/null &"
    $args = Get-SshBaseArguments -TargetHost $TargetHost
    $args += $remoteCommand
    return Invoke-LoggedCommand -Name $Name -FilePath "ssh.exe" -Arguments $args
}

function Test-WifiProfileKnown {
    param([string]$Ssid)
    $result = Invoke-LoggedCommand -Name "netsh-profile-$Ssid" -FilePath "netsh.exe" -Arguments @(
        "wlan",
        "show",
        "profile",
        "name=$Ssid"
    )
    return ($result.ExitCode -eq 0)
}

function Invoke-CurlGet {
    param(
        [string]$Name,
        [string]$Url
    )
    $result = Invoke-LoggedCommand -Name $Name -FilePath "curl.exe" -Arguments @(
        "--max-time", "5",
        "-sS",
        "--output", "NUL",
        "-w", " time_connect=%{time_connect} time_starttransfer=%{time_starttransfer} time_total=%{time_total} http_code=%{http_code}",
        $Url
    )
    return ($result.ExitCode -eq 0)
}

function Test-HttpHead {
    param(
        [string]$Name,
        [string]$Url
    )
    $result = Invoke-LoggedCommand -Name $Name -FilePath "curl.exe" -Arguments @(
        "--max-time", "2",
        "-sS",
        "-I",
        $Url
    )
    return ($result.ExitCode -eq 0)
}

function Write-Report {
    New-Item -ItemType Directory -Force -Path $ReportDir | Out-Null
    $stamp = $script:StartedAt.ToString("yyyyMMdd-HHmmss-fff")
    $stateLabel = $StartState.ToLowerInvariant()
    $path = Join-Path $ReportDir "wifi-kit-ap-timeline-$stamp-$stateLabel.json"
    $report = [ordered]@{
        dry_run = $IsDryRun
        started_at = $script:StartedAt.ToString("o")
        finished_at = (Get-Date).ToString("o")
        config = [ordered]@{
            pi_main_ip = $PiMainIp
            pi_ap_ip = $PiApIp
            ssh_user = $SshUser
            ssh_identity_file = $SshIdentityFile
            ssh_known_hosts_file = $SshKnownHostsFile
            main_network_label = $MainSsid
            main_network_access = "external LAN path, typically Ethernet/RJ45; Windows Wi-Fi is not connected to this SSID"
            ap_ssid = $ApSsid
            start_state_requested = $StartState
            timeout_seconds = $TimeoutSeconds
            poll_seconds = $PollSeconds
            wrapper_path = $WrapperPath
            nm_ap_lab_path = $NmApLabPath
        }
        start_state = $script:StartStateResolved
        main_ssh_initial_ok = $script:MainSshInitialOk
        ap_ssid_visible_initial = $script:ApSsidVisibleInitial
        ap_ssh_initial_ok = $script:ApSshInitialOk
        skipped_start_ap_mode = $script:SkippedStartApMode
        reason = $script:StartReason
        health = [ordered]@{
            ap_reachable = $script:ApReachable
            http80_available = $script:Http80Available
            recovery_ui_54321_reachable = $script:RecoveryUi54321Reachable
            ssh_service_answered = $script:SshServiceAnswered
            ssh_auth_ok = $script:SshAuthOk
            return_default_network_skipped_safely = $script:ReturnDefaultNetworkSkippedSafely
        }
        metrics = $script:Metrics
        timeline = $script:Timeline
        errors = $script:Errors
    }
    $report | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 -Path $path
    Write-Host ""
    Write-Host "Report: $path"
}

Add-TimelineEvent -Name "mode" -Status $(if ($IsDryRun) { "dry-run" } else { "run" }) -Detail "Use -Run -ConfirmText `"$RequiredConfirmation`" for real execution."

$toolsOk = $true
foreach ($tool in @("ssh.exe", "netsh.exe", "curl.exe", "ipconfig.exe", "ping.exe")) {
    if (-not (Test-Tool $tool)) {
        $toolsOk = $false
    }
}

if (-not $toolsOk) {
    Write-Report
    throw "Missing prerequisites."
}

if ($SshIdentityFile) {
    if (Test-Path -LiteralPath $SshIdentityFile) {
        Add-TimelineEvent -Name "ssh-identity" -Status "ok" -Detail $SshIdentityFile
    }
    else {
        Add-AuditError "SSH identity file does not exist: $SshIdentityFile"
        Write-Report
        throw "Missing SSH identity file."
    }
}

if ($SshKnownHostsFile) {
    $knownHostsParent = Split-Path -Parent $SshKnownHostsFile
    if ($knownHostsParent) {
        New-Item -ItemType Directory -Force -Path $knownHostsParent | Out-Null
    }
    Add-TimelineEvent -Name "ssh-known-hosts" -Status "isolated" -Detail $SshKnownHostsFile
}

Add-TimelineEvent -Name "t0" -Status "started" -Detail "AP recovery timeline audit"
Add-TimelineEvent -Name "network-model" -Status "info" -Detail "Windows Wi-Fi is reserved for $ApSsid; main network access is validated by ping/SSH to $PiMainIp, typically over Ethernet/RJ45. The script does not connect Windows to $MainSsid."

$shouldStartApMode = $false

if ($IsDryRun) {
    switch ($StartState) {
        "Auto" {
            $script:StartStateResolved = "auto-dry-run"
            $script:StartReason = "DryRun only: would probe main SSH first, then AP SSID/profile if main is unavailable."
            $shouldStartApMode = $true
            Add-TimelineEvent -Name "start-state" -Status "dry-run" -Detail "Auto branch options: Main starts AP; ApAlreadyActive skips start-ap-mode and connects to AP."
        }
        "Main" {
            $script:StartStateResolved = "main"
            $script:StartReason = "Forced by -StartState Main."
            $shouldStartApMode = $true
            Add-TimelineEvent -Name "start-state" -Status "dry-run" -Detail $script:StartReason
        }
        "ApAlreadyActive" {
            $script:StartStateResolved = "ap-already-active"
            $script:SkippedStartApMode = $true
            $script:StartReason = "Forced by -StartState ApAlreadyActive."
            Add-TimelineEvent -Name "start-state" -Status "dry-run" -Detail "AP already active branch: start-ap-mode skipped."
        }
    }
}
else {
    switch ($StartState) {
        "Main" {
            $script:MainSshInitialOk = Test-SshHost -TargetHost $PiMainIp
            if (-not $script:MainSshInitialOk) {
                $script:StartStateResolved = "refused"
                $script:StartReason = "Forced Main state but SSH to $PiMainIp failed."
                Add-AuditError $script:StartReason
                Write-Report
                throw $script:StartReason
            }
            $script:StartStateResolved = "main"
            $script:StartReason = "Forced Main state and SSH to $PiMainIp is reachable."
            $shouldStartApMode = $true
        }
        "ApAlreadyActive" {
            $script:StartStateResolved = "ap-already-active"
            $script:SkippedStartApMode = $true
            $script:StartReason = "Forced AP already active state; start-ap-mode skipped."
        }
        "Auto" {
            $script:MainSshInitialOk = Test-SshHost -TargetHost $PiMainIp
            if ($script:MainSshInitialOk) {
                $script:StartStateResolved = "main"
                $script:StartReason = "Auto detected SSH to $PiMainIp; starting AP from main network."
                $shouldStartApMode = $true
            }
            else {
                $script:ApSsidVisibleInitial = Test-VisibleSsid -Ssid $ApSsid
                $apProfileKnown = Test-WifiProfileKnown -Ssid $ApSsid
                if ($script:ApSsidVisibleInitial -or $apProfileKnown) {
                    $script:StartStateResolved = "ap-already-active-candidate"
                    $script:SkippedStartApMode = $true
                    $script:StartReason = "Auto did not reach $PiMainIp; AP SSID visible or Windows profile exists, so start-ap-mode is skipped."
                }
                else {
                    $script:StartStateResolved = "refused"
                    $script:StartReason = "Neither main SSH nor AP SSID/profile is available."
                    Add-AuditError $script:StartReason
                    Write-Report
                    throw $script:StartReason
                }
            }
        }
    }
    Add-TimelineEvent -Name "start-state" -Status $script:StartStateResolved -Detail $script:StartReason
}

if ($shouldStartApMode) {
    $startResult = Invoke-RemoteSudoCommandDetached -Name "pi-start-ap-mode" -TargetHost $PiMainIp -Command "$WrapperPath start-ap-mode"
    if ((-not $IsDryRun) -and $startResult.ExitCode -ne 0) {
        Add-AuditError "start-ap-mode failed with exit code $($startResult.ExitCode)"
        Write-Report
        throw "start-ap-mode failed"
    }
}
else {
    $script:SkippedStartApMode = $true
    Add-TimelineEvent -Name "pi-start-ap-mode" -Status "skipped" -Detail "Initial state is AP already active."
}

$ssidVisibleOk = $false
$apProfileKnownForConnect = Test-WifiProfileKnown -Ssid $ApSsid
if ($script:SkippedStartApMode -and $apProfileKnownForConnect) {
    Add-TimelineEvent -Name "ssid_visible_seconds" -Status "skipped" -Detail "AP already active path uses the known Windows profile before trusting flaky scan visibility."
    Add-Metric -Name "ssid_visible_seconds" -Value $null
    $ssidVisibleOk = $true
}
else {
    $ssidVisibleOk = Wait-Until -Name "ssid_visible_seconds" -Condition { Test-VisibleSsid -Ssid $ApSsid }
}

Invoke-LoggedCommand -Name "windows-disconnect-wifi" -FilePath "netsh.exe" -Arguments @(
    "wlan", "disconnect"
) | Out-Null
if (-not $IsDryRun) {
    Start-Sleep -Seconds 2
}

Invoke-LoggedCommand -Name "windows-connect-ap" -FilePath "netsh.exe" -Arguments @(
    "wlan", "connect", "name=$ApSsid"
) | Out-Null

$associatedOk = $false
$dhcpOk = $false
$pingApOk = $false
$sshApOk = $false

if ($ssidVisibleOk) {
    $associatedOk = Wait-Until -Name "association_seconds" -Condition { Test-AssociatedSsid -Ssid $ApSsid }
}
else {
    Add-AuditError "AP SSID was not visible; association skipped."
}

if ($associatedOk) {
    $dhcpOk = Wait-Until -Name "dhcp_seconds" -Condition { Test-DhcpApAddress -Prefix "192.168.50." }
}
else {
    Add-AuditError "Windows did not associate to $ApSsid; AP network tests skipped."
}

if ($dhcpOk) {
    $pingApOk = Wait-Until -Name "ping_ap_seconds" -Condition { Test-PingHost -TargetHost $PiApIp }
    if (-not $IsDryRun) {
        $script:ApReachable = $pingApOk
    }
}
else {
    Add-AuditError "Windows did not get a 192.168.50.x address; AP service tests skipped."
}

if ($pingApOk) {
    $http80Ok = Wait-Until -Name "http80_seconds" -Condition { Test-HttpHead -Name "http80-probe" -Url "http://$PiApIp/" }
    if (-not $IsDryRun) {
        $script:Http80Available = $http80Ok
    }
    $http54321Ok = Wait-Until -Name "http54321_seconds" -Condition { Test-HttpHead -Name "http54321-probe" -Url "http://${PiApIp}:54321/" }
    if (-not $IsDryRun) {
        $script:RecoveryUi54321Reachable = $http54321Ok
    }

    if ($http80Ok) {
        Invoke-CurlGet -Name "curl-root" -Url "http://$PiApIp/" | Out-Null
        Invoke-CurlGet -Name "curl-connecttest" -Url "http://$PiApIp/connecttest.txt" | Out-Null
        Invoke-CurlGet -Name "curl-generate-204" -Url "http://$PiApIp/generate_204" | Out-Null
        Invoke-CurlGet -Name "curl-hotspot-detect" -Url "http://$PiApIp/hotspot-detect.html" | Out-Null
    }
    else {
        Add-TimelineEvent -Name "captive-probes" -Status "skipped" -Detail "HTTP 80 is unavailable; captive endpoint probes would only repeat the same timeout."
    }

    if ($http54321Ok) {
        Invoke-CurlGet -Name "curl-full-ui" -Url "http://${PiApIp}:54321/" | Out-Null
    }
    else {
        Add-TimelineEvent -Name "curl-full-ui" -Status "skipped" -Detail "HTTP 54321 is unavailable."
    }

    $sshApOk = Wait-ForSshHost -Name "ssh_ap_seconds" -TargetHost $PiApIp
}
else {
    Add-AuditError "AP gateway $PiApIp did not answer ping; HTTP and SSH AP tests skipped."
}
$script:ApSshInitialOk = $sshApOk

if ($sshApOk) {
    Invoke-RemoteCommand -Name "pi-ap-status" -TargetHost $PiApIp -Command "hostname; ip -brief addr show wlan0 2>/dev/null; ss -ltn 2>/dev/null" | Out-Null
    Invoke-RemoteSudoCommand -Name "pi-return-default-network" -TargetHost $PiApIp -Command "$WrapperPath return-default-network" | Out-Null
}
else {
    $script:ReturnDefaultNetworkSkippedSafely = $true
    Add-AuditError "SSH AP did not become available; return-default-network skipped."
    Add-TimelineEvent -Name "pi-return-default-network" -Status "skipped" -Detail "SSH AP was not confirmed."
}

Invoke-LoggedCommand -Name "windows-disconnect-ap" -FilePath "netsh.exe" -Arguments @(
    "wlan", "disconnect"
) | Out-Null
Add-TimelineEvent -Name "windows-main-network" -Status "not-managed" -Detail "No Wi-Fi connection to $MainSsid is attempted; waiting for $PiMainIp through the existing LAN path."

Wait-Until -Name "return_main_seconds" -Condition { (Test-PingHost -TargetHost $PiMainIp) -and (Test-SshHost -TargetHost $PiMainIp) } | Out-Null

Write-Report

if ($script:Errors.Count -gt 0) {
    exit 1
}
