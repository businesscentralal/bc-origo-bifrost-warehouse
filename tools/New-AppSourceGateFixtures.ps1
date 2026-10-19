<#
.SYNOPSIS
Compiles genuine isolated NAVX fixtures for the gate tests. Does not build product AL.
#>
param(
    [Parameter(Mandatory)][string] $CompilerDll,
    [Parameter(Mandatory)][string] $Dotnet,
    [Parameter(Mandatory)][string] $OutputFolder
)
$ErrorActionPreference = 'Stop'
$friend = @{ id = '6ae41d19-d457-4d62-bd87-0413ff18de75'; publisher = 'Origo'; name = 'Bifrost Warehouse - Tests' }
$cases = @{
    default = @()
    friend = @($friend)
    wrongFriend = @(@{ id = 'bb0cbfb3-44cf-43cd-9682-a850ba9bdfbb'; publisher = 'Origo'; name = 'Wrong Test Fixture' })
    testApp = @()
}
New-Item -ItemType Directory -Path $OutputFolder -Force | Out-Null
foreach ($name in $cases.Keys) {
    $project = Join-Path $OutputFolder $name
    New-Item -ItemType Directory -Path $project -Force | Out-Null
    $identity = if ($name -eq 'testApp') { $friend } else { @{ id = '1f5309ad-5362-4311-b599-a8fe190d63b0'; publisher = 'Origo'; name = 'Gate Fixture ori' } }
    $manifest = @{
        id = $identity.id
        publisher = $identity.publisher
        name = $identity.name
        version = '1.0.0.0'
        runtime = '17.0'
        target = 'Cloud'
        idRanges = @(@{ from = 50100; to = 50100 })
        internalsVisibleTo = $cases[$name]
    }
    $manifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $project 'app.json') -Encoding UTF8
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'fixtures/AppSourceGate/Fixture.Codeunit.al') -Destination $project
    $output = & $Dotnet $CompilerDll "/project:$project" "/out:$(Join-Path $OutputFolder "$name.app")" `
        '/sourceCommit:1111111111111111111111111111111111111111' '/buildBy:tooling-fixture' '/buildUrl:https://example.invalid/tooling-fixture' 2>&1
    $code = $LASTEXITCODE
    $output | Set-Content -LiteralPath (Join-Path $OutputFolder "$name.log") -Encoding UTF8
    if ($code -ne 0 -or -not (Test-Path -LiteralPath (Join-Path $OutputFolder "$name.app"))) {
        throw "Genuine compiler fixture $name failed ($code)."
    }
}
@{
    kind = 'Isolated tooling fixtures, not product/analyzer/runtime certification'
    compilerSha256 = (Get-FileHash -LiteralPath $CompilerDll -Algorithm SHA256).Hash.ToLowerInvariant()
    fixtureSourceSha256 = (Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'fixtures/AppSourceGate/Fixture.Codeunit.al') -Algorithm SHA256).Hash.ToLowerInvariant()
    generatedPackages = @($cases.Keys)
} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $OutputFolder 'provenance.json') -Encoding UTF8
