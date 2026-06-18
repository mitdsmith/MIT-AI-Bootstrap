<#
Public-safe Windows bootstrap for a private MonrealIT MIT repo.

Intended use:
- Host this single file somewhere public
- Keep the main MIT-AI repository private
- Users run this file; it installs Git if needed, clones/updates the private repo,
  then runs install-monrealit-ai-wsl.ps1 from that private checkout

Example:
  powershell -ExecutionPolicy Bypass -Command "iwr https://raw.githubusercontent.com/mitdsmith/MIT-AI-Bootstrap/main/bootstrap-private-repo-windows.ps1 -UseBasicParsing | iex"
#>

[CmdletBinding()]
param(
    [string]$RepoUrl = "https://github.com/Monreal-IT/MIT-AI.git",
    [string]$RepoBranch = "main",
    [string]$CheckoutDir = "$env:USERPROFILE\MIT-AI",
    [string]$Distro = "Ubuntu-24.04",
    [switch]$SkipVSCodeInstall
)

$ErrorActionPreference = "Stop"

function Write-Step {
    param([string]$Message)
    Write-Host ""
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Get-GitCommand {
    $candidates = @(
        (Get-Command git -ErrorAction SilentlyContinue),
        (Get-Command git.exe -ErrorAction SilentlyContinue)
    ) | Where-Object { $null -ne $_ }

    if ($candidates) {
        return $candidates[0].Source
    }

    $pathCandidates = @(
        "C:\Program Files\Git\bin\git.exe",
        "C:\Program Files\Git\cmd\git.exe"
    )

    foreach ($candidate in $pathCandidates) {
        if (Test-Path $candidate) {
            return $candidate
        }
    }

    return $null
}

function Invoke-Git {
    param(
        [Parameter(Mandatory = $true)][string]$GitExe,
        [Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments
    )

    & $GitExe @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "git command failed with exit code ${LASTEXITCODE}: $GitExe $($Arguments -join ' ')"
    }
}

function Ensure-GitInstalled {
    $gitExe = Get-GitCommand
    if ($gitExe) {
        return $gitExe
    }

    if (-not (Get-Command winget.exe -ErrorAction SilentlyContinue)) {
        throw "Git is not installed and winget.exe is unavailable. Install Git manually, then rerun this bootstrap."
    }

    Write-Step "Installing Git"
    & winget.exe install --id Git.Git -e --source winget --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to install Git with winget."
    }

    $gitExe = Get-GitCommand
    if (-not $gitExe) {
        throw "Git was installed, but the executable could not be located. Reopen PowerShell and rerun this bootstrap."
    }

    return $gitExe
}

function Ensure-GitCredentialHelper {
    param([Parameter(Mandatory = $true)][string]$GitExe)

    $helper = (& $GitExe config --global credential.helper 2>$null).Trim()
    if ([string]::IsNullOrWhiteSpace($helper)) {
        Write-Step "Configuring Git credential storage"
        Invoke-Git $GitExe config --global credential.helper store
    }
}

function Sync-PrivateRepo {
    param(
        [Parameter(Mandatory = $true)][string]$GitExe,
        [Parameter(Mandatory = $true)][string]$Repo,
        [Parameter(Mandatory = $true)][string]$Branch,
        [Parameter(Mandatory = $true)][string]$Destination
    )

    $parentDir = Split-Path -Parent $Destination
    if (-not [string]::IsNullOrWhiteSpace($parentDir)) {
        New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
    }

    if (Test-Path (Join-Path $Destination ".git")) {
        Write-Step "Updating existing MIT-AI checkout"
        Invoke-Git $GitExe -C $Destination remote set-url origin $Repo
        Invoke-Git $GitExe -C $Destination fetch --prune origin
        Invoke-Git $GitExe -C $Destination checkout $Branch
        Invoke-Git $GitExe -C $Destination reset --hard ("origin/{0}" -f $Branch)
        return
    }

    if (Test-Path $Destination) {
        throw "Checkout path already exists and is not a git repo: $Destination"
    }

    Write-Step "Cloning private MIT-AI repository"
    Write-Host "If prompted, enter your GitHub username and paste a PAT token as the password."
    Invoke-Git $GitExe clone --branch $Branch $Repo $Destination
}

$git = Ensure-GitInstalled
Ensure-GitCredentialHelper -GitExe $git
Sync-PrivateRepo -GitExe $git -Repo $RepoUrl -Branch $RepoBranch -Destination $CheckoutDir

$repoInstaller = Join-Path $CheckoutDir "install-monrealit-ai-wsl.ps1"
if (-not (Test-Path $repoInstaller)) {
    throw "install-monrealit-ai-wsl.ps1 was not found in $CheckoutDir"
}

Write-Step "Running MonrealIT installer from private repo"
$installArgs = @{
    Distro = $Distro
    WrapperRepoUrl = $RepoUrl
    WrapperRepoBranch = $RepoBranch
}
if ($SkipVSCodeInstall) {
    $installArgs.SkipVSCodeInstall = $true
}

& $repoInstaller @installArgs
if ($LASTEXITCODE -ne 0) {
    throw "install-monrealit-ai-wsl.ps1 failed."
}
