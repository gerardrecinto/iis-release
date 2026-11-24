BeforeAll {
    Import-Module (Join-Path $PSScriptRoot '..' 'src' 'IisRelease' 'IisRelease.psm1') -Force
}

Describe 'Publish-IisRelease' {
    BeforeEach {
        $script:root = Join-Path $TestDrive 'releases'
        New-Item -ItemType Directory -Path (Join-Path $script:root 'old') -Force | Out-Null
        $src = Join-Path $TestDrive 'src'
        New-Item -ItemType Directory -Path $src -Force | Out-Null
        Set-Content -Path (Join-Path $src 'index.html') -Value 'v2'
        $script:zip = Join-Path $TestDrive 'v2.zip'
        Compress-Archive -Path (Join-Path $src '*') -DestinationPath $script:zip -Force
        $script:previous = Join-Path $script:root 'old'
        $prev = $script:previous
        Mock -ModuleName IisRelease Get-SitePath -MockWith ([scriptblock]::Create("'$prev'"))
        Mock -ModuleName IisRelease Set-SitePath {}
        Mock -ModuleName IisRelease Restart-Pool {}
        Mock -ModuleName IisRelease Start-Sleep {}
    }

    It 'switches the site to the new folder when health is 200' {
        Mock -ModuleName IisRelease Invoke-WebRequest { [pscustomobject]@{ StatusCode = 200 } }
        $r = Publish-IisRelease -SiteName s -AppPoolName p -PackagePath $script:zip -ReleaseRoot $script:root -HealthUrl 'http://x/health' -ReleaseId 'r2'
        $r.Status | Should -Be 'Deployed'
        Test-Path (Join-Path $script:root 'r2' 'index.html') | Should -BeTrue
        Should -Invoke -ModuleName IisRelease Set-SitePath -Times 1 -Exactly
    }

    It 'puts the previous folder back and throws when health never returns 200' {
        Mock -ModuleName IisRelease Invoke-WebRequest { throw 'boom' }
        { Publish-IisRelease -SiteName s -AppPoolName p -PackagePath $script:zip -ReleaseRoot $script:root -HealthUrl 'http://x/health' -ReleaseId 'r2' -Retries 2 } |
            Should -Throw '*Rolled back*'
        Should -Invoke -ModuleName IisRelease Set-SitePath -Times 2 -Exactly
        Should -Invoke -ModuleName IisRelease Set-SitePath -Times 1 -Exactly -ParameterFilter { $Path -like '*old' }
        Test-Path (Join-Path $script:root 'r2') | Should -BeFalse
    }

    It 'retries before giving up' {
        Mock -ModuleName IisRelease Invoke-WebRequest { throw 'boom' }
        { Publish-IisRelease -SiteName s -AppPoolName p -PackagePath $script:zip -ReleaseRoot $script:root -HealthUrl 'http://x/health' -ReleaseId 'r2' -Retries 3 } | Should -Throw
        Should -Invoke -ModuleName IisRelease Invoke-WebRequest -Times 3 -Exactly
    }

    It 'fails fast when the package is missing' {
        { Publish-IisRelease -SiteName s -AppPoolName p -PackagePath (Join-Path $TestDrive 'nope.zip') -ReleaseRoot $script:root -HealthUrl 'http://x/health' } |
            Should -Throw '*Package not found*'
    }
}

Describe 'Remove-OldRelease' {
    It 'keeps the newest N folders and never removes a protected one' {
        $root = Join-Path $TestDrive 'prune'
        1..5 | ForEach-Object { New-Item -ItemType Directory -Path (Join-Path $root "r$_") -Force | Out-Null }
        Remove-OldRelease -ReleaseRoot $root -Keep 2 -Protect @((Join-Path $root 'r1'))
        (Get-ChildItem $root -Directory).Name | Sort-Object | Should -Be @('r1', 'r4', 'r5')
    }
}
