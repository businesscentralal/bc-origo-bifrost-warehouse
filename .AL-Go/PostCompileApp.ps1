param(
    [string[]] $AppFile,
    [string] $AppType,
    [hashtable] $CompilationParams
)

# Run-AlPipeline passes returned package, app type and FINAL parameters positionally.
# Alpaca translation precompiles do not invoke this hook and cannot satisfy it.
& (Join-Path $env:GITHUB_WORKSPACE 'tools/Assert-AppSourceBuild.ps1') `
    -Stage PostCompile -AppFile $AppFile -AppType $AppType -CompilationParams $CompilationParams
