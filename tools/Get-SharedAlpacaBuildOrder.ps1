param([Parameter(Mandatory)][string] $BuildOrderJson)
$ErrorActionPreference = 'Stop'
$order = @($BuildOrderJson | ConvertFrom-Json)
foreach ($group in $order) {
    $dimensions = @($group.buildDimensions)
    foreach ($project in @($dimensions.project | Select-Object -Unique)) {
        $pair = @($dimensions | Where-Object project -EQ $project)
        $default = @($pair | Where-Object buildMode -EQ 'Default')
        $test = @($pair | Where-Object buildMode -EQ 'Test')
        if ($pair.Count -ne 2 -or $default.Count -ne 1 -or $test.Count -ne 1) {
            throw "Shared-container builds require exactly Default and Test for project '$project'."
        }
        if ($default[0].githubRunner -ne $test[0].githubRunner -or $default[0].githubRunnerShell -ne $test[0].githubRunnerShell) {
            throw "Default and Test must use the same runner settings for project '$project'."
        }
    }
    $group.buildDimensions = @($dimensions | Where-Object buildMode -EQ 'Default')
}
$json = ConvertTo-Json -InputObject $order -Depth 100 -Compress
if ($env:GITHUB_OUTPUT) { Add-Content -Path $env:GITHUB_OUTPUT -Value "buildOrderJson=$json" }
else { $json }
