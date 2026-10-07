# Adapt only container selection. _buildMode/BuildMode, settings, dependency downloads,
# compilation and artifact names remain mode-specific. Called after downloading Alpaca v2.11.
function Initialize-BifrostSharedContainer {
    param([string] $OverridePath, [string] $ScriptsPath, [string] $BackendUrl)
    if ($env:_buildMode -notin @('Default', 'Test')) { throw 'Unsupported shared-container build mode.' }
    $env:ALPACA_BACKEND_URL = $BackendUrl
    Import-Module (Join-Path $ScriptsPath 'Modules/Alpaca.psd1') -Scope Global -DisableNameChecking
    $containers = @(Get-AlpacaContainer -Project $env:_project -Token $env:_token -BuildMode Default)
    if ($containers.Count -ne 1) { throw "Expected exactly one shared Default container; found $($containers.Count). Rerun all jobs to recreate the pair." }
    if ($env:_buildMode -eq 'Test' -and (!$env:BIFROST_EXPECTED_CONTAINER_ID -or $containers[0].Id -ne $env:BIFROST_EXPECTED_CONTAINER_ID)) {
        throw 'Test must reuse the physical container reported by Default. Rerun all jobs if it has been removed.'
    }
    $source = Get-Content -LiteralPath $OverridePath -Raw
    $assignment = '$buildMode = $env:_buildMode'
    if ([regex]::Matches($source, [regex]::Escape($assignment)).Count -ne 1) {
        throw 'Alpaca initialization changed: cannot safely adapt container selection.'
    }
    # This local variable is used only by the container lookup/creation in v2.11.
    # Dependency downloads read _buildMode separately and must continue to use Test.
    $source.Replace($assignment, '$buildMode = ''Default'' # Bifrost shared container') |
        Set-Content -LiteralPath $OverridePath -Encoding utf8
    $env:BIFROST_CONTAINER_ID = [string] $containers[0].Id
    $env:BIFROST_TEST_APP_PUBLISHED = ''
    if ($env:GITHUB_ENV) { Add-Content -Path $env:GITHUB_ENV -Value "BIFROST_CONTAINER_ID=$($env:BIFROST_CONTAINER_ID)" }
    Write-Host "Bifrost shared container: phase=$($env:_buildMode), id=$($env:BIFROST_CONTAINER_ID), container mode=Default."
}

function Read-BifrostCompiledManifest {
    param([string] $Path)
    $bytes = [IO.File]::ReadAllBytes($Path)
    $offset = -1
    for ($i = 0; $i -lt [Math]::Min($bytes.Length - 4, 65536); $i++) {
        if ($bytes[$i] -eq 0x50 -and $bytes[$i+1] -eq 0x4B -and $bytes[$i+2] -eq 3 -and $bytes[$i+3] -eq 4) { $offset = $i; break }
    }
    if ($offset -lt 0) { throw 'Compiled app has no readable NAVX archive.' }
    $stream = [IO.MemoryStream]::new($bytes, $offset, $bytes.Length - $offset, $false)
    $zip = [IO.Compression.ZipArchive]::new($stream, [IO.Compression.ZipArchiveMode]::Read)
    try {
        $entry = $zip.GetEntry('NavxManifest.xml')
        if (!$entry) { throw 'Compiled app has no NavxManifest.xml.' }
        $reader = [IO.StreamReader]::new($entry.Open())
        try { return [xml] $reader.ReadToEnd() } finally { $reader.Dispose() }
    } finally { $zip.Dispose(); $stream.Dispose() }
}

function Invoke-BifrostSharedPublish {
    param([hashtable] $Parameters, [scriptblock] $Publisher)
    if ($env:_buildMode -ne 'Test') { Invoke-Command -ScriptBlock $Publisher -ArgumentList $Parameters; return }
    $mainAppId = '47acac54-3873-496f-9e88-157f36413e89'
    $testId = '6ae41d19-d457-4d62-bd87-0413ff18de75'
    # AL-Go calls this for dependencies, previous releases and compiled outputs.
    # Only the freshly compiled MainApp can authorize deploying our test app.
    $requested = @(GetAppInfo -AppFiles $Parameters.appFile -compilerFolder (GetCompilerFolder))
    $compiled = @($apps | Where-Object { $_ } | ForEach-Object { (Resolve-Path -LiteralPath $_).Path })
    $mainApp = @($requested | Where-Object { $_.Id -eq $mainAppId -and (Resolve-Path -LiteralPath $_.Path).Path -in $compiled })
    $containsTest = @($requested | Where-Object Id -EQ $testId).Count -gt 0
    if ($containsTest -and !$env:BIFROST_TEST_APP_PUBLISHED -and $mainApp.Count -eq 0) {
        throw 'Cannot publish the test app before republishing the freshly compiled Test MainApp.'
    }
    # Publish MainApp separately even if it shares a batch with the test app.
    foreach ($app in $mainApp) {
        $manifest = Read-BifrostCompiledManifest -Path $app.Path
        $grants = @($manifest.SelectNodes("//*[local-name()='InternalsVisibleTo']/*") | ForEach-Object { $_.GetAttribute('Id') })
        if ($testId -notin $grants) { throw 'Test MainApp is missing the compiled internalsVisibleTo grant.' }
        $mainAppParameters = $Parameters.Clone()
        $mainAppParameters.appFile = @($app.Path)
        $mainAppParameters.checkAlreadyInstalled = $false
        $mainAppParameters.ignoreIfAppExists = $false
        Write-Host "Bifrost: republishing Test MainApp $($app.Version) on shared container $($env:ALPACA_CONTAINER_ID), SHA256=$((Get-FileHash -LiteralPath $app.Path -Algorithm SHA256).Hash)."
        Invoke-Command -ScriptBlock $Publisher -ArgumentList $mainAppParameters
        $installed = @(Get-AlpacaAppInfo -Token $env:_token -ContainerName $env:ALPACA_CONTAINER_ID | Where-Object { $_.Id -eq $mainAppId -and [version] $_.Version -eq [version] $app.Version })
        if ($installed.Count -eq 0) { throw 'MainApp was not reported by the container after Test republish.' }
        $env:BIFROST_TEST_APP_PUBLISHED = $env:ALPACA_CONTAINER_ID
        Write-Host 'Bifrost: Test MainApp republish completed; the test app may now be deployed.'
    }
    if ($containsTest -and $env:BIFROST_TEST_APP_PUBLISHED -ne $env:ALPACA_CONTAINER_ID) { throw 'Test MainApp was republished on a different container.' }
    # Alpaca publishes output apps even at the same version via the developer endpoint.
    # Do not send MainApp twice when we have already published it above.
    $remaining = @($requested | Where-Object { $_ -notin $mainApp } | ForEach-Object Path)
    if ($remaining.Count -gt 0) {
        $remainingParameters = $Parameters.Clone()
        $remainingParameters.appFile = $remaining
        Invoke-Command -ScriptBlock $Publisher -ArgumentList $remainingParameters
    }
}
