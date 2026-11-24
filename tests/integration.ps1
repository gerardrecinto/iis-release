# Real IIS test. Runs on a Windows runner: installs IIS, deploys v1, v2, then a bad build.
# The bad build has no health.html, so the health check must fail and v2 must keep serving.
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..' 'src' 'IisRelease' 'IisRelease.psm1') -Force

Install-WindowsFeature -Name Web-Server -IncludeManagementTools | Out-Null
Import-Module WebAdministration

$root = 'C:\iislab'
$releases = Join-Path $root 'releases'
$pkgs = Join-Path $root 'packages'
New-Item -ItemType Directory -Path $releases, $pkgs -Force | Out-Null

function New-Package($name, $body, [bool]$withHealth) {
    $dir = Join-Path $pkgs "src-$name"
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    Set-Content -Path (Join-Path $dir 'index.html') -Value $body
    if ($withHealth) { Set-Content -Path (Join-Path $dir 'health.html') -Value 'ok' }
    $zip = Join-Path $pkgs "$name.zip"
    Compress-Archive -Path (Join-Path $dir '*') -DestinationPath $zip -Force
    $zip
}

$v1 = New-Package 'v1' 'version-1' $true
$v2 = New-Package 'v2' 'version-2' $true
$bad = New-Package 'bad' 'version-bad' $false

$initial = Join-Path $releases '00000000000000000-initial'
New-Item -ItemType Directory -Path $initial -Force | Out-Null
Expand-Archive -Path $v1 -DestinationPath $initial -Force

New-WebAppPool -Name 'lab' | Out-Null
New-Website -Name 'lab' -Port 8080 -PhysicalPath $initial -ApplicationPool 'lab' | Out-Null

$url = 'http://localhost:8080'
function Get-Body { (Invoke-WebRequest -Uri "$url/" -UseBasicParsing).Content.Trim() }

$results = [System.Collections.Generic.List[string]]::new()
function Assert-Equal($actual, $expected, $label) {
    if ($actual -ne $expected) { throw "$label : expected '$expected' but got '$actual'" }
    $results.Add("| $label | $actual |")
}

Assert-Equal (Get-Body) 'version-1' 'initial site'

$r = Publish-IisRelease -SiteName 'lab' -AppPoolName 'lab' -PackagePath $v2 -ReleaseRoot $releases -HealthUrl "$url/health.html" -Retries 5 -DelaySeconds 1
Assert-Equal $r.Status 'Deployed' 'deploy v2 status'
Assert-Equal (Get-Body) 'version-2' 'site after v2'

$failed = $false
try {
    Publish-IisRelease -SiteName 'lab' -AppPoolName 'lab' -PackagePath $bad -ReleaseRoot $releases -HealthUrl "$url/health.html" -Retries 3 -DelaySeconds 1 | Out-Null
}
catch { $failed = $true; $msg = $_.Exception.Message }
Assert-Equal $failed $true 'bad build rejected'
Assert-Equal (Get-Body) 'version-2' 'site after rollback'
Assert-Equal ($msg -like '*Rolled back*') $true 'error says rolled back'

$summary = "### IIS release test on Windows`n`n| Check | Result |`n|---|---|`n" + ($results -join "`n")
Write-Host $summary
if ($env:GITHUB_STEP_SUMMARY) { Add-Content -Path $env:GITHUB_STEP_SUMMARY -Value $summary }
