$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/SharedAlpacaContainer.ps1"
function Assert($Condition, $Message) { if (!$Condition) { throw $Message } }
function MustThrow([scriptblock] $Action, [string] $Message) {
    $threw = $false
    try { & $Action } catch { $threw = $true }
    Assert $threw $Message
}
$temp = Join-Path ([IO.Path]::GetTempPath()) ('bifrost-shared-tests-' + [guid]::NewGuid())
New-Item -ItemType Directory -Path $temp | Out-Null
$saved = @{}
foreach ($name in @('GITHUB_OUTPUT','GITHUB_ENV','_buildMode','BIFROST_EXPECTED_CONTAINER_ID','BIFROST_CONTAINER_ID','BIFROST_TEST_APP_PUBLISHED','ALPACA_CONTAINER_ID','ALPACA_BACKEND_URL')) { $saved[$name] = [Environment]::GetEnvironmentVariable($name) }
try {
    $settings = Get-Content -LiteralPath "$PSScriptRoot/../.AL-Go/settings.json" -Raw | ConvertFrom-Json
    $testSettings = @($settings.conditionalSettings | Where-Object { 'Test' -in $_.buildModes })
    $defaultSettings = @($settings.conditionalSettings | Where-Object { 'Default' -in $_.buildModes })
    Assert ($testSettings.settings.skipUpgrade -contains $true) 'Test must skip previous-release upgrade validation.'
    Assert (!$settings.skipUpgrade -and !($defaultSettings.settings.skipUpgrade -contains $true)) 'Default upgrade validation was disabled.'
    foreach ($hookPath in @('tools/Get-SharedAlpacaBuildOrder.ps1','tools/SharedAlpacaContainer.ps1','tools/Test-SharedAlpacaContainer.ps1')) {
        Assert (@($settings.fullBuildPatterns | Where-Object { $hookPath -like ($_ -replace '\\','/') }).Count -gt 0) "Changes to $hookPath must trigger a full build."
    }
    $env:GITHUB_OUTPUT = ''; $env:GITHUB_ENV = ''
    $dimension = @{project='.'; buildMode='Default'; githubRunner='["ubuntu-latest"]'; githubRunnerShell='pwsh'}
    $testDimension = $dimension.Clone(); $testDimension.buildMode = 'Test'
    $plan = @(@{projects=@('.');projectsCount=1;buildDimensions=@($dimension,$testDimension)})
    $json = ConvertTo-Json -InputObject $plan -Depth 10 -Compress
    $filtered = & "$PSScriptRoot/Get-SharedAlpacaBuildOrder.ps1" -BuildOrderJson $json | ConvertFrom-Json
    Assert ($filtered[0].buildDimensions.Count -eq 1 -and $filtered[0].buildDimensions[0].buildMode -eq 'Default') 'Creation plan did not filter Test.'
    $testDimension.githubRunnerShell = 'powershell'
    MustThrow { & "$PSScriptRoot/Get-SharedAlpacaBuildOrder.ps1" -BuildOrderJson (ConvertTo-Json -InputObject $plan -Depth 10 -Compress) } 'Mismatched runners were accepted.'
    $testDimension.githubRunnerShell = 'pwsh'; $testDimension.buildMode = 'Other'
    MustThrow { & "$PSScriptRoot/Get-SharedAlpacaBuildOrder.ps1" -BuildOrderJson (ConvertTo-Json -InputObject $plan -Depth 10 -Compress) } 'Unsupported modes were accepted.'
    # Mock the external control plane only; exercise real local adaptation and publish gates.
    function Import-Module { param($Name, $Scope, [switch]$DisableNameChecking) }
    function Get-AlpacaContainer { param($Project,$Token,$BuildMode) Assert ($BuildMode -eq 'Default') 'Wrong lookup mode'; @([pscustomobject]@{Id='shared-123'}) }
    $override = Join-Path $temp 'PipelineInitialize.ps1'
    '$buildMode = $env:_buildMode' | Set-Content $override
    $env:_buildMode = 'Test'; $env:BIFROST_EXPECTED_CONTAINER_ID = 'shared-123'
    Initialize-BifrostSharedContainer -OverridePath $override -ScriptsPath $temp -BackendUrl 'https://example.invalid/'
    Assert ($env:_buildMode -eq 'Test') 'Test compilation/dependency mode was changed.'
    Assert ((Get-Content $override -Raw).Contains('$buildMode = ''Default''')) 'Container override was not adapted.'
    $env:BIFROST_EXPECTED_CONTAINER_ID = 'wrong'
    MustThrow { Initialize-BifrostSharedContainer -OverridePath $override -ScriptsPath $temp -BackendUrl 'https://example.invalid/' } 'Wrong physical container was accepted.'
    $env:BIFROST_EXPECTED_CONTAINER_ID = 'shared-123'
    MustThrow { Initialize-BifrostSharedContainer -OverridePath $override -ScriptsPath $temp -BackendUrl 'https://example.invalid/' } 'Incompatible vendor initialization was accepted.'
    $mainAppPath = Join-Path $temp 'MainApp.app'; $testPath = Join-Path $temp 'Tests.app'
    function WriteFixture([string]$Path,[bool]$Grant) {
        $stream = [IO.File]::Create($Path)
        $zip = [IO.Compression.ZipArchive]::new($stream,[IO.Compression.ZipArchiveMode]::Create)
        $entry = $zip.CreateEntry('NavxManifest.xml')
        $writer = [IO.StreamWriter]::new($entry.Open())
        try { $writer.Write("<Package><App/><InternalsVisibleTo>$(if ($Grant) {'<App Id=""6ae41d19-d457-4d62-bd87-0413ff18de75""/>'})</InternalsVisibleTo></Package>") }
        finally { $writer.Dispose(); $zip.Dispose(); $stream.Dispose() }
    }
    WriteFixture $mainAppPath $true; WriteFixture $testPath $false
    $apps = @($mainAppPath)
    function GetCompilerFolder { 'mock-compiler' }
    function GetAppInfo {
        param($AppFiles,$compilerFolder)
        foreach ($file in $AppFiles) { [pscustomobject]@{Id=$(if ($file -eq $mainAppPath) {'47acac54-3873-496f-9e88-157f36413e89'} else {'6ae41d19-d457-4d62-bd87-0413ff18de75'}); Version='28.0.2.0'; Path=$file} }
    }
    function Get-AlpacaAppInfo { param($Token,$ContainerName) [pscustomobject]@{Id='47acac54-3873-496f-9e88-157f36413e89';Version='28.0.2.0'} }
    $calls = [Collections.Generic.List[string]]::new()
    $publisher = { param($Parameters) foreach ($file in $Parameters.appFile) { $calls.Add([IO.Path]::GetFileName($file)) } }
    $env:ALPACA_CONTAINER_ID = 'shared-123'; $env:BIFROST_TEST_APP_PUBLISHED = ''
    MustThrow { Invoke-BifrostSharedPublish -Parameters @{appFile=@($testPath)} -Publisher $publisher } 'Test app was deployed before MainApp.'
    Assert ($calls.Count -eq 0) 'Publisher was called despite the failed gate.'
    Invoke-BifrostSharedPublish -Parameters @{appFile=@($testPath,$mainAppPath)} -Publisher $publisher
    Assert (($calls -join ',') -eq 'MainApp.app,Tests.app') 'MainApp was not republished first in a mixed batch.'
    $env:BIFROST_TEST_APP_PUBLISHED = ''; $calls.Clear()
    WriteFixture $mainAppPath $false
    MustThrow { Invoke-BifrostSharedPublish -Parameters @{appFile=@($mainAppPath)} -Publisher $publisher } 'Missing compiled friend grant was accepted.'
    Assert ($calls.Count -eq 0) 'MainApp with no grant was published.'
    $env:_buildMode = 'Default'
    Invoke-BifrostSharedPublish -Parameters @{appFile=@($mainAppPath)} -Publisher $publisher
    Assert ($calls.Count -eq 1) 'Default publishing was changed.'
    Write-Host 'Shared Alpaca pipeline checks passed: plan validation, mode preservation, physical identity, compatibility guard, republish ordering, missing grant, and Default passthrough.'
} finally {
    foreach ($name in $saved.Keys) { [Environment]::SetEnvironmentVariable($name,$saved[$name]) }
    $resolved = (Resolve-Path -LiteralPath $temp).Path
    if ([IO.Path]::GetFileName($resolved) -notlike 'bifrost-shared-tests-*' -or [IO.Path]::GetDirectoryName($resolved).TrimEnd('\','/') -ne ([IO.Path]::GetTempPath()).TrimEnd('\','/')) { throw 'Unexpected test scratch path.' }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
