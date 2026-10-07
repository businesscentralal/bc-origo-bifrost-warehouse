param([string] $ProjectPath = (Split-Path -Parent $PSScriptRoot))

$ErrorActionPreference = 'Stop'
$failures = [Collections.Generic.List[string]]::new()

function Require([bool] $Condition, [string] $Message) {
    if (!$Condition) { $failures.Add($Message) }
}

function Read-ProjectFile([string] $RelativePath) {
    Get-Content -LiteralPath (Join-Path $ProjectPath $RelativePath) -Raw
}

# Read the existing indentation-based AL-Go job layout. Unexpected layout fails
# the contract checks instead of accepting a template update without review.
function Get-YamlBlock([string] $Text, [string] $Key, [int] $Indent) {
    $lines = $Text -split '\r?\n'
    $pattern = '^' + (' ' * $Indent) + [regex]::Escape($Key) + ':[ \t]*(?:#.*)?$'
    for ($index = 0; $index -lt $lines.Count; $index++) {
        if ($lines[$index] -notmatch $pattern) { continue }
        $end = $index + 1
        while ($end -lt $lines.Count) {
            $line = $lines[$end]
            if ($line.Trim() -and ($line.Length - $line.TrimStart().Length) -le $Indent) { break }
            $end++
        }
        return ($lines[$index..($end - 1)] -join "`n")
    }
    return ''
}

foreach ($workflowName in @('CICD.yaml', 'PullRequestHandler.yaml')) {
    $workflow = Read-ProjectFile ".github/workflows/$workflowName"
    $build = Get-YamlBlock $workflow 'Build' 2
    $initialization = Get-YamlBlock $workflow 'Initialization' 2
    $create = Get-YamlBlock $workflow 'CustomJob-CreateAlpaca-Container' 2
    $cleanup = Get-YamlBlock $workflow 'CustomJob-RemoveAlpaca-Container' 2
    Require ($build -match 'uses: \./\.github/workflows/_BuildSharedALGoProject\.yaml') "$workflowName must call the sequential Default/Test workflow."
    Require ($build -match 'include:.*sharedBuildOrderJson') "$workflowName must build the filtered per-project plan."
    Require ($initialization -match 'sharedBuildOrderJson:' -and $initialization -match 'id: sharedPlan' -and $initialization -match 'Get-SharedAlpacaBuildOrder\.ps1') "$workflowName must generate and expose the shared creation plan."
    Require ($create -match 'buildOrderJson:.*sharedBuildOrderJson') "$workflowName must create only the shared Default container."
    Require ($cleanup -match 'if: always\(\)' -and $cleanup -match "CustomJob-Alpaca-Initialization.result == 'success'" -and $cleanup -match "CustomJob-CreateAlpaca-Container.result != 'skipped'") "$workflowName must clean up after partial creation, failed builds and cancellation."
    foreach ($variableName in @('ALGoOrgSettings', 'ALGoRepoSettings')) {
        Require ($workflow -match ('(?m)^  ' + $variableName + ':')) "$workflowName must retain $variableName."
    }
    if ($workflowName -eq 'CICD.yaml') { Require ($build -match 'signArtifacts: true') 'CI/CD must request signing of the Default artifacts.' }
}

$wrapper = Read-ProjectFile '.github/workflows/_BuildSharedALGoProject.yaml'
$default = Get-YamlBlock $wrapper 'Default' 2
$test = Get-YamlBlock $wrapper 'Test' 2
Require ($default -match 'buildMode: Default' -and $default -match 'sharedContainer: true') 'Default must retain the shared container.'
Require ($test -match 'needs:\s*\[ Default \]' -and $test -match 'buildMode: Test') 'Test must wait for successful Default.'
Require ($test -match 'expectedContainerId:.*needs.Default.outputs.containerId' -and $test -match 'sharedContainer: true') 'Test must reuse the physical container reported by Default.'

