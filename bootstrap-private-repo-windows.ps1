<#
Public-safe Windows bootstrap for a private MonrealIT MIT repo.

Intended use:
- Host this single file somewhere public
- Keep the main MIT-AI repository private
- Users run this file; it installs Git/GitHub CLI if needed, authenticates to GitHub,
  clones/updates the private repo, then runs install-monrealit-ai-wsl.ps1 from that private checkout

Example:
  powershell -ExecutionPolicy Bypass -Command "iwr https://raw.githubusercontent.com/mitdsmith/MIT-AI-Bootstrap/main/bootstrap-private-repo-windows.ps1 -UseBasicParsing | iex"
#>

[CmdletBinding()]
param(
    [string]$RepoUrl = "https://github.com/Monreal-IT/MIT-AI.git",
    [string]$RepoBranch = "main",
    [string]$CheckoutDir = "$env:USERPROFILE\MIT-AI",
    [string]$Distro = "Ubuntu-24.04",
    [string]$LinuxUser = "",
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
        "C:\Program Files\Git\cmd\git.exe",
        "C:\Program Files (x86)\Git\bin\git.exe",
        "C:\Program Files (x86)\Git\cmd\git.exe",
        (Join-Path $env:LOCALAPPDATA "Programs\Git\bin\git.exe"),
        (Join-Path $env:LOCALAPPDATA "Programs\Git\cmd\git.exe")
    )

    foreach ($candidate in $pathCandidates) {
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path $candidate)) {
            return $candidate
        }
    }

    $searchRoots = @(
        $env:ProgramFiles,
        ${env:ProgramFiles(x86)},
        $env:LOCALAPPDATA
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) -and (Test-Path $_) }

    foreach ($root in $searchRoots) {
        $match = Get-ChildItem -Path $root -Filter git.exe -File -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -match '\\Git\\(cmd|bin)\\git\.exe$' } |
            Select-Object -First 1
        if ($match) {
            return $match.FullName
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

    $helperOutput = & $GitExe config --global credential.helper 2>$null
    $helper = if ($null -eq $helperOutput) { "" } else { [string]$helperOutput }
    $helper = $helper.Trim()
    if ([string]::IsNullOrWhiteSpace($helper)) {
        Write-Step "Configuring Git credential storage"
        Invoke-Git $GitExe config --global credential.helper store
    }
}

function Get-GhCommand {
    $candidates = @(
        (Get-Command gh -ErrorAction SilentlyContinue),
        (Get-Command gh.exe -ErrorAction SilentlyContinue)
    ) | Where-Object { $null -ne $_ }

    if ($candidates) {
        return $candidates[0].Source
    }

    $pathCandidates = @(
        "C:\Program Files\GitHub CLI\gh.exe",
        (Join-Path $env:LOCALAPPDATA "Programs\GitHub CLI\gh.exe")
    )

    foreach ($candidate in $pathCandidates) {
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path $candidate)) {
            return $candidate
        }
    }

    return $null
}

function Ensure-GhInstalled {
    $ghExe = Get-GhCommand
    if ($ghExe) {
        return $ghExe
    }

    if (-not (Get-Command winget.exe -ErrorAction SilentlyContinue)) {
        return $null
    }

    Write-Step "Installing GitHub CLI"
    & winget.exe install --id GitHub.cli -e --source winget --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0) {
        return $null
    }

    return (Get-GhCommand)
}

function Ensure-GitHubAuth {
    param([Parameter(Mandatory = $true)][string]$GitExe)

    $ghExe = Ensure-GhInstalled
    if ($ghExe) {
        & $ghExe auth status 1>$null 2>$null
        if ($LASTEXITCODE -ne 0) {
            Write-Step "Signing in to GitHub via browser"
            Write-Host "A browser/device login flow should open. Sign in there, then return here."
            & $ghExe auth login --hostname github.com --git-protocol https --web
            if ($LASTEXITCODE -ne 0) {
                throw "GitHub CLI login failed."
            }
        }

        Write-Step "Configuring Git to use GitHub CLI credentials"
        & $ghExe auth setup-git
        if ($LASTEXITCODE -ne 0) {
            throw "GitHub CLI could not configure git credentials."
        }
        return
    }

    Ensure-GitCredentialHelper -GitExe $GitExe
    Write-Step "Cloning private MIT-AI repository"
    Write-Host "GitHub CLI is unavailable, so git will prompt for credentials."
    Write-Host "Enter your GitHub username and paste a GitHub Personal Access Token (PAT) as the password."
    Write-Host "Create a token here if needed: https://github.com/settings/tokens/new"
    Write-Host "Recommended scopes for this private repo flow: repo and read:org"
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
    Invoke-Git $GitExe clone --branch $Branch $Repo $Destination
}

$git = Ensure-GitInstalled
if ([string]::IsNullOrWhiteSpace($git)) {
    throw "Git could not be located after installation. Reopen PowerShell and rerun this bootstrap."
}
Ensure-GitHubAuth -GitExe $git
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
if (-not [string]::IsNullOrWhiteSpace($LinuxUser)) {
    $installArgs.LinuxUser = $LinuxUser
}
if ($SkipVSCodeInstall) {
    $installArgs.SkipVSCodeInstall = $true
}

& $repoInstaller @installArgs
if ($LASTEXITCODE -ne 0) {
    throw "install-monrealit-ai-wsl.ps1 failed."
}
