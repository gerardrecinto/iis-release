Set-StrictMode -Version Latest

if (Get-Module -ListAvailable -Name WebAdministration) { Import-Module WebAdministration }

# Thin wrappers around the IIS cmdlets so tests can mock them on any OS.
function Get-SitePath {
    param([Parameter(Mandatory)][string]$SiteName)
    (Get-Website -Name $SiteName).physicalPath
}

function Set-SitePath {
    param([Parameter(Mandatory)][string]$SiteName, [Parameter(Mandatory)][string]$Path)
    Set-ItemProperty -Path "IIS:\Sites\$SiteName" -Name physicalPath -Value $Path
}

function Restart-Pool {
    param([Parameter(Mandatory)][string]$Name)
    Restart-WebAppPool -Name $Name
}

function Test-IisHealth {
    <#
    .SYNOPSIS
    Returns $true when the URL answers 200 within the retry budget.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Url,
        [int]$Retries = 5,
        [int]$DelaySeconds = 2
    )
    for ($i = 1; $i -le $Retries; $i++) {
        # A unique query string keeps the IIS kernel cache (http.sys) from answering with the previous release's page.
        $sep = if ($Url -match '\?') { '&' } else { '?' }
        $probe = "$Url${sep}_probe=$([guid]::NewGuid().ToString('N'))"
        try {
            $r = Invoke-WebRequest -Uri $probe -UseBasicParsing -TimeoutSec 5 -Headers @{ 'Cache-Control' = 'no-cache' }
            if ($r.StatusCode -eq 200) { return $true }
        }
        catch {
            Write-Verbose "Health attempt $i of $Retries failed: $($_.Exception.Message)"
        }
        if ($i -lt $Retries) { Start-Sleep -Seconds $DelaySeconds }
    }
    return $false
}

function Publish-IisRelease {
    <#
    .SYNOPSIS
    Unpacks a zip into a new release folder, points the IIS site at it, checks health,
    and puts the previous folder back if the check fails.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$SiteName,
        [Parameter(Mandatory)][string]$AppPoolName,
        [Parameter(Mandatory)][string]$PackagePath,
        [Parameter(Mandatory)][string]$ReleaseRoot,
        [Parameter(Mandatory)][string]$HealthUrl,
        [string]$ReleaseId = (Get-Date -Format 'yyyyMMddHHmmssfff'),
        [int]$Keep = 3,
        [int]$Retries = 5,
        [int]$DelaySeconds = 2
    )
    if (-not (Test-Path -LiteralPath $PackagePath)) { throw "Package not found: $PackagePath" }

    $target = Join-Path $ReleaseRoot $ReleaseId
    $previous = Get-SitePath -SiteName $SiteName

    New-Item -ItemType Directory -Path $target -Force | Out-Null
    Expand-Archive -Path $PackagePath -DestinationPath $target -Force

    Set-SitePath -SiteName $SiteName -Path $target
    Restart-Pool -Name $AppPoolName

    if (Test-IisHealth -Url $HealthUrl -Retries $Retries -DelaySeconds $DelaySeconds) {
        Remove-OldRelease -ReleaseRoot $ReleaseRoot -Keep $Keep -Protect @($target, $previous)
        return [pscustomobject]@{ Status = 'Deployed'; Release = $ReleaseId; Previous = $previous }
    }

    Set-SitePath -SiteName $SiteName -Path $previous
    Restart-Pool -Name $AppPoolName
    Remove-Item -LiteralPath $target -Recurse -Force
    throw "Health check failed for $HealthUrl. Rolled back to $previous."
}

function Remove-OldRelease {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ReleaseRoot,
        [int]$Keep = 3,
        [string[]]$Protect = @()
    )
    $protected = $Protect | ForEach-Object { $_.TrimEnd('\', '/') }
    Get-ChildItem -LiteralPath $ReleaseRoot -Directory |
        Sort-Object Name -Descending |
        Select-Object -Skip $Keep |
        Where-Object { $protected -notcontains $_.FullName.TrimEnd('\', '/') } |
        Remove-Item -Recurse -Force
}

function Get-HostSnapshot {
    <#
    .SYNOPSIS
    One-shot Windows host health: CPU, memory, disk, recent error events, and IIS site and pool state.
    #>
    [CmdletBinding()]
    param(
        [string]$SiteName,
        [string]$AppPoolName,
        [string]$Drive = 'C',
        [int]$EventMinutes = 15
    )
    $os = Get-CimInstance -ClassName Win32_OperatingSystem
    $disk = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='${Drive}:'"
    $cpu = (Get-Counter '\Processor(_Total)\% Processor Time' -SampleInterval 1 -MaxSamples 2).CounterSamples |
        Select-Object -Last 1 -ExpandProperty CookedValue
    $since = (Get-Date).AddMinutes(-$EventMinutes)
    $errors = @(Get-WinEvent -FilterHashtable @{ LogName = 'System', 'Application'; Level = 1, 2; StartTime = $since } -ErrorAction SilentlyContinue)
    $snap = [ordered]@{
        CpuPercent          = [math]::Round($cpu, 1)
        MemoryFreePercent   = [math]::Round(100 * $os.FreePhysicalMemory / $os.TotalVisibleMemorySize, 1)
        DiskFreePercent     = [math]::Round(100 * $disk.FreeSpace / $disk.Size, 1)
        RecentErrorEvents   = $errors.Count
        SiteState           = $null
        AppPoolState        = $null
    }
    if ($SiteName) { $snap.SiteState = (Get-Website -Name $SiteName).State }
    if ($AppPoolName) { $snap.AppPoolState = (Get-WebAppPoolState -Name $AppPoolName).Value }
    [pscustomobject]$snap
}

Export-ModuleMember -Function Publish-IisRelease, Test-IisHealth, Remove-OldRelease, Get-HostSnapshot
