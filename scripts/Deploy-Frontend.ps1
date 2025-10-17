<#
.SYNOPSIS
    Builds and deploys the Angular frontend to an Azure App Service Web App using ZIP deploy via Azure CLI.

.DESCRIPTION
    Minimal script mirroring the backend deployment approach. It runs npm install (unless -SkipInstall),
    builds the Angular project (unless -SkipBuild), packages the dist output into a ZIP, then executes:
        az webapp deploy --resource-group <rg> --name <webAppName> --src-path <zip> --type zip --restart true

.PARAMETER WebAppName
    Azure Web App name or full hostname (will strip .azurewebsites.net if present).

.PARAMETER ResourceGroup
    Resource group containing the target Web App.

.PARAMETER FrontendDir
    Path to the frontend root containing package.json & angular.json. Default: 'frontend'

.PARAMETER ProjectName
    Angular project name inside angular.json (defaults to angular.json defaultProject or first project if absent).

.PARAMETER Configuration
    Angular build configuration (production | development). Default: production

.PARAMETER DistPath
    Explicit dist folder path. If not provided it's resolved from angular.json (project build options outputPath) and configuration.

.PARAMETER ZipPath
    Explicit zip path. If omitted a timestamped zip is created under artifacts/.

.PARAMETER SkipInstall
    Skip npm install (assumes dependencies already restored).

.PARAMETER SkipBuild
    Skip angular build (assumes dist already prepared).

.PARAMETER ZipOnly
    Produce the ZIP artifact but do not deploy.

.PARAMETER Force
    Overwrite an existing ZIP if path conflict.

.EXAMPLE
    ./scripts/Deploy-Frontend.ps1 -WebAppName contoso-transit-frontend-dev -ResourceGroup rg-contoso

.EXAMPLE
    ./scripts/Deploy-Frontend.ps1 -WebAppName contoso-transit-frontend-dev.azurewebsites.net -ResourceGroup rg-contoso -Configuration production

.NOTES
    Requires: Node.js, npm, Angular CLI (locally or via npx), Azure CLI logged in.
#>
[CmdletBinding()] param(
    [Parameter(Mandatory=$true)][string]$WebAppName,
    [Parameter(Mandatory=$true)][string]$ResourceGroup,
    [string]$FrontendDir = 'frontend',
    [string]$ProjectName,
    [string]$Configuration = 'production',
    [string]$DistPath,
    [string]$ZipPath,
    [switch]$SkipInstall,
    [switch]$SkipBuild,
    [switch]$ZipOnly,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
function Section($t){ Write-Host "`n=== $t ===" -ForegroundColor Cyan }
function Fail($m){ Write-Error $m; exit 1 }
function Warn($m){ Write-Warning $m }

Section 'Normalize WebApp name'
if($WebAppName -match '\.azurewebsites\.net$'){
    $parsed = $WebAppName.Split('.')[0]
    Write-Host "Parsed WebAppName '$WebAppName' -> '$parsed'" -ForegroundColor DarkGray
    $WebAppName = $parsed
}

Section 'Validate tooling'
if(-not (Get-Command az -ErrorAction SilentlyContinue)){ Fail 'Azure CLI (az) not found.' }
try { az account show 1>$null 2>$null } catch { Fail 'Not logged into Azure CLI. Run az login.' }
if(-not (Get-Command npm -ErrorAction SilentlyContinue)){ Fail 'npm not found.' }

# Resolve repo root
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent $scriptRoot
$frontendPath = Join-Path $repoRoot $FrontendDir
if(-not (Test-Path (Join-Path $frontendPath 'package.json'))){ Fail "package.json not found under $frontendPath" }
$angularJsonPath = Join-Path $frontendPath 'angular.json'
if(-not (Test-Path $angularJsonPath)){ Fail "angular.json not found under $frontendPath" }

Section 'Resolve Angular project metadata'
$angularConfig = Get-Content $angularJsonPath -Raw | ConvertFrom-Json
if(-not $ProjectName){
    if($angularConfig.defaultProject){ $ProjectName = $angularConfig.defaultProject }
    else { $ProjectName = ($angularConfig.projects | Get-Member -MemberType NoteProperty | Select-Object -First 1).Name }
}
if(-not $angularConfig.projects.$ProjectName){ Fail "Project '$ProjectName' not found in angular.json" }

if(-not $DistPath){
    $projectBuild = $angularConfig.projects.$ProjectName.targets.build
    $outputPath = $projectBuild.options.outputPath
    # For simplicity both dev/prod go to same path in this config; still allow override.
    $DistPath = Join-Path $frontendPath $outputPath
}
Write-Host "ProjectName: $ProjectName" -ForegroundColor DarkGray
Write-Host "DistPath:    $DistPath" -ForegroundColor DarkGray

if(-not $SkipInstall){
    Section 'npm install'
    Push-Location $frontendPath
    npm install | Write-Verbose
    Pop-Location
} else { Warn 'Skipping npm install.' }

if(-not $SkipBuild){
    Section 'Angular build'
    Push-Location $frontendPath
    # Use npx to ensure local CLI version
    $buildCmd = "npx ng build $ProjectName --configuration $Configuration"
    Write-Host $buildCmd -ForegroundColor DarkGray
    cmd /c $buildCmd | Write-Verbose
    Pop-Location
    if(-not (Test-Path $DistPath)){ Fail "Build did not produce dist folder: $DistPath" }
} else { Warn 'Skipping build.' }

if(-not (Test-Path $DistPath)){ Fail "Dist folder not found: $DistPath" }

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
if(-not $ZipPath){
    $artifacts = Join-Path $repoRoot 'artifacts'
    if(-not (Test-Path $artifacts)){ New-Item -ItemType Directory -Path $artifacts | Out-Null }
    $ZipPath = Join-Path $artifacts "frontend-$ProjectName-$timestamp.zip"
}

Section 'Packaging ZIP'
if((Test-Path $ZipPath) -and -not $Force){ Fail "ZIP already exists at $ZipPath (use -Force to overwrite)." }
if(Test-Path $ZipPath){ Remove-Item $ZipPath -Force }
Compress-Archive -Path (Join-Path $DistPath '*') -DestinationPath $ZipPath -Force
Write-Host "Created ZIP: $ZipPath" -ForegroundColor Green

if($ZipOnly){
    Write-Host 'ZipOnly specified – skipping deploy.' -ForegroundColor Yellow
    Write-Host "Artifact: $ZipPath"
    exit 0
}

 # Ensure sentinel index.html exists always
$indexFile = Join-Path $DistPath 'index.html'
if(-not (Test-Path $indexFile)){ Fail "Sentinel 'index.html' not found in dist output: $indexFile" }
 $deployArgs = @('webapp','deploy','--resource-group',$ResourceGroup,'--name',$WebAppName,'--src-path',$ZipPath,'--type','zip','--restart','true')
 Write-Host "az $($deployArgs -join ' ')" -ForegroundColor DarkGray
 az @deployArgs

Section 'Summary'
Write-Host "Web App:     $WebAppName" -ForegroundColor Gray
Write-Host "ResourceGp:  $ResourceGroup" -ForegroundColor Gray
Write-Host "Project:     $ProjectName" -ForegroundColor Gray
Write-Host "Dist:        $DistPath" -ForegroundColor Gray
Write-Host "Zip:         $ZipPath" -ForegroundColor Gray
Write-Host 'Done.' -ForegroundColor Green
