# Bifrost: never ship the test app's internalsVisibleTo grant.
# COSMO Alpaca replaces .AL-Go/PreCompileApp.ps1 with its own override and never calls ours,
# so the strip happens here, before anything compiles. Only the Test build mode keeps the grant.
if ($env:BuildMode -ne 'Test') {
    $appJsonPath = Join-Path $env:GITHUB_WORKSPACE 'app/app.json'
    if (Test-Path -LiteralPath $appJsonPath) {
        $appJson = Get-Content -LiteralPath $appJsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($appJson.PSObject.Properties.Name -contains 'internalsVisibleTo') {
            $appJson.PSObject.Properties.Remove('internalsVisibleTo')
        }
        if ($appJson.PSObject.Properties.Name -contains 'suppressWarnings') {
            $appJson.suppressWarnings = @($appJson.suppressWarnings | Where-Object { $_ -ne 'AS0081' })
        }
        $appJson | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $appJsonPath -Encoding UTF8
        Write-Host "Bifrost: build mode '$($env:BuildMode)' - removed internalsVisibleTo and the AS0081 suppression from app/app.json."
    }
}

Write-Host "::group::PipelineInitialize"

if (Test-Path -LiteralPath "$($env:NeedsContext)" -PathType Leaf) {
    Write-Host "Load Context from file at '$($env:NeedsContext)'"
    $needsContext = "$($env:NeedsContext)" | Get-Item | Get-Content -Raw | ConvertFrom-Json
}
else {
    Write-Host "Load Context from Json"
    $needsContext = "$($env:NeedsContext)" | ConvertFrom-Json
}

$initializationJob = $needsContext.'CustomJob-Alpaca-Initialization'

$scriptsPath = "./.alpaca/Scripts/"
$scriptsArchiveUrl = $initializationJob.outputs.scriptsArchiveUrl
$scriptsArchiveDirectory = $initializationJob.outputs.scriptsArchiveDirectory

Write-Host "Collect workflow jobs from context:"
$jobs = @{}
$jobIds = $initializationJob.outputs.jobIdsJson | ConvertFrom-Json
foreach ($jobId in $jobIds.PSObject.Properties.GetEnumerator()) {
    if ($needsContext.PSObject.Properties.Name -contains $jobId.Value) {
        Write-Host " - $($jobId.Name): $($jobId.Value)"
        $jobs[$jobId.Name] = $needsContext.$($jobId.Value)
    }
}
if ($jobs.Count -eq 0) {
    Write-Host " - None"
}

Write-Host "Prepare Alpaca scripts directory at '$scriptsPath'"
if (Test-Path -Path $scriptsPath) {
    Remove-Item -Path $scriptsPath -Recurse -Force
}
New-Item -Path $scriptsPath -ItemType Directory -Force | Out-Null

if ($scriptsArchiveUrl) {
    try {
        $tempPath = Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName())
        $tempArchivePath = "$tempPath.zip"

        Write-Host "Download Alpaca scripts archive from '$scriptsArchiveUrl'"
        Invoke-WebRequest -Uri $scriptsArchiveUrl -OutFile $tempArchivePath

        Write-Host "Extract Alpaca scripts archive"
        Expand-Archive -Path $tempArchivePath -DestinationPath $tempPath -Force

        Write-Host "Copy Alpaca scripts to '$scriptsPath'"
        Get-Item -Path (Join-Path $tempPath $scriptsArchiveDirectory) |
            Get-ChildItem |
            ForEach-Object {
                Copy-Item -Path $_.FullName -Destination $scriptsPath -Recurse -Force
            }
    }
    catch {
        throw
    }
    finally {
        if ($tempPath -and (Test-Path $tempPath)) {
            Remove-Item -Path $tempPath -Recurse -Force -ErrorAction SilentlyContinue
        }
        if ($tempArchivePath -and (Test-Path $tempArchivePath)) {
            Remove-Item -Path $tempArchivePath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Write-Host "Alpaca scripts found:"
$scriptFiles = Get-ChildItem -Path $scriptsPath -File -Recurse
if ($scriptFiles) {
    $scriptFiles | ForEach-Object {
        Write-Host "- $(Resolve-Path -Path $_.FullName -Relative)"
    }
} else {
    Write-Host "- None"
}

$overridesPath = Join-Path $scriptsPath "/Overrides/RunAlPipeline"
Write-Host "Alpaca overrides path: $overridesPath"
$overridePath = Join-Path $overridesPath "PipelineInitialize.ps1"
if (Test-Path $overridePath) {
    Write-Host "Invoking Alpaca override"
    . $overridePath -Jobs $jobs -ScriptsPath $scriptsPath
}

Write-Host "::endgroup::"