$phase = Read-ProjectFile '.github/workflows/_BuildALGoProject.yaml'
$on = Get-YamlBlock $phase 'on' 0
$call = Get-YamlBlock $on 'workflow_call' 2
$inputs = Get-YamlBlock $call 'inputs' 4
$outputs = Get-YamlBlock $call 'outputs' 4
Require ($inputs -match '(?m)^      sharedContainer:' -and $inputs -match '(?m)^      expectedContainerId:') 'The phase workflow must accept the shared-container inputs.'
Require ($outputs -match '(?m)^      containerId:' -and $phase -match 'containerId=\$\(\$env:BIFROST_CONTAINER_ID\)') 'Default must expose its physical container identity.'
Require ($phase -match 'BIFROST_SHARED_CONTAINER:.*inputs.sharedContainer' -and $phase -match 'BIFROST_EXPECTED_CONTAINER_ID:.*inputs.expectedContainerId') 'The build step must pass the shared identity variables to the pipeline.'
Require ($phase -match 'Test-SharedAlpacaContainer\.ps1') 'The build must execute the functional shared-container checks.'
$phaseCleanup = Get-YamlBlock $phase 'CustomJob-Alpaca-RemoveContainers' 2
Require ($phaseCleanup -match '!inputs.sharedContainer') 'Shared phases must defer cleanup until both phases finish.'

$parseTokens = $null; $parseErrors = $null
$pipelineAst = [Management.Automation.Language.Parser]::ParseInput((Read-ProjectFile '.AL-Go/PipelineInitialize.ps1'), [ref]$parseTokens, [ref]$parseErrors)
Require ($parseErrors.Count -eq 0) 'PipelineInitialize.ps1 must parse.'
$pipelineCalls = @($pipelineAst.FindAll({ param($node) $node -is [Management.Automation.Language.CommandAst] }, $true) | ForEach-Object { $_.GetCommandName() })
Require ('Initialize-BifrostSharedContainer' -in $pipelineCalls) 'Initialization must select and verify the shared container.'
Require ('Invoke-BifrostSharedPublish' -in $pipelineCalls) 'Publishing must enforce Test production-app republish before the test app.'
$pipelineVariables = @($pipelineAst.FindAll({ param($node) $node -is [Management.Automation.Language.VariableExpressionAst] }, $true) | ForEach-Object { $_.VariablePath.UserPath })
# Feature apps strip before Alpaca initialization; Orchestrator chains PreCompileApp instead.
$initialStrip = (Read-ProjectFile '.AL-Go/PipelineInitialize.ps1') -split 'Write-Host "::group::PipelineInitialize"', 2 | Select-Object -First 1
$stripsBeforeInitialization = $initialStrip -match '(?m)^if \(\$env:BuildMode -ne ''Test''\)' -and $initialStrip -match "Properties\.Remove\('internalsVisibleTo'\)" -and $initialStrip -match 'Set-Content -LiteralPath \$appJsonPath'
$chainsCompileHook = 'AlGoPreCompileApp' -in $pipelineVariables -and 'BifrostAlpacaPreCompileApp' -in $pipelineVariables
Require ($stripsBeforeInitialization -or $chainsCompileHook) 'Default must retain its early internals strip or original compile-hook chain.'

$sync = Read-ProjectFile '.github/workflows/_AlpacaSyncConfigs.yaml'
$readSettings = $sync.IndexOf('/ReadSettings@', [StringComparison]::Ordinal)
$readSecrets = $sync.IndexOf('/ReadSecrets@', [StringComparison]::Ordinal)
Require ($readSettings -ge 0 -and $readSecrets -gt $readSettings) 'Settings sync must load merged settings before reading secrets.'

$settings = Read-ProjectFile '.AL-Go/settings.json' | ConvertFrom-Json
$testSettings = @($settings.conditionalSettings | Where-Object { 'Test' -in $_.buildModes })
$defaultSettings = @($settings.conditionalSettings | Where-Object { 'Default' -in $_.buildModes })
Require ($testSettings.settings.skipUpgrade -contains $true) 'Test must skip deployment of the previous release.'
Require (!$settings.skipUpgrade -and !($defaultSettings.settings.skipUpgrade -contains $true)) 'Default must retain upgrade validation.'

if ($failures.Count) { throw ("Bifrost pipeline contract failed:`n- " + ($failures -join "`n- ")) }
Write-Host 'Bifrost pipeline contract passed: sequential builds, shared identity, Test republish wiring, production internals stripping, cleanup, signing request, settings sync and upgrade modes.'
