Set-StrictMode -Version Latest

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
        try {
            $r = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 5
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

Export-ModuleMember -Function Publish-IisRelease, Test-IisHealth, Remove-OldRelease
