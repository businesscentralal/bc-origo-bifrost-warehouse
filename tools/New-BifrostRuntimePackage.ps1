<#
.SYNOPSIS
    Builds the public on-prem runtime zip for one released Bifröst product app, and checks a published one.

.DESCRIPTION
    Issue #1241 / decisions d-20261102-runtime-access, d-20261102-runtime-retention-majors,
    d-20261102-runtime-storage-identity and d-20261102-runtime-trigger-scope. Issue #1269.

    The zip is uploaded to storage account origopublic, container runtime, at
    bc<major>/<app name>/<Publisher>_<App>_runtime.zip
    and replaces the previous blob at that path. The zip holds one *_runtime.app.
    A four-part expected version must equal the manifest version. A three-part release
    tag is major.minor.build and matches any revision of that build, because AL-Go
    stamps the revision (tag 28.0.10 shipped app 28.0.10.632).

    The *_runtime.app must be a real Business Central runtime package: the output of
    Get-NAVAppRuntimePackage on a server of the matching BC version (#1269). It holds
    compiled code and no AL source. A normal .app, such as the release asset or alc output,
    carries every .al file and anyone can unzip it, so the packager refuses any input .app
    that has a .al entry. NAVX packages are validated with the Microsoft AL package reader,
    including their complete contents, runtime manifest, source paths and app identity.
    An absent ZIP signature never proves that unreadable bytes are a valid runtime package.

    -VerifyZipPath checks a downloaded runtime zip: exactly one *_runtime.app, no .al entry
    inside it, and (with -AppJsonPath and -ExpectedVersion) the manifest name, publisher
    and version. The RuntimePackage workflow runs it on the anonymous read-back, and on the
    public runtime zip of every Bifrost dependency before it installs that dependency. The
    result lists the manifest id and dependencies (ManifestId, ManifestDependencies).

    The folder is always the app name, which is what the Cloud Events example uses
    (bc28/Cloud Events/...). One rule for both sides: the publisher stores the zip under the
    app name and an app that depends on it computes the same location from the dependency's
    name and publisher (-Locate). -FolderName is accepted only when it equals the app name;
    any other folder is refused, because dependants could not find the zip there.

    -Locate checks an app identity (-LocateId, -LocateName, -LocatePublisher, -LocateVersion)
    against the strict identity rules and prints its public runtime zip location. Names and
    publishers may hold letters A-Z, Icelandic letters, digits, space, '.', '-' and '_'; versions
    are four numeric parts; ids are GUIDs. Anything else is refused, so a manifest value can never
    become code in a generated script.

    -VerifyZipPath with -Dependency checks the public runtime zip of a dependency: the same
    source-free checks, plus the package must be a genuine runtime package (PackageKind runtime)
    and the manifest identity and every manifest dependency must pass the identity rules.

    -VerifyZipPath with -CheckPublishedOrder checks the zip that is public now (the anonymous
    download of the blob the run is about to replace) against the version being published
    (-ExpectedVersion, four parts) and app.json (-AppJsonPath). An older version never replaces
    a newer public one: the check fails, naming both versions, unless -AllowOlder is given. The
    same version may be uploaded again (a rebuild); a newer one replaces the older one. A public
    zip that cannot be verified, or that holds another app, also fails unless -AllowOlder.
    The workflow runs it only when the blob exists (HTTP 200); a missing blob (404) needs no check.

    -WriteDependencyInstallScript writes the fixed container script that installs dependencies.
    It reads the dependency records from a JSON data file (-DataPath) and never runs generated code.
    The major comes from app.json "application" (28.0.0.0 -> bc28). A later BC 29 app.json
    yields bc29. This script does not hard-code a single major.

    Test apps are refused (folder name "test", or an app name containing "Tests").

    The storage credential is read from the environment variable named by -CredentialEnvName.
    There is no default name: Gunnar or an Azure/GitHub org admin creates the credential and
    chooses the name. The script never writes that value, a SAS query, or an AccountKey.
    Logs go through Protect-BifrostLogText. The upload sends Content-Type application/zip.

    The GitHub workflow that calls this script (.github/workflows/RuntimePackage.yaml) is
    Architect-owned. It exports the runtime package from a COSMO Alpaca container; this
    script is the reusable check, zip and upload step.

.PARAMETER AppJsonPath
    Product app.json. Refused when the path is under a test folder.

.PARAMETER RuntimeAppPath
    Runtime package .app (Get-NAVAppRuntimePackage output) to place in the zip.
    Refused when it contains any .al entry.

.PARAMETER ExpectedVersion
    Release version the NavxManifest Version must match. Four parts must be exact.
    Three parts (major.minor.build) accept any revision of that build.

.PARAMETER OutputDirectory
    Directory for the zip. Created when missing.

.PARAMETER CredentialEnvName
    Environment variable that holds the write credential. Required with -Upload.
    The name is logged. The value is not.

.PARAMETER VerifyZipPath
    Check a runtime zip (for example the anonymous download of the published blob) and exit.
    Fails when it does not hold exactly one *_runtime.app or that app has a .al entry.

.PARAMETER PackageReaderPath
    Microsoft.Dynamics.Nav.CodeAnalysis.dll from the official AL extension, with its dependencies
    alongside it. Required for NAVX packages. Defaults to BIFROST_PACKAGE_READER_PATH.

.PARAMETER ExpectedRuntimeSha256
    SHA256 of the validated export, carried separately by the trusted workflow to anonymous read-back.
    Not read from the downloaded ZIP. When supplied, different bytes are refused.

.PARAMETER RuntimeFixturePath
    Genuine Get-NAVAppRuntimePackage export for the integration portion of -SelfTest.
    Synthetic ZIP layout fixtures do not prove runtime-package acceptance.

.PARAMETER SelfTest
    Runs the layout, version, test-app refusal, source refusal, zip, verify, upload-header
    and redaction checks. No network.

.EXAMPLE
    ./tools/New-BifrostRuntimePackage.ps1 -SelfTest

.EXAMPLE
    ./tools/New-BifrostRuntimePackage.ps1 -AppJsonPath ./app/app.json -RuntimeAppPath ./out/Origo_Bifrost_Foundation_28.0.11.669.runtime.app -ExpectedVersion 28.0.11 -OutputDirectory ./out

.EXAMPLE
    ./tools/New-BifrostRuntimePackage.ps1 -VerifyZipPath ./readback.zip -AppJsonPath ./app/app.json -ExpectedVersion 28.0.11
#>
param(
    [string]$AppJsonPath,
    [string]$RuntimeAppPath,
    [string]$ExpectedVersion,
    [string]$OutputDirectory,
    [string]$BcMajor,
    [string]$FolderName,
    [string]$CredentialEnvName,
    [string]$VerifyZipPath,
    [string]$ExpectedRuntimeSha256,
    [string]$PackageReaderPath = $env:BIFROST_PACKAGE_READER_PATH,
    [string]$RuntimeFixturePath,
    [string]$LocateId,
    [string]$LocateName,
    [string]$LocatePublisher,
    [string]$LocateVersion,
    [string]$WriteDependencyInstallScript,
    [scriptblock]$UploadHandler,
    [switch]$Locate,
    [switch]$Dependency,
    [switch]$CheckPublishedOrder,
    [switch]$AllowOlder,
    [switch]$Upload,
    [switch]$WhatIf,
    [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$script:StorageAccount = 'origopublic'
$script:Container = 'runtime'
$script:StorageHost = 'origopublic.blob.core.windows.net'
$script:ZipContentType = 'application/zip'
# Strict identity rules for anything that reaches a generated script, a URL or a log line.
$script:SafeNameCharacters = 'A-Za-z0-9\u00C1\u00E1\u00D0\u00F0\u00C9\u00E9\u00CD\u00ED\u00D3\u00F3\u00DA\u00FA\u00DD\u00FD\u00DE\u00FE\u00C6\u00E6\u00D6\u00F6'
$script:SafeNamePattern = '^[' + $script:SafeNameCharacters + '][' + $script:SafeNameCharacters + ' ._\-]{0,99}\z'
$script:SafeVersionPattern = '^\d{1,9}\.\d{1,9}\.\d{1,9}\.\d{1,9}\z'
$script:SafeIdPattern = '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\z'

function Protect-BifrostLogText {
    param(
        [AllowNull()][string]$Text,
        [AllowNull()][string[]]$SecretValues
    )
    if ([string]::IsNullOrEmpty($Text)) { return '' }
    $out = $Text
    foreach ($secret in @($SecretValues)) {
        if (-not [string]::IsNullOrEmpty($secret) -and $secret.Length -ge 4) {
            $out = $out.Replace($secret, '[redacted]')
        }
    }
    $out = [regex]::Replace($out, '(?i)(sig|se|sp|sv|spr|srt|ss|st|sip|skoid|sktid|skt|ske|sks|skv|AccountKey|SharedAccessSignature|sas)=([^&\s#]*)', '$1=[redacted]')
    $out = [regex]::Replace($out, '(?i)https?://[^\s?]+\?[^\s]+', { param($m) ($m.Value -split '\?', 2)[0] + '?[redacted]' })
    return $out
}

function Write-BifrostSafe {
    param(
        [string]$Message,
        [string[]]$SecretValues
    )
    $safe = Protect-BifrostLogText -Text $Message -SecretValues $SecretValues
    Write-Information $safe -InformationAction Continue
}

function Test-BifrostSafeName {
    param([AllowNull()][AllowEmptyString()][string]$Value)
    if ($null -eq $Value) { return $false }
    return [regex]::IsMatch($Value, $script:SafeNamePattern)
}

function Assert-BifrostSafeIdentity {
    param(
        [AllowNull()][AllowEmptyString()][string]$Id,
        [AllowNull()][AllowEmptyString()][string]$Name,
        [AllowNull()][AllowEmptyString()][string]$Publisher,
        [AllowNull()][AllowEmptyString()][string]$Version,
        [string]$Context = 'app'
    )
    # Values are never echoed back: a hostile value must not reach a log or a script.
    if ($null -eq $Id -or -not [regex]::IsMatch($Id, $script:SafeIdPattern)) { throw "Refusing $($Context): the app id is not a GUID." }
    if (-not (Test-BifrostSafeName $Name)) { throw "Refusing $($Context) $($Id): the app name has characters outside A-Z, Icelandic letters, digits, space, '.', '-' and '_' (or is empty or longer than 100)." }
    if (-not (Test-BifrostSafeName $Publisher)) { throw "Refusing $($Context) $($Id): the publisher has characters outside A-Z, Icelandic letters, digits, space, '.', '-' and '_' (or is empty or longer than 100)." }
    if ($null -eq $Version -or -not [regex]::IsMatch($Version, $script:SafeVersionPattern)) { throw "Refusing $($Context) $($Id): the version is not four numeric parts." }
}

function Assert-BifrostDependencyManifest {
    param([Parameter(Mandatory = $true)]$Manifest)
    Assert-BifrostSafeIdentity -Id ([string]$Manifest.Id) -Name ([string]$Manifest.Name) -Publisher ([string]$Manifest.Publisher) -Version ([string]$Manifest.Version) -Context 'dependency runtime package'
    foreach ($child in @($Manifest.Dependencies | Where-Object { $_ })) {
        Assert-BifrostSafeIdentity -Id ([string]$child.Id) -Name ([string]$child.Name) -Publisher ([string]$child.Publisher) -Version ([string]$child.Version) -Context "a dependency of $($Manifest.Id)"
    }
}

function ConvertTo-BifrostFourPartVersion {
    param([string]$Version)
    if ([string]::IsNullOrWhiteSpace($Version)) { return $null }
    $parts = @($Version.Trim().Split('.'))
    if ($parts.Count -eq 3) { $parts += '0' }
    if ($parts.Count -ne 4) { return $null }
    foreach ($part in $parts) {
        $number = 0
        if (-not [int]::TryParse($part, [ref]$number)) { return $null }
        if ($number -lt 0) { return $null }
    }
    return ($parts -join '.')
}

function Test-BifrostReleaseVersionMatch {
    param(
        [string]$AppVersion,
        [string]$ReleaseVersion
    )
    $app = ConvertTo-BifrostFourPartVersion $AppVersion
    if (-not $app) { return $false }
    $releaseText = if ($null -eq $ReleaseVersion) { '' } else { $ReleaseVersion.Trim() }
    $releaseParts = @($releaseText.Split('.'))
    if ($releaseParts.Count -eq 3) {
        # AL-Go tags are major.minor.build. The app revision is stamped later.
        $prefix = ConvertTo-BifrostFourPartVersion ($releaseText + '.0')
        if (-not $prefix) { return $false }
        $appParts = $app.Split('.')
        $prefixParts = $prefix.Split('.')
        return ($appParts[0] -eq $prefixParts[0]) -and ($appParts[1] -eq $prefixParts[1]) -and ($appParts[2] -eq $prefixParts[2])
    }
    $release = ConvertTo-BifrostFourPartVersion $ReleaseVersion
    if (-not $release) { return $false }
    return $app -eq $release
}

function Test-BifrostProductAppPath {
    param([string]$Path)
    $full = [System.IO.Path]::GetFullPath($Path)
    $segments = $full -split '[\\/]'
    foreach ($segment in $segments) {
        if ($segment -eq 'test') { return $false }
    }
    return $true
}

function Get-BifrostAppIdentity {
    param([string]$Path)
    if (-not (Test-BifrostProductAppPath $Path)) {
        throw "Refusing test-app path '$Path'. Runtime packages are built from the product app only."
    }
    $json = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    $name = [string]$json.name
    $publisher = [string]$json.publisher
    $version = [string]$json.version
    $application = [string]$json.application
    if ([string]::IsNullOrWhiteSpace($name) -or [string]::IsNullOrWhiteSpace($publisher)) {
        throw "app.json at '$Path' is missing name or publisher."
    }
    if ($name -match '(?i)(^test\b|\btests\b)') {
        throw "Refusing app name '$name'. Runtime packages are not built for test apps."
    }
    $applicationMajor = $null
    if ($application -match '^(\d+)\.') { $applicationMajor = $Matches[1] }
    return [pscustomobject]@{
        Name = $name
        Publisher = $publisher
        Version = $version
        Application = $application
        ApplicationMajor = $applicationMajor
        Id = [string]$json.id
    }
}

function Get-BifrostRuntimePackageLayout {
    param(
        [Parameter(Mandatory = $true)]$Identity,
        [string]$BcMajor,
        [string]$FolderName
    )
    $major = $BcMajor
    if ([string]::IsNullOrWhiteSpace($major)) { $major = [string]$Identity.ApplicationMajor }
    if ($major -notmatch '^\d+$') {
        throw "BC major must be the leading number of app.json application (got '$major')."
    }
    $folder = [string]$Identity.Name
    if (-not [string]::IsNullOrWhiteSpace($FolderName) -and $FolderName -cne $folder) {
        throw ("Refusing package folder '{0}': the runtime zip is always stored under the app name '{1}' (bc<major>/<app name>/<Publisher>_<App>_runtime.zip), so apps that depend on it find it." -f $FolderName, $folder)
    }
    if ($folder -match '(?i)(^test\b|\btests\b)') {
        throw "Refusing package folder '$folder'."
    }
    $fileStem = ('{0}_{1}_runtime' -f $Identity.Publisher, $Identity.Name)
    $zipFileName = $fileStem + '.zip'
    $innerAppFileName = $fileStem + '.app'
    $blobPath = ('bc{0}/{1}/{2}' -f $major, $folder, $zipFileName)
    $encoded = (($blobPath -split '/') | ForEach-Object { [Uri]::EscapeDataString($_) }) -join '/'
    $publicUrl = ('https://{0}/{1}/{2}' -f $script:StorageHost, $script:Container, $encoded)
    return [pscustomobject]@{
        BcMajor = $major
        FolderName = $folder
        ZipFileName = $zipFileName
        InnerAppFileName = $innerAppFileName
        BlobPath = $blobPath
        PublicUrl = $publicUrl
        Container = $script:Container
        StorageAccount = $script:StorageAccount
    }
}

function Get-BifrostZipOffset {
    param([byte[]]$Bytes)
    # A Business Central .app is a NAVX header followed by a zip. Find the first local
    # file header (PK\x03\x04); the NAVX header is 40 bytes, so the first 512 bytes suffice.
    $limit = [Math]::Min(512, $Bytes.Length - 4)
    for ($i = 0; $i -le $limit; $i++) {
        if ($Bytes[$i] -eq 0x50 -and $Bytes[$i + 1] -eq 0x4B -and $Bytes[$i + 2] -eq 0x03 -and $Bytes[$i + 3] -eq 0x04) {
            return $i
        }
    }
    return -1
}

function Get-BifrostNativePackageInfo {
    param([Parameter(Mandatory = $true)][string]$AppPath)
    # NAVX is a container format, not evidence of an encrypted/source-free payload. Use the
    # same Microsoft reader as the AL compiler, including for runtime packages without PK.
    if (-not ('Microsoft.Dynamics.Nav.CodeAnalysis.Packaging.NavAppPackageReader' -as [type])) {
        if ([string]::IsNullOrWhiteSpace($PackageReaderPath) -or -not (Test-Path -LiteralPath $PackageReaderPath -PathType Leaf)) {
            throw 'NAVX validation requires Microsoft.Dynamics.Nav.CodeAnalysis.dll. Set -PackageReaderPath or BIFROST_PACKAGE_READER_PATH to the AL compiler assembly. Unreadable input is never treated as source-free.'
        }
        $readerDirectory = Split-Path -Parent ([System.IO.Path]::GetFullPath($PackageReaderPath))
        $resolver = {
            param($context, $name)
            $dependency = Join-Path $readerDirectory ($name.Name + '.dll')
            if (Test-Path -LiteralPath $dependency) { return $context.LoadFromAssemblyPath($dependency) }
            return $null
        }.GetNewClosure()
        [System.Runtime.Loader.AssemblyLoadContext]::Default.add_Resolving($resolver)
        [System.Reflection.Assembly]::LoadFrom([System.IO.Path]::GetFullPath($PackageReaderPath)) | Out-Null
    }
    $stream = [System.IO.File]::OpenRead($AppPath)
    $reader = $null
    try {
        $reader = [Microsoft.Dynamics.Nav.CodeAnalysis.Packaging.NavAppPackageReader]::Create($stream, $true, $AppPath)
        $manifest = $reader.ReadNavAppManifest()
        $entries = @($reader.ReadTableOfContents())
        if ($entries.Count -eq 0) { throw 'The BC package has no contents.' }
        # Read every entry, not just the header/manifest: truncated or corrupt payloads fail.
        foreach ($name in $entries) {
            $content = $reader.ReadFile($name)
            if (-not $content) { throw "The BC package entry '$name' is unreadable." }
            try { $content.CopyTo([System.IO.Stream]::Null) } finally { $content.Dispose() }
        }
        $runtime = $reader.IsRuntimePackage
        if ($runtime) {
            $runtimeManifest = $reader.ReadRuntimePackageManifest()
            if (-not $runtimeManifest -or $runtimeManifest.Contents.Count -eq 0) {
                throw 'The runtime package has no compiled contents.'
            }
        }
        # Ask the reader for embedded source too, and scan all entry names regardless of case.
        $sources = @(@($entries) + @($reader.ReadSourceFilePaths()) + @($reader.ReadSourceCodeFilePaths()) |
            ForEach-Object { $_ -replace '\\', '/' } | Where-Object { $_ -match '(?i)\.al$' } | Sort-Object -Unique)
        return [pscustomobject]@{
            PackageKind = $(if ($runtime) { 'runtime' } else { 'zip' })
            Sources = $sources
            Identity = [pscustomobject]@{
                Id = [string]$manifest.AppId
                Name = $manifest.AppName
                Publisher = $manifest.AppPublisher
                Version = [string]$manifest.AppVersion
                Application = [string]$manifest.Application
                Dependencies = @(@($manifest.Dependencies) | Where-Object { $_ } | ForEach-Object {
                    [pscustomobject]@{ Id = [string]$_.AppId; Name = [string]$_.Name; Publisher = [string]$_.Publisher; Version = [string]$_.MinVersion }
                })
            }
        }
    }
    catch { throw "Refusing invalid Business Central package '$AppPath': $($_.Exception.Message)" }
    finally {
        if ($reader) { $reader.Dispose() }
        $stream.Dispose()
    }
}

function Test-BifrostNavxHeader {
    param([string]$AppPath)
    $stream = [System.IO.File]::OpenRead($AppPath)
    try {
        $header = New-Object byte[] 4
        return $stream.Read($header, 0, 4) -eq 4 -and [System.Text.Encoding]::ASCII.GetString($header) -eq 'NAVX'
    }
    finally { $stream.Dispose() }
}

function Get-BifrostAppPackageKind {
    param([Parameter(Mandatory = $true)][string]$AppPath)
    if (Test-BifrostNavxHeader $AppPath) { return (Get-BifrostNativePackageInfo $AppPath).PackageKind }
    $bytes = [System.IO.File]::ReadAllBytes($AppPath)
    if ((Get-BifrostZipOffset $bytes) -eq 0) { return 'zip' }
    throw "'$AppPath' is not a Business Central package: no valid NAVX package or ZIP header (PK)."
}

function Open-BifrostAppPackage {
    param([string]$AppPath)
    # ZipFile.OpenRead only accepts a file that starts with PK, so copy from the local header.
    $bytes = [System.IO.File]::ReadAllBytes($AppPath)
    $offset = Get-BifrostZipOffset $bytes
    if ($offset -lt 0) { throw "No zip local header (PK\x03\x04) in '$AppPath'. It is not a Business Central .app." }
    $stream = New-Object System.IO.MemoryStream
    $stream.Write($bytes, $offset, $bytes.Length - $offset)
    $stream.Position = 0
    return New-Object System.IO.Compression.ZipArchive($stream, [System.IO.Compression.ZipArchiveMode]::Read, $false)
}

function Get-BifrostAppSourceEntry {
    param([Parameter(Mandatory = $true)][string]$AppPath)
    # Every entry whose name ends in .al (any folder, any case) is AL source.
    if (Test-BifrostNavxHeader $AppPath) { return (Get-BifrostNativePackageInfo $AppPath).Sources }
    Get-BifrostAppPackageKind $AppPath | Out-Null
    $zip = Open-BifrostAppPackage $AppPath
    try {
        return @($zip.Entries | ForEach-Object { $_.FullName -replace '\\', '/' } | Where-Object { $_ -match '(?i)\.al$' })
    }
    finally { $zip.Dispose() }
}

function Assert-BifrostRuntimeAppHasNoSource {
    param([Parameter(Mandatory = $true)][string]$AppPath)
    $sources = @(Get-BifrostAppSourceEntry -AppPath $AppPath)
    if ($sources.Count -gt 0) {
        $examples = ($sources | Select-Object -First 3) -join ', '
        throw ("Refusing '{0}': it contains {1} AL source file(s) (.al entries, for example {2}). It is a full .app, not a runtime package. Export a runtime package with Get-NAVAppRuntimePackage on a BC server of the matching version and pack that. A public runtime zip must never carry source (#1269)." -f [System.IO.Path]::GetFileName($AppPath), $sources.Count, $examples)
    }
}

function Get-NavxAppIdentity {
    param([string]$AppPath)
    if (Test-BifrostNavxHeader $AppPath) { return (Get-BifrostNativePackageInfo $AppPath).Identity }
    $zip = Open-BifrostAppPackage $AppPath
    try {
        $entry = $zip.Entries | Where-Object { ($_.FullName -replace '\\', '/') -eq 'NavxManifest.xml' } | Select-Object -First 1
        if (-not $entry) { throw "NavxManifest.xml is missing from '$AppPath'." }
        $reader = New-Object System.IO.StreamReader($entry.Open())
        try { $xmlText = $reader.ReadToEnd() } finally { $reader.Dispose() }
    }
    finally { $zip.Dispose() }
    $xml = New-Object System.Xml.XmlDocument
    $xml.PreserveWhitespace = $true
    $xml.LoadXml($xmlText)
    $node = $xml.SelectSingleNode('//*[local-name()="App"]')
    if (-not $node) { throw "NavxManifest.xml in '$AppPath' has no App element." }
    $dependencies = @($xml.SelectNodes('//*[local-name()="Dependencies"]/*[local-name()="Dependency"]') | ForEach-Object {
        $dependencyId = $_.GetAttribute('Id')
        if (-not $dependencyId) { $dependencyId = $_.GetAttribute('AppId') }
        [pscustomobject]@{ Id = $dependencyId; Name = $_.GetAttribute('Name'); Publisher = $_.GetAttribute('Publisher'); Version = $_.GetAttribute('MinVersion') }
    })
    return [pscustomobject]@{
        Id = $node.GetAttribute('Id')
        Name = $node.GetAttribute('Name')
        Publisher = $node.GetAttribute('Publisher')
        Version = $node.GetAttribute('Version')
        Application = $node.GetAttribute('Application')
        Dependencies = $dependencies
    }
}

function Assert-BifrostManifestMatch {
    param(
        [Parameter(Mandatory = $true)]$Manifest,
        [Parameter(Mandatory = $true)]$Identity,
        [Parameter(Mandatory = $true)][string]$ExpectedVersion
    )
    if ($Identity.Id -and $Manifest.Id -ne $Identity.Id) { throw 'NavxManifest app id does not match app.json.' }
    if ($Manifest.Name -ne $Identity.Name -or $Manifest.Publisher -ne $Identity.Publisher) {
        throw ("NavxManifest name/publisher '{0}'/'{1}' does not match app.json '{2}'/'{3}'." -f $Manifest.Name, $Manifest.Publisher, $Identity.Name, $Identity.Publisher)
    }
    if (-not (Test-BifrostReleaseVersionMatch -AppVersion $Manifest.Version -ReleaseVersion $ExpectedVersion)) {
        throw ("NavxManifest version '{0}' does not match release version '{1}'." -f $Manifest.Version, $ExpectedVersion)
    }
}

function New-BifrostRuntimePackageZip {
    param(
        [Parameter(Mandatory = $true)][string]$RuntimeAppPath,
        [Parameter(Mandatory = $true)][string]$ZipPath,
        [Parameter(Mandatory = $true)][string]$InnerAppFileName,
        [Parameter(Mandatory = $true)]$Identity,
        [Parameter(Mandatory = $true)][string]$ExpectedVersion
    )
    if (-not (Test-Path -LiteralPath $RuntimeAppPath)) {
        throw "Runtime package not found: $RuntimeAppPath"
    }
    Assert-BifrostRuntimeAppHasNoSource -AppPath $RuntimeAppPath
    $manifest = Get-NavxAppIdentity $RuntimeAppPath
    Assert-BifrostManifestMatch -Manifest $manifest -Identity $Identity -ExpectedVersion $ExpectedVersion
    $directory = Split-Path -Parent $ZipPath
    if ($directory -and -not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    if (Test-Path -LiteralPath $ZipPath) { Remove-Item -LiteralPath $ZipPath -Force }
    $zip = [System.IO.Compression.ZipFile]::Open($ZipPath, [System.IO.Compression.ZipArchiveMode]::Create)
    try {
        $entry = $zip.CreateEntry($InnerAppFileName, [System.IO.Compression.CompressionLevel]::Optimal)
        $inputStream = [System.IO.File]::OpenRead($RuntimeAppPath)
        $outputStream = $entry.Open()
        try { $inputStream.CopyTo($outputStream) } finally { $outputStream.Dispose(); $inputStream.Dispose() }
    }
    finally { $zip.Dispose() }
    $runtimeSha256 = (Get-FileHash -LiteralPath $RuntimeAppPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $verified = Test-BifrostRuntimePackageZip -ZipPath $ZipPath -InnerAppFileName $InnerAppFileName -ExpectedRuntimeSha256 $runtimeSha256 -Identity $Identity -ExpectedVersion $ExpectedVersion
    return [pscustomobject]@{
        ZipPath = $ZipPath
        InnerAppFileName = $InnerAppFileName
        ManifestVersion = $(if ($manifest) { $manifest.Version } else { $null })
        RuntimeSha256 = $runtimeSha256
        AlEntries = $verified.AlEntries
        PackageKind = $verified.PackageKind
    }
}

function Test-BifrostRuntimePackageZip {
    param(
        [Parameter(Mandatory = $true)][string]$ZipPath,
        [string]$InnerAppFileName,
        [string]$ExpectedRuntimeSha256,
        $Identity,
        [string]$ExpectedVersion
    )
    # Checks a runtime zip as a consumer gets it: one *_runtime.app, and no AL source inside.
    if (-not (Test-Path -LiteralPath $ZipPath)) { throw "Runtime zip not found: $ZipPath" }
    $work = Join-Path ([System.IO.Path]::GetTempPath()) ('bifrost-runtime-verify-' + [guid]::NewGuid().ToString('n'))
    New-Item -ItemType Directory -Path $work -Force | Out-Null
    try {
        $outer = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)
        try {
            $names = @($outer.Entries | ForEach-Object { $_.FullName })
            $expectedName = $InnerAppFileName
            if ([string]::IsNullOrWhiteSpace($expectedName)) {
                if ($names.Count -ne 1 -or $names[0] -notlike '*_runtime.app') {
                    throw ("Runtime zip must contain exactly one *_runtime.app. Found: {0}" -f ($names -join ', '))
                }
                $expectedName = $names[0]
            }
            if ($names.Count -ne 1 -or $names[0] -ne $expectedName) {
                throw ("Runtime zip must contain exactly one {0}. Found: {1}" -f $expectedName, ($names -join ', '))
            }
            $innerPath = Join-Path $work 'inner.app'
            $entryStream = $outer.Entries[0].Open()
            $fileStream = [System.IO.File]::Create($innerPath)
            try { $entryStream.CopyTo($fileStream) } finally { $fileStream.Dispose(); $entryStream.Dispose() }
        }
        finally { $outer.Dispose() }
        $runtimeSha256 = (Get-FileHash -LiteralPath $innerPath -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($ExpectedRuntimeSha256 -and ($ExpectedRuntimeSha256 -notmatch '^[a-fA-F0-9]{64}$' -or $runtimeSha256 -ne $ExpectedRuntimeSha256)) {
            throw 'The downloaded runtime package SHA256 does not match the validated export.'
        }
        $packageKind = Get-BifrostAppPackageKind $innerPath
        $sources = @(Get-BifrostAppSourceEntry -AppPath $innerPath)
        if ($sources.Count -gt 0) {
            throw ("Runtime zip '{0}' holds {1} with {2} AL source file(s) (for example {3}). The public runtime zip must not carry source (#1269)." -f [System.IO.Path]::GetFileName($ZipPath), $expectedName, $sources.Count, (($sources | Select-Object -First 3) -join ', '))
        }
        $manifest = Get-NavxAppIdentity $innerPath
        if ($Identity) {
            if ([string]::IsNullOrWhiteSpace($ExpectedVersion)) { throw 'ExpectedVersion is required when the identity is checked.' }
            Assert-BifrostManifestMatch -Manifest $manifest -Identity $Identity -ExpectedVersion $ExpectedVersion
        }
        return [pscustomobject]@{
            Verified = $true
            RuntimeSha256 = $runtimeSha256
            InnerAppFileName = $expectedName
            AlEntries = 0
            PackageKind = $packageKind
            ManifestId = $(if ($manifest) { $manifest.Id } else { $null })
            ManifestName = $(if ($manifest) { $manifest.Name } else { $null })
            ManifestPublisher = $(if ($manifest) { $manifest.Publisher } else { $null })
            ManifestVersion = $(if ($manifest) { $manifest.Version } else { $null })
            # Dependencies of the packaged app (id, name, publisher, minimum version). The RuntimePackage
            # workflow reads them from a dependency's public runtime zip to install Bifrost dependencies
            # transitively and in order before it publishes the released app.
            ManifestDependencies = $(if ($manifest) { @($manifest.Dependencies) } else { @() })
        }
    }
    finally {
        if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force }
    }
}

function Publish-BifrostRuntimePackageBlob {
    param(
        [Parameter(Mandatory = $true)][string]$ZipPath,
        [Parameter(Mandatory = $true)][string]$PublicUrl,
        [Parameter(Mandatory = $true)][string]$CredentialEnvName,
        [scriptblock]$UploadHandler,
        [switch]$WhatIf
    )
    if ($CredentialEnvName -notmatch '^[A-Za-z_][A-Za-z0-9_]*$') {
        throw "Credential environment name '$CredentialEnvName' is not an environment-variable name."
    }
    $secret = [Environment]::GetEnvironmentVariable($CredentialEnvName)
    if ($WhatIf) {
        Write-BifrostSafe -Message ("Upload not performed (WhatIf). Credential env name: {0}. Public URL: {1}" -f $CredentialEnvName, $PublicUrl) -SecretValues @($secret)
        return [pscustomobject]@{ Uploaded = $false; Planned = $true; PublicUrl = $PublicUrl; CredentialEnvName = $CredentialEnvName }
    }
    if ([string]::IsNullOrWhiteSpace($secret)) {
        throw ("Storage credential environment variable '{0}' is empty. Gunnar or an Azure/GitHub org admin must create the origopublic write credential. Upload was not attempted." -f $CredentialEnvName)
    }
    $uploadUrl = $PublicUrl
    $trimmed = $secret.Trim()
    if ($trimmed -match '^https?://') { $uploadUrl = $trimmed }
    elseif ($trimmed.StartsWith('?')) { $uploadUrl = $PublicUrl + $trimmed }
    else { $uploadUrl = $PublicUrl + '?' + $trimmed.TrimStart('?') }
    Write-BifrostSafe -Message ("Uploading runtime zip to {0} using credential env {1}." -f $PublicUrl, $CredentialEnvName) -SecretValues @($secret, $uploadUrl)
    try {
        if ($UploadHandler) {
            $status = & $UploadHandler $ZipPath $uploadUrl
        }
        else {
            $status = Invoke-BifrostBlobPut -ZipPath $ZipPath -UploadUrl $uploadUrl -SecretValues @($secret)
        }
    }
    catch {
        $safe = Protect-BifrostLogText -Text $_.Exception.Message -SecretValues @($secret, $uploadUrl)
        throw "Runtime blob upload failed: $safe"
    }
    if ([int]$status -lt 200 -or [int]$status -ge 300) {
        throw "Runtime blob upload failed with HTTP $status. The credential value was not logged."
    }
    return [pscustomobject]@{ Uploaded = $true; Planned = $false; PublicUrl = $PublicUrl; CredentialEnvName = $CredentialEnvName; StatusCode = [int]$status }
}

function Get-BifrostBlobPutCurlArgument {
    param(
        [Parameter(Mandatory = $true)][string]$ZipPath,
        [Parameter(Mandatory = $true)][string]$UploadUrl
    )
    # curl --data-binary defaults to application/x-www-form-urlencoded, which Put Blob stored as the
    # blob's content type (#1269). Send application/zip as the request type and the blob type.
    return @(
        '--silent', '--show-error', '--fail-with-body',
        '-o', '/dev/null',
        '-w', '%{http_code}',
        '-X', 'PUT',
        '-H', 'x-ms-blob-type: BlockBlob',
        '-H', "Content-Type: $($script:ZipContentType)",
        '-H', "x-ms-blob-content-type: $($script:ZipContentType)",
        '--data-binary', "@$ZipPath",
        $UploadUrl
    )
}

function Invoke-BifrostBlobPut {
    param(
        [string]$ZipPath,
        [string]$UploadUrl,
        [string[]]$SecretValues
    )
    $curl = Get-Command curl -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $curl) { throw 'curl is not available for the blob upload.' }
    $arguments = Get-BifrostBlobPutCurlArgument -ZipPath $ZipPath -UploadUrl $UploadUrl
    $output = & $curl.Source @arguments 2>&1
    $text = ($output | Out-String)
    $safe = Protect-BifrostLogText -Text $text -SecretValues $SecretValues
    if ($text -match '(\d{3})\s*$') { return [int]$Matches[1] }
    throw "Blob upload did not return an HTTP status. curl said: $safe"
}

function Invoke-BifrostRuntimePackage {
    if ([string]::IsNullOrWhiteSpace($AppJsonPath) -or [string]::IsNullOrWhiteSpace($ExpectedVersion) -or [string]::IsNullOrWhiteSpace($OutputDirectory)) {
        throw 'AppJsonPath, ExpectedVersion and OutputDirectory are required.'
    }
    if ([string]::IsNullOrWhiteSpace($RuntimeAppPath)) { throw 'RuntimeAppPath is required: the Get-NAVAppRuntimePackage output.' }
    $identity = Get-BifrostAppIdentity $AppJsonPath
    $layout = Get-BifrostRuntimePackageLayout -Identity $identity -BcMajor $BcMajor -FolderName $FolderName
    $zipPath = Join-Path $OutputDirectory $layout.ZipFileName
    $packed = New-BifrostRuntimePackageZip -RuntimeAppPath $RuntimeAppPath -ZipPath $zipPath -InnerAppFileName $layout.InnerAppFileName -Identity $identity -ExpectedVersion $ExpectedVersion
    $uploadResult = $null
    if ($Upload -or $WhatIf) {
        if ([string]::IsNullOrWhiteSpace($CredentialEnvName) -and $Upload) {
            throw '-Upload requires -CredentialEnvName. Do not invent a secret name; use the name Gunnar or the org admin created.'
        }
        if ($WhatIf -and [string]::IsNullOrWhiteSpace($CredentialEnvName)) {
            $uploadResult = [pscustomobject]@{ Uploaded = $false; Planned = $true; PublicUrl = $layout.PublicUrl; CredentialEnvName = $null }
        }
        else {
            $uploadResult = Publish-BifrostRuntimePackageBlob -ZipPath $packed.ZipPath -PublicUrl $layout.PublicUrl -CredentialEnvName $CredentialEnvName -UploadHandler $UploadHandler -WhatIf:$WhatIf
        }
    }
    return [pscustomobject]@{
        BlobPath = $layout.BlobPath
        PublicUrl = $layout.PublicUrl
        ZipPath = $packed.ZipPath
        InnerAppFileName = $layout.InnerAppFileName
        ManifestVersion = $packed.ManifestVersion
        RuntimeSha256 = $packed.RuntimeSha256
        AlEntries = $packed.AlEntries
        PackageKind = $packed.PackageKind
        Uploaded = $(if ($uploadResult) { [bool]$uploadResult.Uploaded } else { $false })
        CredentialEnvName = $(if ($uploadResult) { $uploadResult.CredentialEnvName } else { $null })
    }
}

function Invoke-BifrostRuntimeZipVerification {
    $identity = $null
    $innerName = $null
    if (-not [string]::IsNullOrWhiteSpace($AppJsonPath)) {
        $identity = Get-BifrostAppIdentity $AppJsonPath
        $innerName = (Get-BifrostRuntimePackageLayout -Identity $identity -BcMajor $BcMajor -FolderName $FolderName).InnerAppFileName
    }
    if ($Dependency) { return Test-BifrostDependencyRuntimeZip -ZipPath $VerifyZipPath }
    if ($CheckPublishedOrder) { return Test-BifrostPublishedVersionOrder -PublishedZipPath $VerifyZipPath -AppJsonPath $AppJsonPath -NewVersion $ExpectedVersion -AllowOlder:$AllowOlder }
    return Test-BifrostRuntimePackageZip -ZipPath $VerifyZipPath -InnerAppFileName $innerName -Identity $identity -ExpectedVersion $ExpectedVersion -ExpectedRuntimeSha256 $ExpectedRuntimeSha256
}

function Get-BifrostVersionOrderDecision {
    param(
        [AllowNull()][AllowEmptyString()][string]$PublishedVersion,
        [Parameter(Mandatory = $true)][string]$NewVersion,
        [switch]$AllowOlder
    )
    # Latest release only (Gunnar, 02.11.2026): the public zip must never go back to an older version.
    $new = ConvertTo-BifrostFourPartVersion $NewVersion
    if (-not $new -or $NewVersion -notmatch '^\d+\.\d+\.\d+\.\d+$') { throw "The version being published must have four numeric parts (got '$NewVersion')." }
    if ([string]::IsNullOrWhiteSpace($PublishedVersion)) {
        return [pscustomobject]@{ Allowed = $true; Reason = 'none-published'; PublishedVersion = $null; NewVersion = $new }
    }
    $published = ConvertTo-BifrostFourPartVersion $PublishedVersion
    if (-not $published) { throw "The public runtime zip reports version '$PublishedVersion', which is not a version." }
    $comparison = ([version]$new).CompareTo([version]$published)
    if ($comparison -gt 0) { return [pscustomobject]@{ Allowed = $true; Reason = 'newer'; PublishedVersion = $published; NewVersion = $new } }
    if ($comparison -eq 0) { return [pscustomobject]@{ Allowed = $true; Reason = 'same-version-rebuild'; PublishedVersion = $published; NewVersion = $new } }
    if ($AllowOlder) { return [pscustomobject]@{ Allowed = $true; Reason = 'older-allowed'; PublishedVersion = $published; NewVersion = $new } }
    return [pscustomobject]@{ Allowed = $false; Reason = 'older'; PublishedVersion = $published; NewVersion = $new }
}

function Test-BifrostPublishedVersionOrder {
    param(
        [Parameter(Mandatory = $true)][string]$PublishedZipPath,
        [Parameter(Mandatory = $true)][string]$AppJsonPath,
        [Parameter(Mandatory = $true)][string]$NewVersion,
        [switch]$AllowOlder
    )
    $identity = Get-BifrostAppIdentity $AppJsonPath
    $verified = $null
    try { $verified = Test-BifrostRuntimePackageZip -ZipPath $PublishedZipPath }
    catch {
        if (-not $AllowOlder) {
            throw ("The public runtime zip of {0} could not be verified, so its version is unknown and it is not replaced: {1} Run again with allowOlder to replace it." -f $identity.Name, $_.Exception.Message)
        }
    }
    if ($verified -and ($verified.ManifestName -cne $identity.Name -or $verified.ManifestPublisher -cne $identity.Publisher) -and -not $AllowOlder) {
        throw ("The public runtime zip at the {0} location holds {1} {2}, not {3} {4}. It is not replaced. Run again with allowOlder to replace it." -f $identity.Name, $verified.ManifestPublisher, $verified.ManifestName, $identity.Publisher, $identity.Name)
    }
    $publishedVersion = if ($verified) { [string]$verified.ManifestVersion } else { $null }
    $decision = Get-BifrostVersionOrderDecision -PublishedVersion $publishedVersion -NewVersion $NewVersion -AllowOlder:$AllowOlder
    if (-not $decision.Allowed) {
        throw ("Refusing to replace the public runtime package of {0} {1} with the older {2}. The public zip always holds the latest release. Run again with allowOlder only to roll back on purpose; the built zip is kept as a workflow artifact." -f $identity.Name, $decision.PublishedVersion, $decision.NewVersion)
    }
    return $decision
}

function Test-BifrostDependencyRuntimeZip {
    param([Parameter(Mandatory = $true)][string]$ZipPath)
    # A dependency is installed in the export container, so it must be a genuine runtime package
    # (the NAVX runtime checks the packager applies to its own export), not just a source-free zip.
    $result = Test-BifrostRuntimePackageZip -ZipPath $ZipPath
    if ($result.PackageKind -ne 'runtime') {
        throw ("Refusing dependency runtime zip '{0}': the package inside is not a genuine Business Central runtime package (PackageKind {1})." -f [System.IO.Path]::GetFileName($ZipPath), $result.PackageKind)
    }
    Assert-BifrostDependencyManifest -Manifest ([pscustomobject]@{ Id = $result.ManifestId; Name = $result.ManifestName; Publisher = $result.ManifestPublisher; Version = $result.ManifestVersion; Dependencies = @($result.ManifestDependencies) })
    $expectedName = (Get-BifrostRuntimePackageLayout -Identity ([pscustomobject]@{ Name = $result.ManifestName; Publisher = $result.ManifestPublisher; ApplicationMajor = '0' }) -BcMajor '0').InnerAppFileName
    if ($result.InnerAppFileName -cne $expectedName) { throw ("Refusing dependency runtime zip '{0}': it holds {1}, expected {2}." -f [System.IO.Path]::GetFileName($ZipPath), $result.InnerAppFileName, $expectedName) }
    return $result
}

function Get-BifrostRuntimeLocation {
    param([string]$Id, [string]$Name, [string]$Publisher, [string]$Version, [string]$BcMajor)
    Assert-BifrostSafeIdentity -Id $Id -Name $Name -Publisher $Publisher -Version $Version -Context 'app'
    # The same derivation the publisher uses (Get-BifrostRuntimePackageLayout), so a dependant always
    # looks where the dependency's own run stored its zip.
    $layout = Get-BifrostRuntimePackageLayout -Identity ([pscustomobject]@{ Name = $Name; Publisher = $Publisher; ApplicationMajor = $BcMajor }) -BcMajor $BcMajor
    return [pscustomobject]@{ Id = $Id; Name = $Name; Publisher = $Publisher; Version = $Version; BlobPath = $layout.BlobPath; PublicUrl = $layout.PublicUrl; InnerAppFileName = $layout.InnerAppFileName }
}

function Get-BifrostDependencyInstallScript {
    # Fixed text: no value is ever spliced into it. Dependency records arrive as JSON data.
    return @'
param([Parameter(Mandatory = $true)][string]$DataPath)
$ErrorActionPreference = 'Stop'
if (Test-Path 'C:\Run\Prompt.ps1') { . 'C:\Run\Prompt.ps1' | Out-Null }
try {
    $data = Get-Content -Raw -LiteralPath $DataPath | ConvertFrom-Json
    $folder = Split-Path -Parent $DataPath
    $inst = Get-NAVServerInstance | Select-Object -First 1
    if (-not $inst) { throw 'No BC server instance.' }
    $si = $inst.ServerInstance -replace '^.*\$', ''
    $files = $null
    foreach ($dep in @($data.Microsoft | Where-Object { $_ })) {
        $info = @(Get-NAVAppInfo -ServerInstance $si -Id $dep.Id -Tenant default -TenantSpecificProperties) | Sort-Object Version -Descending | Select-Object -First 1
        if (-not $info) {
            if ($null -eq $files) { $files = @(Get-ChildItem -Path 'C:\Applications*' -Recurse -File -Filter '*.app' -ErrorAction SilentlyContinue) }
            $pattern = '*' + [System.Management.Automation.WildcardPattern]::Escape([string]$dep.Name) + '*'
            $file = $null
            foreach ($candidate in @(@($files | Where-Object { $_.Name -like $pattern }) + @($files))) {
                try { if ([string](Get-NAVAppInfo -Path $candidate.FullName).AppId -eq [string]$dep.Id) { $file = $candidate; break } } catch { }
            }
            if (-not $file) { throw ('Microsoft dependency {0} is not published and not in the BC artifact applications of this container.' -f $dep.Name) }
            Publish-NAVApp -ServerInstance $si -Path $file.FullName -SkipVerification
            $info = @(Get-NAVAppInfo -ServerInstance $si -Id $dep.Id -Tenant default -TenantSpecificProperties) | Sort-Object Version -Descending | Select-Object -First 1
        }
        if ($dep.MinVersion -and [version][string]$info.Version -lt [version][string]$dep.MinVersion) { throw ('Microsoft dependency {0} is {1} in this BC artifact; the app needs {2}.' -f $dep.Name, $info.Version, $dep.MinVersion) }
        if (-not $info.IsInstalled) {
            Sync-NAVApp -ServerInstance $si -Name $info.Name -Publisher $info.Publisher -Version $info.Version -Tenant default
            Install-NAVApp -ServerInstance $si -Name $info.Name -Publisher $info.Publisher -Version $info.Version -Tenant default
        }
        Write-Host ('[BIFROST_DEPENDENCY_OK] Microsoft {0} {1}' -f $dep.Name, $info.Version)
    }
    foreach ($dep in @($data.Bifrost | Where-Object { $_ })) {
        $path = Join-Path $folder ([System.IO.Path]::GetFileName([string]$dep.File))
        Publish-NAVApp -ServerInstance $si -Path $path -SkipVerification
        Sync-NAVApp -ServerInstance $si -Name $dep.Name -Publisher $dep.Publisher -Version $dep.Version -Tenant default
        Install-NAVApp -ServerInstance $si -Name $dep.Name -Publisher $dep.Publisher -Version $dep.Version -Tenant default
        Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        Write-Host ('[BIFROST_DEPENDENCY_OK] {0} {1} {2}' -f $dep.Publisher, $dep.Name, $dep.Version)
    }
}
catch {
    Write-Host ('[BIFROST_RUNTIME_ERROR] ' + $_.Exception.Message)
    exit 7
}
Write-Host '[BIFROST_DEPENDENCIES_OK]'
'@
}

function New-BifrostSelfTestApp {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][hashtable]$Entries,
        [switch]$NoNavxHeader
    )
    # Real packages are a 40-byte NAVX header followed by a zip. The reader must skip that header.
    $plain = $Path + '.zip'
    if (Test-Path -LiteralPath $plain) { Remove-Item -LiteralPath $plain -Force }
    $zip = [System.IO.Compression.ZipFile]::Open($plain, [System.IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($name in $Entries.Keys) {
            $entry = $zip.CreateEntry($name)
            $writer = New-Object System.IO.StreamWriter($entry.Open())
            try { $writer.Write([string]$Entries[$name]) } finally { $writer.Dispose() }
        }
    }
    finally { $zip.Dispose() }
    $raw = [System.IO.File]::ReadAllBytes($plain)
    Remove-Item -LiteralPath $plain -Force
    if ($NoNavxHeader) {
        [System.IO.File]::WriteAllBytes($Path, $raw)
        return $Path
    }
    $header = New-Object byte[] 40
    [System.Text.Encoding]::ASCII.GetBytes('NAVX').CopyTo($header, 0)
    $combined = New-Object byte[] ($header.Length + $raw.Length)
    [Array]::Copy($header, 0, $combined, 0, $header.Length)
    [Array]::Copy($raw, 0, $combined, $header.Length, $raw.Length)
    [System.IO.File]::WriteAllBytes($Path, $combined)
    return $Path
}

function New-BifrostSelfTestZip {
    param(
        [Parameter(Mandatory = $true)][string]$ZipPath,
        [Parameter(Mandatory = $true)][hashtable]$Files
    )
    if (Test-Path -LiteralPath $ZipPath) { Remove-Item -LiteralPath $ZipPath -Force }
    $zip = [System.IO.Compression.ZipFile]::Open($ZipPath, [System.IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($name in $Files.Keys) {
            $entry = $zip.CreateEntry($name)
            $inputStream = [System.IO.File]::OpenRead($Files[$name])
            $outputStream = $entry.Open()
            try { $inputStream.CopyTo($outputStream) } finally { $outputStream.Dispose(); $inputStream.Dispose() }
        }
    }
    finally { $zip.Dispose() }
    return $ZipPath
}

function Invoke-BifrostRuntimePackageSelfTest {
    $failed = [System.Collections.Generic.List[string]]::new()
    $script:selfTestAssertions = 0
    function Assert-True {
        param([bool]$Condition, [string]$Message)
        $script:selfTestAssertions++
        if (-not $Condition) { $failed.Add($Message) }
    }
    $root = Join-Path ([System.IO.Path]::GetTempPath()) ('bifrost-runtime-package-' + [guid]::NewGuid().ToString('n'))
    New-Item -ItemType Directory -Path $root -Force | Out-Null
    try {
        $productDir = Join-Path $root 'repo/app'
        $testDir = Join-Path $root 'repo/test'
        New-Item -ItemType Directory -Path $productDir -Force | Out-Null
        New-Item -ItemType Directory -Path $testDir -Force | Out-Null
        $productJson = Join-Path $productDir 'app.json'
        $testJson = Join-Path $testDir 'app.json'
        @{
            name = 'Bifrost Foundation'
            publisher = 'Origo'
            version = '28.0.11.0'
            application = '28.0.0.0'
            id = '7505e808-6e52-4b96-a328-82573391297a'
        } | ConvertTo-Json | Set-Content -LiteralPath $productJson -Encoding utf8
        @{
            name = 'Bifrost Foundation - Tests'
            publisher = 'Origo'
            version = '28.0.11.0'
            application = '28.0.0.0'
        } | ConvertTo-Json | Set-Content -LiteralPath $testJson -Encoding utf8

        $identity = Get-BifrostAppIdentity $productJson
        $layout = Get-BifrostRuntimePackageLayout -Identity $identity
        Assert-True ($layout.BlobPath -eq 'bc28/Bifrost Foundation/Origo_Bifrost Foundation_runtime.zip') "blob path was $($layout.BlobPath)"
        Assert-True ($layout.PublicUrl -eq 'https://origopublic.blob.core.windows.net/runtime/bc28/Bifrost%20Foundation/Origo_Bifrost%20Foundation_runtime.zip') "public url was $($layout.PublicUrl)"
        Assert-True ($layout.InnerAppFileName -eq 'Origo_Bifrost Foundation_runtime.app') 'inner app name'
        Assert-True ($layout.BcMajor -eq '28') 'major is 28 for this app'
        Assert-True ($layout.PublicUrl -notmatch 'bc29') 'current foundation layout must not use bc29'

        $later = Get-BifrostAppIdentity $productJson
        $later.ApplicationMajor = '29'
        $laterLayout = Get-BifrostRuntimePackageLayout -Identity $later
        Assert-True ($laterLayout.BlobPath.StartsWith('bc29/')) "future application major must be bc29, got $($laterLayout.BlobPath)"

        $refused = $false
        try { Get-BifrostAppIdentity $testJson | Out-Null } catch { $refused = $true }
        Assert-True $refused 'test app.json must be refused'

        Assert-True (Test-BifrostReleaseVersionMatch '28.0.11.0' '28.0.11') 'three-part release matches revision 0'
        Assert-True (Test-BifrostReleaseVersionMatch '28.0.10.632' '28.0.10') 'three-part release tag accepts the AL-Go revision'
        Assert-True (Test-BifrostReleaseVersionMatch '28.0.11.0' '28.0.11.0') 'exact version matches'
        Assert-True (Test-BifrostReleaseVersionMatch '28.0.10.632' '28.0.10.632') 'exact four-part revision matches'
        Assert-True (-not (Test-BifrostReleaseVersionMatch '28.0.10.632' '28.0.10.0')) 'a four-part expected version does not accept a different revision'
        Assert-True (-not (Test-BifrostReleaseVersionMatch '28.0.12.0' '28.0.11')) 'a different build does not match a three-part tag'
        Assert-True (-not (Test-BifrostReleaseVersionMatch '28.0.10.0' '28.0.11.0')) 'different release does not match'

        $manifest = @'
<?xml version="1.0" encoding="utf-8"?>
<Package xmlns="http://schemas.microsoft.com/navx/2015/manifest">
  <App Id="7505e808-6e52-4b96-a328-82573391297a" Name="Bifrost Foundation" Publisher="Origo" Version="28.0.11.669" Application="28.0.0.0" />
</Package>
'@
        # Synthetic ZIP layout fixture, NOT an exported Business Central runtime package.
        $runtimeApp = New-BifrostSelfTestApp -Path (Join-Path $root 'runtime.app') -Entries @{
            'NavxManifest.xml' = $manifest
            'Bifrost Foundation.runtime' = 'compiled'
        } -NoNavxHeader
        # The full release .app: same manifest plus AL source, the #1269 leak.
        $sourceApp = New-BifrostSelfTestApp -Path (Join-Path $root 'source.app') -Entries @{
            'NavxManifest.xml' = $manifest
            'src/src/Approval/ApprovalEvents.Codeunit.al' = 'codeunit 1 X {}'
            'src/src/Setup/Setup.Table.AL' = 'table 1 X {}'
        } -NoNavxHeader

        $headerFixture = New-BifrostSelfTestApp -Path (Join-Path $root 'header-only-layout.app') -Entries @{ 'NavxManifest.xml' = $manifest }
        Assert-True ((Get-BifrostZipOffset ([System.IO.File]::ReadAllBytes($headerFixture))) -eq 40) 'zip offset after a 40-byte NAVX header'
        $plainApp = New-BifrostSelfTestApp -Path (Join-Path $root 'plain.app') -Entries @{ 'NavxManifest.xml' = $manifest } -NoNavxHeader
        Assert-True ((Get-BifrostZipOffset ([System.IO.File]::ReadAllBytes($plainApp))) -eq 0) 'zip offset 0 without a header'
        $notApp = Join-Path $root 'not.app'
        [System.IO.File]::WriteAllBytes($notApp, [System.Text.Encoding]::ASCII.GetBytes('plain text, neither NAVX nor zip'))
        $notAppRefused = $false
        try { Get-BifrostAppSourceEntry -AppPath $notApp | Out-Null } catch { $notAppRefused = $_.Exception.Message -match 'PK' }
        Assert-True $notAppRefused 'a file without a zip local header and without an encrypted payload must be refused'

        # The exact malformed inputs from Worker review #6660287800, plus random NAVX bytes.
        $encBytes = New-Object byte[] 4096
        (New-Object System.Random 42).NextBytes($encBytes)
        [System.Text.Encoding]::ASCII.GetBytes('NAVX').CopyTo($encBytes, 0)
        $invalidInputs = @{
            'navx-only' = [System.Text.Encoding]::ASCII.GetBytes('NAVX')
            'navx-plaintext' = [System.Text.Encoding]::ASCII.GetBytes('NAVXcodeunit 50100 Plaintext {}')
            'navx-random' = $encBytes
        }
        foreach ($case in $invalidInputs.Keys) {
            $invalidPath = Join-Path $root ($case + '.app')
            [System.IO.File]::WriteAllBytes($invalidPath, $invalidInputs[$case])
            $invalidZipPath = Join-Path $root ($case + '-packed.zip')
            $refused = $false
            try { New-BifrostRuntimePackageZip -RuntimeAppPath $invalidPath -ZipPath $invalidZipPath -InnerAppFileName 'invalid_runtime.app' -Identity $identity -ExpectedVersion '28.0.11' | Out-Null } catch { $refused = $true }
            Assert-True $refused "$case must be refused before packaging"
            Assert-True (-not (Test-Path -LiteralPath $invalidZipPath)) "$case must not produce an output zip"
            $invalidReadback = New-BifrostSelfTestZip -ZipPath (Join-Path $root ($case + '-readback.zip')) -Files @{ 'invalid_runtime.app' = $invalidPath }
            $refused = $false
            try { Test-BifrostRuntimePackageZip -ZipPath $invalidReadback | Out-Null } catch { $refused = $true }
            Assert-True $refused "$case must also be refused on read-back"
        }
        # NAVX header with a zip hidden deep in the payload is not trusted as a runtime package.
        $hidden = New-Object byte[] 2048
        [System.Text.Encoding]::ASCII.GetBytes('NAVX').CopyTo($hidden, 0)
        $hidden[1500] = 0x50; $hidden[1501] = 0x4B; $hidden[1502] = 0x03; $hidden[1503] = 0x04
        $hiddenApp = Join-Path $root 'hidden.app'
        [System.IO.File]::WriteAllBytes($hiddenApp, $hidden)
        $hiddenRefused = $false
        try { Get-BifrostAppPackageKind $hiddenApp | Out-Null } catch { $hiddenRefused = $true }
        Assert-True $hiddenRefused 'a NAVX file with a late zip header is refused (fail closed)'
        $garbageApp = Join-Path $root 'garbage.app'
        [System.IO.File]::WriteAllBytes($garbageApp, (New-Object byte[] 64))
        $garbageRefused = $false
        try { Get-BifrostAppPackageKind $garbageApp | Out-Null } catch { $garbageRefused = $true }
        Assert-True $garbageRefused 'garbage without NAVX or zip is refused'

        $sourceEntries = @(Get-BifrostAppSourceEntry -AppPath $sourceApp)
        Assert-True ($sourceEntries.Count -eq 2) ("source entries found: " + ($sourceEntries -join ','))
        Assert-True (@(Get-BifrostAppSourceEntry -AppPath $runtimeApp).Count -eq 0) 'runtime package has no source entries'

        $outDir = Join-Path $root 'out'
        $packed = New-BifrostRuntimePackageZip -RuntimeAppPath $runtimeApp -ZipPath (Join-Path $outDir $layout.ZipFileName) -InnerAppFileName $layout.InnerAppFileName -Identity $identity -ExpectedVersion '28.0.11'
        Assert-True (Test-Path -LiteralPath $packed.ZipPath) 'zip exists'
        Assert-True ($packed.AlEntries -eq 0) 'packed zip reports 0 .al entries'
        $zip = [System.IO.Compression.ZipFile]::OpenRead($packed.ZipPath)
        try { $entries = @($zip.Entries | ForEach-Object { $_.FullName }) } finally { $zip.Dispose() }
        Assert-True ($entries.Count -eq 1 -and $entries[0] -like '*_runtime.app') ("zip entries: " + ($entries -join ','))

        $sourceRefused = $false
        $sourceZipPath = Join-Path $outDir 'source.zip'
        try {
            New-BifrostRuntimePackageZip -RuntimeAppPath $sourceApp -ZipPath $sourceZipPath -InnerAppFileName $layout.InnerAppFileName -Identity $identity -ExpectedVersion '28.0.11' | Out-Null
        }
        catch {
            $sourceRefused = $true
            Assert-True ($_.Exception.Message -match 'AL source') "source refusal message: $($_.Exception.Message)"
            Assert-True ($_.Exception.Message -match 'Get-NAVAppRuntimePackage') 'source refusal names Get-NAVAppRuntimePackage'
            Assert-True ($_.Exception.Message -match '\b2 AL source') 'source refusal counts the .al entries'
        }
        Assert-True $sourceRefused 'an input .app with .al entries must be refused'
        Assert-True (-not (Test-Path -LiteralPath $sourceZipPath)) 'no zip is written for a refused source .app'

        $bad = $false
        try {
            New-BifrostRuntimePackageZip -RuntimeAppPath $runtimeApp -ZipPath (Join-Path $outDir 'bad.zip') -InnerAppFileName $layout.InnerAppFileName -Identity $identity -ExpectedVersion '28.0.10.0' | Out-Null
        }
        catch { $bad = $true }
        Assert-True $bad 'wrong release version must fail'

        # Read-back verification, as the workflow runs it on the anonymous download.
        $verified = Test-BifrostRuntimePackageZip -ZipPath $packed.ZipPath -InnerAppFileName $layout.InnerAppFileName -Identity $identity -ExpectedVersion '28.0.11'
        Assert-True ($verified.Verified -and $verified.AlEntries -eq 0 -and $verified.ManifestVersion -eq '28.0.11.669') 'verify accepts the packed runtime zip'
        $verifiedAny = Test-BifrostRuntimePackageZip -ZipPath $packed.ZipPath
        Assert-True ($verifiedAny.InnerAppFileName -eq $layout.InnerAppFileName) 'verify without app.json finds the *_runtime.app'

        $leakZip = New-BifrostSelfTestZip -ZipPath (Join-Path $outDir 'leak.zip') -Files @{ $layout.InnerAppFileName = $sourceApp }
        $leakRefused = $false
        try { Test-BifrostRuntimePackageZip -ZipPath $leakZip -InnerAppFileName $layout.InnerAppFileName | Out-Null }
        catch { $leakRefused = $_.Exception.Message -match 'AL source' }
        Assert-True $leakRefused 'verify must refuse a published zip whose .app has .al entries (the 28.0.11 blob)'

        $twoZip = New-BifrostSelfTestZip -ZipPath (Join-Path $outDir 'two.zip') -Files @{ $layout.InnerAppFileName = $runtimeApp; 'extra.app' = $runtimeApp }
        $twoRefused = $false
        try { Test-BifrostRuntimePackageZip -ZipPath $twoZip | Out-Null } catch { $twoRefused = $true }
        Assert-True $twoRefused 'verify must refuse a zip with more than one entry'

        $wrongVersionRefused = $false
        try { Test-BifrostRuntimePackageZip -ZipPath $packed.ZipPath -InnerAppFileName $layout.InnerAppFileName -Identity $identity -ExpectedVersion '28.0.12' | Out-Null } catch { $wrongVersionRefused = $true }
        Assert-True $wrongVersionRefused 'verify must refuse a zip for another release'

        $hashRefused = $false
        try { Test-BifrostRuntimePackageZip -ZipPath $packed.ZipPath -ExpectedRuntimeSha256 ('0' * 64) | Out-Null } catch { $hashRefused = $true }
        Assert-True $hashRefused 'read-back must refuse bytes different from the validated export'

        if ($RuntimeFixturePath) {
            # Only a real Get-NAVAppRuntimePackage export may serve as a positive runtime fixture.
            $native = Get-BifrostNativePackageInfo $RuntimeFixturePath
            Assert-True ($native.PackageKind -eq 'runtime') 'genuine exported fixture is a BC runtime package'
            Assert-True ($native.Sources.Count -eq 0) 'genuine exported fixture has no source paths'
            $realPacked = New-BifrostRuntimePackageZip -RuntimeAppPath $RuntimeFixturePath -ZipPath (Join-Path $root 'genuine.zip') -InnerAppFileName 'genuine_runtime.app' -Identity $native.Identity -ExpectedVersion $native.Identity.Version
            $realVerified = Test-BifrostRuntimePackageZip -ZipPath $realPacked.ZipPath -Identity $native.Identity -ExpectedVersion $native.Identity.Version -ExpectedRuntimeSha256 $realPacked.RuntimeSha256
            Assert-True ($realVerified.Verified -and $realVerified.PackageKind -eq 'runtime' -and $realVerified.ManifestVersion -eq $native.Identity.Version) 'genuine runtime packs and verifies with matching identity and export hash'
            # A truncated genuine export must fail the native reader, not become source-free.
            $truncatedPath = Join-Path $root 'truncated-runtime.app'
            $bytes = [System.IO.File]::ReadAllBytes($RuntimeFixturePath)
            [System.IO.File]::WriteAllBytes($truncatedPath, $bytes[0..([int]($bytes.Length / 2))])
            $refused = $false
            try { Get-BifrostNativePackageInfo $truncatedPath | Out-Null } catch { $refused = $true }
            Assert-True $refused 'truncated genuine runtime package must be refused'
        }

        # Upload request: application/zip, never curl's form-urlencoded default.
        $curlArgs = Get-BifrostBlobPutCurlArgument -ZipPath $packed.ZipPath -UploadUrl 'https://example.invalid/x'
        $curlJoined = $curlArgs -join ' '
        Assert-True ($curlJoined -match 'Content-Type: application/zip') 'upload sends Content-Type application/zip'
        Assert-True ($curlJoined -match 'x-ms-blob-content-type: application/zip') 'upload sets the blob content type'
        Assert-True ($curlJoined -match 'x-ms-blob-type: BlockBlob') 'upload is a block blob'
        Assert-True ($curlJoined -notmatch 'x-www-form-urlencoded') 'upload must not send the form content type'

        $secret = 'super-secret-sas-value'
        $signed = "https://origopublic.blob.core.windows.net/runtime/bc28/x?sig=$secret&se=2026"
        $redacted = Protect-BifrostLogText -Text "upload $signed token $secret AccountKey=abc" -SecretValues @($secret)
        Assert-True ($redacted -notmatch [regex]::Escape($secret)) "redaction leaked the secret: $redacted"
        Assert-True ($redacted -notmatch 'AccountKey=abc') "account key leaked: $redacted"
        Assert-True ($redacted -match '\[redacted\]') 'redaction marker missing'
        Assert-True ($redacted -notmatch '\?sig=') "query signature leaked: $redacted"

        $envName = 'BIFROST_RUNTIME_STORAGE_CREDENTIAL_SELFTEST'
        [Environment]::SetEnvironmentVariable($envName, "sig=$secret")
        $script:seenUrl = $null
        $result = Publish-BifrostRuntimePackageBlob -ZipPath $packed.ZipPath -PublicUrl $layout.PublicUrl -CredentialEnvName $envName -UploadHandler {
            param($zipPath, $uploadUrl)
            $script:seenUrl = $uploadUrl
            return 201
        }
        Assert-True ($result.Uploaded -eq $true -and $result.StatusCode -eq 201) 'upload handler result'
        Assert-True ($result.PublicUrl -eq $layout.PublicUrl) 'public url has no query'
        Assert-True ($result.PublicUrl -notmatch 'sig=') 'result public url contains a signature'
        $info = Protect-BifrostLogText -Text $script:seenUrl -SecretValues @("sig=$secret", $secret)
        Assert-True ($info -notmatch [regex]::Escape($secret)) 'handler url could not be redacted'
        [Environment]::SetEnvironmentVariable($envName, $null)

        $missing = $false
        try {
            Publish-BifrostRuntimePackageBlob -ZipPath $packed.ZipPath -PublicUrl $layout.PublicUrl -CredentialEnvName 'BIFROST_RUNTIME_STORAGE_CREDENTIAL_ABSENT' | Out-Null
        }
        catch {
            $missing = $true
            Assert-True ($_.Exception.Message -notmatch 'sig=') 'missing-credential error leaked a signature'
            Assert-True ($_.Exception.Message -match 'BIFROST_RUNTIME_STORAGE_CREDENTIAL_ABSENT') 'missing-credential error names the env var'
        }
        Assert-True $missing 'empty credential must fail closed'

        # Review AMEND on #1448, blocker 1: manifest values never become code. Strict identity rules.
        $goodId = '7505e808-6e52-4b96-a328-82573391297a'
        foreach ($okName in @('Bifrost Foundation', 'IS Core', 'Amazon via Bifrost', ('Bifr' + [char]0x00F6 + 'st ' + [char]0x00CD + 'sland ' + [char]0x00DE + 'j' + [char]0x00F3 + 'nusta'), 'Quality_Management-2.0')) {
            Assert-True (Test-BifrostSafeName $okName) "safe name refused: $okName"
        }
        $hostileNames = @('Evil $(Write-Host pwned)', 'Back`tick', 'Quote"d', "Single'quote", 'semi;colon', 'pipe|name', ('new' + "`n" + 'line'), '', ' leading space', '-dash first', ('x' * 101), 'curly{brace}', ('Bifrost' + [char]0x00E4))
        foreach ($badName in $hostileNames) {
            Assert-True (-not (Test-BifrostSafeName $badName)) "hostile name accepted: $($badName.Length) chars"
            $nameRefused = $false
            try { Assert-BifrostSafeIdentity -Id $goodId -Name $badName -Publisher 'Origo' -Version '28.0.11.669' } catch { $nameRefused = $_.Exception.Message -notmatch [regex]::Escape('pwned') }
            Assert-True $nameRefused 'hostile dependency name must be refused without echoing it'
            $publisherRefused = $false
            try { Assert-BifrostSafeIdentity -Id $goodId -Name 'Bifrost Foundation' -Publisher $badName -Version '28.0.11.669' } catch { $publisherRefused = $true }
            Assert-True $publisherRefused "hostile publisher must be refused: $($badName.Length) chars"
        }
        foreach ($badVersion in @('28.0.11', '28.0.11.669;x', '28.0.11.$(1)', 'a.b.c.d', '')) {
            $versionRefused = $false
            try { Assert-BifrostSafeIdentity -Id $goodId -Name 'Bifrost Foundation' -Publisher 'Origo' -Version $badVersion } catch { $versionRefused = $true }
            Assert-True $versionRefused "bad version accepted: $badVersion"
        }
        $idRefused = $false
        try { Assert-BifrostSafeIdentity -Id 'not-a-guid' -Name 'Bifrost Foundation' -Publisher 'Origo' -Version '28.0.11.669' } catch { $idRefused = $true }
        Assert-True $idRefused 'a non-GUID id must be refused'
        Assert-BifrostSafeIdentity -Id $goodId -Name 'Bifrost Foundation' -Publisher 'Origo' -Version '28.0.11.669'
        Assert-True $true 'a normal identity passes'

        # A runtime manifest that lists a hostile dependency is refused before anything is installed.
        $hostileManifest = @'
<?xml version="1.0" encoding="utf-8"?>
<Package xmlns="http://schemas.microsoft.com/navx/2015/manifest">
  <App Id="7505e808-6e52-4b96-a328-82573391297a" Name="Bifrost Foundation" Publisher="Origo" Version="28.0.11.669" Application="28.0.0.0" />
  <Dependencies>
    <Dependency Id="11111111-2222-3333-4444-555555555555" Name="Evil $(Write-Host pwned) `b &quot;x" Publisher="Origo" MinVersion="28.0.0.0" />
  </Dependencies>
</Package>
'@
        $hostileApp = New-BifrostSelfTestApp -Path (Join-Path $root 'hostile-dependency.app') -Entries @{ 'NavxManifest.xml' = $hostileManifest } -NoNavxHeader
        $hostileIdentity = Get-NavxAppIdentity $hostileApp
        Assert-True (@($hostileIdentity.Dependencies).Count -eq 1 -and $hostileIdentity.Dependencies[0].Name -like 'Evil $(*') 'manifest dependencies are read from NavxManifest.xml'
        $hostileRefused = $false
        try { Assert-BifrostDependencyManifest -Manifest $hostileIdentity } catch { $hostileRefused = $_.Exception.Message -notmatch 'pwned' }
        Assert-True $hostileRefused 'a manifest with a hostile dependency name must be refused without echoing it'

        # The install script is fixed text that takes data, not generated code.
        $installScript = Get-BifrostDependencyInstallScript
        $installTokens = $null
        $installErrors = $null
        [void][System.Management.Automation.Language.Parser]::ParseInput($installScript, [ref]$installTokens, [ref]$installErrors)
        Assert-True (@($installErrors).Count -eq 0) 'the dependency install script parses'
        Assert-True ($installScript -match 'param\(\[Parameter\(Mandatory = \$true\)\]\[string\]\$DataPath\)') 'the dependency install script takes a data file'
        Assert-True ($installScript -notmatch 'Invoke-Expression|iex |\[scriptblock\]::Create|Add-Type') 'the dependency install script never evaluates text'

        # Blocker 2: a dependency must be a genuine runtime package, not a zip with only a manifest.
        $manifestOnlyApp = New-BifrostSelfTestApp -Path (Join-Path $root 'manifest-only.app') -Entries @{ 'NavxManifest.xml' = $manifest } -NoNavxHeader
        $manifestOnlyZip = New-BifrostSelfTestZip -ZipPath (Join-Path $root 'manifest-only-dependency.zip') -Files @{ 'Origo_Bifrost Foundation_runtime.app' = $manifestOnlyApp }
        $plainVerified = Test-BifrostRuntimePackageZip -ZipPath $manifestOnlyZip
        Assert-True ($plainVerified.Verified -and $plainVerified.AlEntries -eq 0 -and $plainVerified.PackageKind -eq 'zip') 'the manifest-only fixture passes the plain source-free check (the review case)'
        $plainRefused = $false
        try { Test-BifrostDependencyRuntimeZip -ZipPath $manifestOnlyZip | Out-Null } catch { $plainRefused = $_.Exception.Message -match 'not a genuine Business Central runtime package' }
        Assert-True $plainRefused 'a manifest-only zip must be refused as a dependency runtime package'
        if ($RuntimeFixturePath) {
            $genuineZip = New-BifrostSelfTestZip -ZipPath (Join-Path $root 'genuine-dependency.zip') -Files @{ ('{0}_{1}_runtime.app' -f (Get-NavxAppIdentity $RuntimeFixturePath).Publisher, (Get-NavxAppIdentity $RuntimeFixturePath).Name) = $RuntimeFixturePath }
            $genuine = Test-BifrostDependencyRuntimeZip -ZipPath $genuineZip
            Assert-True ($genuine.PackageKind -eq 'runtime') 'a genuine runtime package is accepted as a dependency'
        }

        # Release order: an older tag never replaces a newer public runtime (worker reviews on the app copies).
        $order = Get-BifrostVersionOrderDecision -PublishedVersion $null -NewVersion '28.0.11.669'
        Assert-True ($order.Allowed -and $order.Reason -eq 'none-published') 'no public zip (404): upload'
        $order = Get-BifrostVersionOrderDecision -PublishedVersion '28.0.13.741' -NewVersion '28.0.14.1'
        Assert-True ($order.Allowed -and $order.Reason -eq 'newer') 'a newer version replaces the public one'
        $order = Get-BifrostVersionOrderDecision -PublishedVersion '28.0.13.741' -NewVersion '28.0.13.741'
        Assert-True ($order.Allowed -and $order.Reason -eq 'same-version-rebuild') 'the same version may be uploaded again'
        $order = Get-BifrostVersionOrderDecision -PublishedVersion '28.0.13.741' -NewVersion '28.0.11.669'
        Assert-True (-not $order.Allowed -and $order.Reason -eq 'older') 'an older version must not replace a newer one'
        $order = Get-BifrostVersionOrderDecision -PublishedVersion '28.0.13.741' -NewVersion '28.0.13.740'
        Assert-True (-not $order.Allowed) 'an older revision of the same build must not replace a newer one'
        $order = Get-BifrostVersionOrderDecision -PublishedVersion '28.0.10.632' -NewVersion '28.0.9.999'
        Assert-True (-not $order.Allowed) 'versions compare numerically, not as text'
        $order = Get-BifrostVersionOrderDecision -PublishedVersion '28.0.13.741' -NewVersion '28.0.11.669' -AllowOlder
        Assert-True ($order.Allowed -and $order.Reason -eq 'older-allowed') 'allowOlder rolls back on purpose'
        $threePartRefused = $false
        try { Get-BifrostVersionOrderDecision -PublishedVersion '28.0.13.741' -NewVersion '28.0.14' | Out-Null } catch { $threePartRefused = $true }
        Assert-True $threePartRefused 'the published version must have four parts'

        # Newer-then-older end to end: the public zip holds 28.0.13.741, an older 28.0.11.669 run is refused.
        $newerManifest = $manifest.Replace('Version="28.0.11.669"', 'Version="28.0.13.741"')
        $newerApp = New-BifrostSelfTestApp -Path (Join-Path $root 'published-newer.app') -Entries @{ 'NavxManifest.xml' = $newerManifest; 'Bifrost Foundation.runtime' = 'compiled' } -NoNavxHeader
        $publishedZip = New-BifrostSelfTestZip -ZipPath (Join-Path $root 'published-newer.zip') -Files @{ 'Origo_Bifrost Foundation_runtime.app' = $newerApp }
        $olderRefused = $false
        try { Test-BifrostPublishedVersionOrder -PublishedZipPath $publishedZip -AppJsonPath $productJson -NewVersion '28.0.11.669' | Out-Null }
        catch { $olderRefused = $_.Exception.Message -match '28\.0\.13\.741' -and $_.Exception.Message -match '28\.0\.11\.669' }
        Assert-True $olderRefused 'an older run is refused against a newer public zip, naming both versions'
        $same = Test-BifrostPublishedVersionOrder -PublishedZipPath $publishedZip -AppJsonPath $productJson -NewVersion '28.0.13.741'
        Assert-True ($same.Allowed -and $same.PublishedVersion -eq '28.0.13.741') 'a rebuild of the public version is allowed'
        $newer = Test-BifrostPublishedVersionOrder -PublishedZipPath $publishedZip -AppJsonPath $productJson -NewVersion '28.0.14.1'
        Assert-True ($newer.Allowed -and $newer.Reason -eq 'newer') 'a newer run replaces the public zip'
        $rollback = Test-BifrostPublishedVersionOrder -PublishedZipPath $publishedZip -AppJsonPath $productJson -NewVersion '28.0.11.669' -AllowOlder
        Assert-True ($rollback.Allowed -and $rollback.Reason -eq 'older-allowed') 'allowOlder lets an older run replace the public zip'
        $otherApp = New-BifrostSelfTestApp -Path (Join-Path $root 'published-other.app') -Entries @{ 'NavxManifest.xml' = $newerManifest.Replace('Name="Bifrost Foundation"', 'Name="Bifrost Iceland"'); 'x.runtime' = 'compiled' } -NoNavxHeader
        $otherZip = New-BifrostSelfTestZip -ZipPath (Join-Path $root 'published-other.zip') -Files @{ 'Origo_Bifrost Iceland_runtime.app' = $otherApp }
        $otherRefused = $false
        try { Test-BifrostPublishedVersionOrder -PublishedZipPath $otherZip -AppJsonPath $productJson -NewVersion '28.0.14.1' | Out-Null } catch { $otherRefused = $_.Exception.Message -match 'not Origo Bifrost Foundation' }
        Assert-True $otherRefused 'a public zip of another app is not silently replaced'
        $brokenZip = Join-Path $root 'published-broken.zip'
        [System.IO.File]::WriteAllBytes($brokenZip, [System.Text.Encoding]::ASCII.GetBytes('not a zip'))
        $brokenRefused = $false
        try { Test-BifrostPublishedVersionOrder -PublishedZipPath $brokenZip -AppJsonPath $productJson -NewVersion '28.0.14.1' | Out-Null } catch { $brokenRefused = $_.Exception.Message -match 'could not be verified' }
        Assert-True $brokenRefused 'an unverifiable public zip is not replaced without allowOlder'
        $brokenAllowed = Test-BifrostPublishedVersionOrder -PublishedZipPath $brokenZip -AppJsonPath $productJson -NewVersion '28.0.14.1' -AllowOlder
        Assert-True ($brokenAllowed.Allowed -and $brokenAllowed.Reason -eq 'none-published') 'allowOlder replaces an unverifiable public zip'

        # Blocker 3: one location rule for publisher and dependant.
        $folderRefused = $false
        try { Get-BifrostRuntimePackageLayout -Identity $identity -FolderName 'bc-origo-bifrost-core' | Out-Null } catch { $folderRefused = $_.Exception.Message -match 'always stored under the app name' }
        Assert-True $folderRefused 'a folder name other than the app name must be refused'
        $sameFolder = Get-BifrostRuntimePackageLayout -Identity $identity -FolderName 'Bifrost Foundation'
        Assert-True ($sameFolder.PublicUrl -eq $layout.PublicUrl) 'a folder name equal to the app name is the canonical location'
        $located = Get-BifrostRuntimeLocation -Id $goodId -Name 'Bifrost Foundation' -Publisher 'Origo' -Version '28.0.11.669' -BcMajor '28'
        Assert-True ($located.PublicUrl -eq $layout.PublicUrl) "the dependant computes the publisher's URL, got $($located.PublicUrl)"
        $locateRefused = $false
        try { Get-BifrostRuntimeLocation -Id $goodId -Name 'Evil $(x)' -Publisher 'Origo' -Version '28.0.11.669' -BcMajor '28' | Out-Null } catch { $locateRefused = $true }
        Assert-True $locateRefused 'locating a hostile name must be refused'
    }
    finally {
        if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
    }
    if ($failed.Count -gt 0) {
        $failed | ForEach-Object { Write-Error $_ -ErrorAction Continue }
        exit 1
    }
    Write-Output ("SelfTest passed: $script:selfTestAssertions assertions, 0 failed. Genuine runtime fixture supplied: $([bool]$RuntimeFixturePath). Layout, identity, malformed input/source refusal, ZIP/read-back/hash verification, upload headers, redaction, identity rules, dependency runtime kind, location and release order.")
    exit 0
}

if ($SelfTest) {
    Invoke-BifrostRuntimePackageSelfTest
}

if ($Locate) {
    Get-BifrostRuntimeLocation -Id $LocateId -Name $LocateName -Publisher $LocatePublisher -Version $LocateVersion -BcMajor $BcMajor | ConvertTo-Json -Compress
    exit 0
}

if (-not [string]::IsNullOrWhiteSpace($WriteDependencyInstallScript)) {
    [System.IO.File]::WriteAllText($WriteDependencyInstallScript, ((Get-BifrostDependencyInstallScript) -replace "`r?`n", "`r`n"))
    exit 0
}

if (-not [string]::IsNullOrWhiteSpace($VerifyZipPath)) {
    Invoke-BifrostRuntimeZipVerification | ConvertTo-Json -Compress
    exit 0
}

$result = Invoke-BifrostRuntimePackage
$result | ConvertTo-Json -Compress
