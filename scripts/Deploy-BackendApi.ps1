<#
.SYNOPSIS
    Builds and deploys the backend Contoso.IdentityApi to an Azure App Service Web App using 'az webapp deploy'.

.DESCRIPTION
    Simplest possible deployment script (no publish profile, no slots, no Kudu REST calls directly). 
    Relies on Azure CLI for authentication and deployment. Produces a ZIP via 'dotnet publish' output and
    calls 'az webapp deploy --type zip'.

.PARAMETER WebAppName
    The Azure Web App name OR full host (e.g. contoso-api-dev.azurewebsites.net). If a host is supplied,
    only the left-most label is used as the Web App name.

.PARAMETER ResourceGroup
    The resource group containing the target Web App.

.PARAMETER ProjectPath
    Path (relative or absolute) to the .csproj of the API. Defaults to backend/Contoso.IdentityApi/Contoso.IdentityApi.csproj

.PARAMETER Configuration
    Build configuration (Release/Debug). Default: Release.

.PARAMETER Framework
    Optional target framework (e.g. net8.0). If omitted, the project default is used.

.PARAMETER PublishDir
    Optional explicit publish directory. If not provided a timestamped directory under bin/DeployPublish is created.

.PARAMETER ZipPath
    Optional explicit path for the generated ZIP. If omitted, an artifacts directory is created and a timestamped file used.

.PARAMETER SkipBuild
    Skip dotnet publish (assumes PublishDir already populated OR ZipPath provided pointing to a valid zip).

.PARAMETER ZipOnly
    Create (or reuse) the ZIP but do not deploy it.

.PARAMETER Force
    Overwrite existing ZIP if paths collide.

.PARAMETER Verbose
    Standard PowerShell -Verbose flag for additional output.

.EXAMPLE
    ./scripts/Deploy-BackendApi.ps1 -WebAppName contoso-transit-api-dev-eba5fcfughcfg0c0 -ResourceGroup rg-contoso-dev

.EXAMPLE
    ./scripts/Deploy-BackendApi.ps1 -WebAppName contoso-transit-api-dev-eba5fcfughcfg0c0.australiaeast-01.azurewebsites.net -ResourceGroup rg-contoso-dev -Verbose

.NOTES
    Requires: Azure CLI (az) logged in (az login) and correct subscription set.
    The script intentionally avoids advanced features (slots, warm-up, retries) for simplicity.
#>
[CmdletBinding()] param(
    [Parameter(Mandatory=$true)][string]$WebAppName,
    [Parameter(Mandatory=$true)][string]$ResourceGroup,
    [string]$ProjectPath = "backend/Contoso.IdentityApi/Contoso.IdentityApi.csproj",
    [string]$Configuration = "Release",
    [string]$Framework,
    [string]$PublishDir,
    [string]$ZipPath,
    [switch]$SkipBuild,
    [switch]$ZipOnly,
    [switch]$Force
    # NOTE: Do NOT declare a Verbose parameter; -Verbose is a built-in common parameter via CmdletBinding
)

$ErrorActionPreference = 'Stop'
function Write-Section($msg){ Write-Host "`n=== $msg ===" -ForegroundColor Cyan }
function Write-Warn($msg){ Write-Warning $msg }
function Fail($msg){ Write-Error $msg; exit 1 }

Write-Section 'Normalize WebApp name'
if($WebAppName -match '\.azurewebsites\.net$'){
    $parsed = $WebAppName.Split('.')[0]
    Write-Host "Parsed WebAppName '$WebAppName' -> '$parsed'" -ForegroundColor DarkGray
    $WebAppName = $parsed
}

Write-Section 'Validate tooling'
if(-not (Get-Command az -ErrorAction SilentlyContinue)) { Fail "Azure CLI (az) is not installed or not on PATH." }
try { az account show 1>$null 2>$null } catch { Fail "You are not logged in. Run 'az login' first." }
if(-not (Get-Command dotnet -ErrorAction SilentlyContinue)) { Fail ".NET SDK (dotnet) not found." }

# Resolve paths relative to repo root (script directory's parent)
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent $scriptRoot
$fullProjectPath = Resolve-Path -Path (Join-Path $repoRoot $ProjectPath) -ErrorAction Stop

Write-Host "Project: $fullProjectPath" -ForegroundColor DarkGray

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'

if(-not $PublishDir){
    $publishBase = Join-Path (Split-Path $fullProjectPath -Parent) "bin/DeployPublish"
    if(-not (Test-Path $publishBase)){ New-Item -ItemType Directory -Path $publishBase | Out-Null }
    $PublishDir = Join-Path $publishBase "$Configuration-$timestamp"
}
if(-not (Test-Path $PublishDir)){ New-Item -ItemType Directory -Path $PublishDir | Out-Null }

if(-not $SkipBuild){
    Write-Section 'dotnet publish'
    $publishArgs = @('publish', $fullProjectPath, '-c', $Configuration, '-o', $PublishDir)
    if($Framework){ $publishArgs += @('-f', $Framework) }
    Write-Host "dotnet $($publishArgs -join ' ')" -ForegroundColor DarkGray
    dotnet @publishArgs | Write-Verbose
} else {
    Write-Warn "SkipBuild specified – assuming publish output already exists at $PublishDir"
    if(-not (Test-Path (Join-Path $PublishDir '*'))){ Fail "PublishDir appears empty: $PublishDir" }
}

if(-not $ZipPath){
    $artifacts = Join-Path $repoRoot 'artifacts'
    if(-not (Test-Path $artifacts)){ New-Item -ItemType Directory -Path $artifacts | Out-Null }
    $zipFileName = "Contoso.IdentityApi-$timestamp.zip"
    $ZipPath = Join-Path $artifacts $zipFileName
}

Write-Section 'Packaging ZIP'
if((Test-Path $ZipPath) -and -not $Force){ Fail "ZIP already exists at $ZipPath (use -Force to overwrite)." }
if(Test-Path $ZipPath){ Remove-Item $ZipPath -Force }
# Compress the CONTENTS of publish directory (not the directory name itself)
$items = Get-ChildItem -LiteralPath $PublishDir
if(-not $items){ Fail "No files found in publish directory: $PublishDir" }
Compress-Archive -Path (Join-Path $PublishDir '*') -DestinationPath $ZipPath -Force
Write-Host "Created ZIP: $ZipPath" -ForegroundColor Green

if($ZipOnly){
    Write-Host "ZipOnly specified – skipping deployment." -ForegroundColor Yellow
    Write-Host "Artifact: $ZipPath"
    exit 0
}

Write-Section 'Deploying'
# Validate sentinel always (good early failure) for backend
$dllName = 'Contoso.IdentityApi.dll'
if(-not (Test-Path (Join-Path $PublishDir $dllName))){ Fail "Sentinel file '$dllName' not found in publish output at $PublishDir. Publish may have failed." }
 $deployArgs = @('webapp','deploy','--resource-group', $ResourceGroup,'--name', $WebAppName,'--src-path', $ZipPath,'--type','zip','--restart','true')
 Write-Host "az $($deployArgs -join ' ')" -ForegroundColor DarkGray
 az @deployArgs

Write-Section 'Summary'
Write-Host "Web App:    $WebAppName" -ForegroundColor Gray
Write-Host "ResourceGp: $ResourceGroup" -ForegroundColor Gray
Write-Host "Zip:        $ZipPath" -ForegroundColor Gray
Write-Host "PublishDir: $PublishDir" -ForegroundColor Gray
Write-Host "Done." -ForegroundColor Green
