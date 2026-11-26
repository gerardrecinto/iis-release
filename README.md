# iis-release-lab

Ship a zip to IIS, check it is healthy, and put the old version back if it is not. PowerShell module, Azure DevOps pipeline, and Terraform for Azure and AWS.

Site: https://gerardrecinto.github.io/iis-release-lab/

## What runs in CI

| Job | What it proves |
|---|---|
| Pester unit tests (Linux) | Switch on healthy, rollback on unhealthy, retries, missing package, pruning |
| Real IIS (Windows runner) | Installs IIS, deploys v1 then v2, then a bad build that must be rejected while v2 keeps serving |
| Pipeline check | Azure DevOps pipeline has dev, staging and prod in order, each depending on the last |
| Bicep and ARM | `bicep lint` is clean and `bicep/main.json` (the ARM template) matches the Bicep source |
| Terraform | `fmt`, `validate` and a Trivy scan on the Azure and AWS roots |

## Try it

```powershell
git clone https://github.com/gerardrecinto/iis-release-lab
cd iis-release-lab
Install-Module Pester -MinimumVersion 5.5.0 -Scope CurrentUser
Invoke-Pester tests/IisRelease.Tests.ps1
```

On a Windows machine with admin rights, `./tests/integration.ps1` installs IIS and runs the real deploy and rollback.

```powershell
Import-Module ./src/IisRelease/IisRelease.psm1
Publish-IisRelease -SiteName MySite -AppPoolName MyPool `
  -PackagePath .\site.zip -ReleaseRoot C:\sites\releases `
  -HealthUrl http://localhost/health.html
```

## Layout

```
src/IisRelease/        PowerShell module
tests/                 Pester tests and the Windows integration test
pipelines/             Azure DevOps pipeline and reusable deploy template
bicep/                 Same Azure platform in Bicep, plus the compiled ARM template (main.json)
terraform/azure/       Resource group, Windows web app (IIS), Function App, Service Bus, API Management, Storage
terraform/aws/         Encrypted, versioned artifact bucket
docs/                  GitHub Pages site
```

MIT licensed.
