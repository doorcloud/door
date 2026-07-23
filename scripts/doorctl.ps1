param(
    [string]$Version,
    [string]$InstallDir,
    [switch]$NoPathUpdate
)

# doorctl installer
# Run with:
#   irm https://raw.githubusercontent.com/doorcloud/door/main/scripts/doorctl.ps1 | iex
#   .\doorctl.ps1 -Version v2.5.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Owner = 'doorcloud'
$Repository = 'door'
$Binary = 'doorctl'
$GitHubApiUrl = "https://api.github.com/repos/$Owner/$Repository"

function Write-InstallInfo {
    param([string]$Message)
    Write-Host $Message -ForegroundColor Cyan
}

function Write-InstallSuccess {
    param([string]$Message)
    Write-Host $Message -ForegroundColor Green
}

function Write-InstallWarning {
    param([string]$Message)
    Write-Host "Warning: $Message" -ForegroundColor Yellow
}

function Write-InstallError {
    param([string]$Message)
    Write-Host "Error: $Message" -ForegroundColor Red
}

function Resolve-DoorctlVersion {
    if (-not [string]::IsNullOrWhiteSpace($Version)) {
        return $Version.Trim()
    }

    if (-not [string]::IsNullOrWhiteSpace($env:DOORCTL_VERSION)) {
        return $env:DOORCTL_VERSION.Trim()
    }

    Write-InstallInfo "Resolving the latest $Binary release..."
    try {
        $headers = @{
            Accept = 'application/vnd.github+json'
            'User-Agent' = 'doorctl-installer'
        }
        $release = Invoke-RestMethod `
            -Uri "$GitHubApiUrl/releases/latest" `
            -Headers $headers `
            -UseBasicParsing

        if ([string]::IsNullOrWhiteSpace([string]$release.tag_name)) {
            throw 'The GitHub response did not include a release tag.'
        }

        return [string]$release.tag_name
    }
    catch {
        $details = $_.Exception.Message
        throw "Failed to resolve the latest $Binary release from GitHub. The API may be rate-limited or unavailable, or this computer may be offline. Set DOORCTL_VERSION to a specific tag and try again. Details: $details"
    }
}

function Get-NormalizedPathEntry {
    param([string]$PathEntry)

    if ([string]::IsNullOrWhiteSpace($PathEntry)) {
        return ''
    }

    $expandedPath = [Environment]::ExpandEnvironmentVariables($PathEntry.Trim().Trim('"'))
    try {
        $expandedPath = [IO.Path]::GetFullPath($expandedPath)
    }
    catch {
        # Keep non-filesystem PATH entries comparable without blocking installation.
    }

    return $expandedPath.TrimEnd(
        [IO.Path]::DirectorySeparatorChar,
        [IO.Path]::AltDirectorySeparatorChar
    )
}

function Test-PathContains {
    param(
        [string]$PathValue,
        [string]$Directory
    )

    $normalizedDirectory = Get-NormalizedPathEntry $Directory
    foreach ($entry in @($PathValue -split ';')) {
        if ((Get-NormalizedPathEntry $entry) -ieq $normalizedDirectory) {
            return $true
        }
    }

    return $false
}

function Add-ToUserPath {
    param([string]$Directory)

    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    if (Test-PathContains -PathValue $userPath -Directory $Directory) {
        return $false
    }

    $trimmedUserPath = ([string]$userPath).Trim().TrimEnd(';')
    $newUserPath = if ([string]::IsNullOrWhiteSpace($trimmedUserPath)) {
        $Directory
    }
    else {
        "$trimmedUserPath;$Directory"
    }

    [Environment]::SetEnvironmentVariable('Path', $newUserPath, 'User')
    return $true
}

$temporaryDirectory = $null
$pathUpdated = $false

try {
    $resolvedVersion = Resolve-DoorctlVersion

    $resolvedInstallDir = if (-not [string]::IsNullOrWhiteSpace($InstallDir)) {
        $InstallDir.Trim()
    }
    elseif (-not [string]::IsNullOrWhiteSpace($env:DOORCTL_INSTALL_DIR)) {
        $env:DOORCTL_INSTALL_DIR.Trim()
    }
    else {
        if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
            throw 'LOCALAPPDATA is not set. Set DOORCTL_INSTALL_DIR to choose an installation directory.'
        }
        Join-Path $env:LOCALAPPDATA 'Programs\doorctl'
    }
    $resolvedInstallDir = [IO.Path]::GetFullPath(
        [Environment]::ExpandEnvironmentVariables($resolvedInstallDir)
    )

    $skipPathUpdate = $NoPathUpdate.IsPresent -or
        -not [string]::IsNullOrWhiteSpace($env:DOORCTL_NO_PATH_UPDATE)

    $architecture = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') {
        'arm64'
    }
    else {
        'x86_64'
    }

    $archiveName = "${Binary}_Windows_${architecture}.zip"
    $releaseUrl = "https://github.com/$Owner/$Repository/releases/download/$resolvedVersion"
    $archiveUrl = "$releaseUrl/$archiveName"
    $checksumsUrl = "$releaseUrl/checksums.txt"

    $temporaryDirectory = Join-Path ([IO.Path]::GetTempPath()) (
        "doorctl-install-{0}" -f [Guid]::NewGuid().ToString('N')
    )
    New-Item -ItemType Directory -Path $temporaryDirectory | Out-Null

    $archivePath = Join-Path $temporaryDirectory $archiveName
    $checksumsPath = Join-Path $temporaryDirectory 'checksums.txt'
    $extractPath = Join-Path $temporaryDirectory 'extracted'

    Write-InstallInfo "Downloading $Binary $resolvedVersion for Windows $architecture..."
    try {
        Invoke-WebRequest -Uri $archiveUrl -OutFile $archivePath -UseBasicParsing
    }
    catch {
        throw "Failed to download $archiveUrl. Details: $($_.Exception.Message)"
    }

    try {
        Invoke-WebRequest -Uri $checksumsUrl -OutFile $checksumsPath -UseBasicParsing
    }
    catch {
        throw "Failed to download $checksumsUrl. Details: $($_.Exception.Message)"
    }

    $escapedArchiveName = [Regex]::Escape($archiveName)
    $checksumText = Get-Content -LiteralPath $checksumsPath -Raw
    $checksumMatch = [Regex]::Match(
        $checksumText,
        "(?im)^([0-9a-f]{64})\s+\*?$escapedArchiveName\s*$"
    )
    if (-not $checksumMatch.Success) {
        throw "Checksum for $archiveName was not found in checksums.txt."
    }

    $expectedHash = $checksumMatch.Groups[1].Value.ToUpperInvariant()
    $actualHash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToUpperInvariant()
    if ($actualHash -cne $expectedHash) {
        throw "Checksum verification failed for $archiveName.`n  expected: $expectedHash`n  actual:   $actualHash"
    }
    Write-InstallSuccess 'Checksum verified.'

    Expand-Archive -LiteralPath $archivePath -DestinationPath $extractPath -Force
    $extractedBinary = Join-Path $extractPath 'doorctl.exe'
    if (-not (Test-Path -LiteralPath $extractedBinary -PathType Leaf)) {
        throw "$archiveName did not contain doorctl.exe."
    }

    New-Item -ItemType Directory -Path $resolvedInstallDir -Force | Out-Null
    $installedBinary = Join-Path $resolvedInstallDir 'doorctl.exe'
    Copy-Item -LiteralPath $extractedBinary -Destination $installedBinary -Force

    if ($skipPathUpdate) {
        Write-InstallWarning 'PATH modification was skipped.'
    }
    else {
        $pathUpdated = Add-ToUserPath -Directory $resolvedInstallDir

        if (-not (Test-PathContains -PathValue $env:Path -Directory $resolvedInstallDir)) {
            $trimmedSessionPath = ([string]$env:Path).TrimEnd(';')
            $env:Path = if ([string]::IsNullOrWhiteSpace($trimmedSessionPath)) {
                $resolvedInstallDir
            }
            else {
                "$trimmedSessionPath;$resolvedInstallDir"
            }
        }

        if ($pathUpdated) {
            Write-InstallWarning 'Other already-open terminals must be restarted to use the updated PATH.'
        }
    }

    $verificationOutput = & $installedBinary version 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-InstallWarning "'doorctl version' failed; checking the installation with 'doorctl --help'."
        $verificationOutput = & $installedBinary --help 2>&1
    }

    Write-Host ''
    Write-InstallSuccess "$Binary $resolvedVersion installed successfully"
    Write-Host "  install directory: $resolvedInstallDir"
    Write-Host "  architecture:      Windows $architecture"
    Write-Host "  PATH updated:      $pathUpdated"
    if ($verificationOutput) {
        Write-Host "  verification:      $($verificationOutput | Select-Object -First 1)"
    }
    Write-Host ''
    Write-Host 'Next steps:'
    Write-Host '  doorctl config --server-url <YOUR_DOOR_URL> --organization <YOUR_ORG>'
}
catch {
    Write-InstallError $_.Exception.Message
    throw
}
finally {
    if ($null -ne $temporaryDirectory -and (Test-Path -LiteralPath $temporaryDirectory)) {
        Remove-Item -LiteralPath $temporaryDirectory -Recurse -Force -ErrorAction SilentlyContinue
    }
}
