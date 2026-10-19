<#
.SYNOPSIS
Runs real-artifact collision/selection tests; does not certify runner or signature trust.
#>
param(
    [Parameter(Mandatory)][string] $ArtifactFolder,
    [Parameter(Mandatory)][string] $FixtureFolder,
    [Parameter(Mandatory)][string] $CandidateArtifactFolder
)
$ErrorActionPreference = 'Stop'
$previousArtifacts = $env:FOUNDATION_STAGING_ARTIFACTS
$previousFixtures = $env:APPSOURCE_GATE_FIXTURES
$previousCandidateArtifacts = $env:FOUNDATION_CANDIDATE_ARTIFACTS
try {
    $env:FOUNDATION_STAGING_ARTIFACTS = (Resolve-Path -LiteralPath $ArtifactFolder).Path
    $env:APPSOURCE_GATE_FIXTURES = (Resolve-Path -LiteralPath $FixtureFolder).Path
    $env:FOUNDATION_CANDIDATE_ARTIFACTS = (Resolve-Path -LiteralPath $CandidateArtifactFolder).Path
    $python = Get-Command python3 -ErrorAction SilentlyContinue
    if (-not $python) { $python = Get-Command python -ErrorAction Stop }
    & $python.Source -m unittest discover -s (Join-Path $PSScriptRoot 'tests') -p 'test_foundation_staging.py' -v
    if ($LASTEXITCODE -ne 0) { throw 'Foundation staging regression checks failed.' }
}
finally {
    $env:FOUNDATION_STAGING_ARTIFACTS = $previousArtifacts
    $env:APPSOURCE_GATE_FIXTURES = $previousFixtures
    $env:FOUNDATION_CANDIDATE_ARTIFACTS = $previousCandidateArtifacts
}
