<#
.SYNOPSIS
Checks actual callback/collector/native-process return and failure plumbing.
Controlled verifier/compiler fixtures do not certify AL, helper runtime or BC.
#>
$ErrorActionPreference = 'Stop'
$source = Split-Path $PSScriptRoot -Parent
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('warehouse-callback-' + [guid]::NewGuid())
$names = @('GITHUB_WORKSPACE','GITHUB_RUN_ID','GITHUB_RUN_ATTEMPT','GITHUB_JOB','GITHUB_SHA','BuildMode','Settings')
$saved = @{}
foreach ($name in $names) { $saved[$name] = [Environment]::GetEnvironmentVariable($name) }
$count = 0
function Assert-Contract($Condition, $Message) { if (-not $Condition) { throw $Message } }
try {
    New-Item -ItemType Directory -Path (Join-Path $fixture 'tools') -Force | Out-Null
    Copy-Item (Join-Path $source 'tools/Assert-AppSourceBuild.ps1') (Join-Path $fixture 'tools/Assert-AppSourceBuild.ps1')
    $restoreStub = "print('{""action"": ""absent"", ""restored"": []}')`nprint('restore-status-must-not-return')"
    [IO.File]::WriteAllText((Join-Path $fixture 'tools/stage_foundation_inputs.py'), $restoreStub)
    $env:GITHUB_WORKSPACE = $fixture
    $env:GITHUB_RUN_ID = 'fixture'; $env:GITHUB_RUN_ATTEMPT = '1'; $env:GITHUB_JOB = 'callback-fixture'; $env:GITHUB_SHA = 'a' * 40
    $env:Settings = @{enableCodeCop=$true;enableUICop=$true;enableCodeAnalyzersOnTestApps=$true;failOn='warning';workspaceCompilation=@{enabled=$false};type='AppSource App'} | ConvertTo-Json
    function global:git { 'a' * 40; $global:LASTEXITCODE = 0 }
    $script:compilerCalls = 0
    $script:throwCompiler = $false
    function global:Compile-AppWithBcCompilerFolder {
        param([scriptblock] $OutputTo, [string] $appProjectFolder, [string] $appSymbolsFolder, [string] $compilerFolder,
              [bool] $CopyAppToSymbolsFolder, [string] $GenerateReportLayout, [bool] $enableCodeCop, [bool] $enableUICop,
              [bool] $enableAppSourceCop, [bool] $enablePerTenantExtensionCop, [string] $failOn)
        $script:compilerCalls++
        $script:forwarded = $PSBoundParameters
        $OutputTo.Invoke('compiler-line-one') | Out-Null
        $OutputTo.Invoke('compiler-line-two') | Out-Null
        if ($script:throwCompiler) { throw 'original-compiler-failure' }
        'original-package.app'
    }
    $callback = (Get-Command (Join-Path $source '.AL-Go/CompileAppWithBcCompilerFolder.ps1')).ScriptBlock
    foreach ($mode in 'Default','Test') {
        $env:BuildMode = $mode
        $directory = Join-Path $fixture ".buildartifacts/AppSourceGate/$mode"
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
        foreach ($translation in $true,$false) {
            # Actual native Python process, exact CLI success text; no package verdict.
            [IO.File]::WriteAllText((Join-Path $fixture 'tools/appsource_gate.py'), "print('AppSource gate: before passed')")
            $script:received = @()
            $sink = {param($Line) $script:received += $Line; 'sink-output-must-not-return'}
            $parameters = @{OutputTo=$sink;appProjectFolder=$fixture;appSymbolsFolder=$fixture;compilerFolder=$fixture;
                CopyAppToSymbolsFolder=(-not $translation);GenerateReportLayout=$(if ($translation) {'No'} else {'Yes'});
                enableCodeCop=(-not $translation);enableUICop=(-not $translation);enableAppSourceCop=(-not $translation);
                enablePerTenantExtensionCop=$false;failOn='warning'}
            $returned = @(Invoke-Command -ScriptBlock $callback -ArgumentList $parameters)
            Assert-Contract ($returned.Count -eq 1 -and $returned[0] -ceq 'original-package.app') 'Callback polluted original package return'
            Assert-Contract ($parameters.OutputTo -eq $sink -and $script:forwarded.OutputTo -ne $sink) 'Original parameters mutated or output not wrapped'
            foreach ($key in $parameters.Keys) {
                if ($key -ne 'OutputTo') { Assert-Contract ($script:forwarded[$key] -eq $parameters[$key]) "Parameter forwarding changed: $key" }
            }
            Assert-Contract (($script:received -join '|') -ceq 'compiler-line-one|compiler-line-two') 'Original sink lost output'
            Assert-Contract (([IO.File]::ReadAllLines((Join-Path $directory 'current-compile.txt')) -join '|') -ceq 'compiler-line-one|compiler-line-two') 'Isolated log differs'
            $count++
            foreach ($silentOrInvalid in @(
                '# Truncated gate module: definitions only, no entry point.',
                "print('AppSource gate: post passed')",
                "print('AppSource gate: before passed')`nprint('unexpected extra output')",
                "print('appsource gate: before passed')"
            )) {
                [IO.File]::WriteAllText((Join-Path $fixture 'tools/appsource_gate.py'), $silentOrInvalid)
                $callsBefore = $script:compilerCalls
                $refused = $false
                try { Invoke-Command -ScriptBlock $callback -ArgumentList $parameters | Out-Null }
                catch { $refused = $_.Exception.Message -ceq 'AppSource before validation did not return the expected completion marker.' }
                Assert-Contract ($refused -and $script:compilerCalls -eq $callsBefore) 'Zero-exit verifier without exact completion marker reached compiler'
                Assert-Contract (-not (Test-Path (Join-Path $fixture '.buildartifacts/AppSourceGate/request.json'))) 'Invalid-marker request cleanup failed'
                $count++
            }
            [IO.File]::WriteAllText((Join-Path $fixture 'tools/appsource_gate.py'), "print('AppSource gate: before passed')")
            $script:throwCompiler = $true
            $preserved = $false
            try { Invoke-Command -ScriptBlock $callback -ArgumentList $parameters | Out-Null } catch { $preserved = $_.Exception.Message -ceq 'original-compiler-failure' }
            Assert-Contract $preserved 'Original compiler exception replaced/suppressed'
            $script:throwCompiler = $false
            $count++
            [IO.File]::WriteAllText((Join-Path $fixture 'tools/appsource_gate.py'), "import sys`nprint('native-refusal', file=sys.stderr)`nsys.exit(7)")
            $callsBefore = $script:compilerCalls
            $refused = $false
            try { Invoke-Command -ScriptBlock $callback -ArgumentList $parameters | Out-Null } catch { $refused = $_.Exception.Message -ceq 'AppSource before validation failed.' }
            Assert-Contract ($refused -and $script:compilerCalls -eq $callsBefore) 'Native verifier failure did not refuse before compiler'
            Assert-Contract (-not (Test-Path (Join-Path $fixture '.buildartifacts/AppSourceGate/request.json'))) 'Native request cleanup failed'
            $count++
        }
    }
    [IO.File]::WriteAllText((Join-Path $fixture 'tools/stage_foundation_inputs.py'), "import sys`nprint('restore-refused', file=sys.stderr)`nsys.exit(4)")
    [IO.File]::WriteAllText((Join-Path $fixture 'tools/appsource_gate.py'), "print('AppSource gate: before passed')")
    $callsBefore = $script:compilerCalls
    $refused = $false
    try { Invoke-Command -ScriptBlock $callback -ArgumentList $parameters | Out-Null }
    catch { $refused = $_.Exception.Message -ceq 'Foundation candidate restore failed.' }
    Assert-Contract ($refused -and $script:compilerCalls -eq $callsBefore) 'Foundation restore failure reached the compiler'
    [IO.File]::WriteAllText((Join-Path $fixture 'tools/stage_foundation_inputs.py'), $restoreStub)
    $count++
    New-Item -ItemType Directory -Path (Join-Path $fixture '.AL-Go') -Force | Out-Null
    Copy-Item (Join-Path $source '.AL-Go/CompileAppWithBcCompilerFolder.ps1') (Join-Path $fixture '.AL-Go/CompileAppWithBcCompilerFolder.ps1')
    [IO.File]::WriteAllText((Join-Path $fixture 'tools/appsource_gate.py'), "print('AppSource gate: before passed')")
    $initialize = Get-Content (Join-Path $source '.AL-Go/PipelineInitialize.ps1') -Raw
    $installer = [scriptblock]::Create($initialize.Substring($initialize.IndexOf('function Set-AppSourceCompilerCallback')))
    $module = New-Module -Name AppSourceCallbackFixture -ScriptBlock {
        function Invoke-HelperFixture {
            param([scriptblock] $PipelineInitialize, [scriptblock] $CompileAppWithBcCompilerFolder)
            Invoke-Command -ScriptBlock $PipelineInitialize
            if (-not $CompileAppWithBcCompilerFolder) { throw 'Callback not installed in helper scope' }
            $folder = $env:GITHUB_WORKSPACE
            $buildOutputFile = Join-Path $folder 'BuildOutput.txt'
            $output = {param($line)
                Write-Host $line
                if ($line -like "$($folder)*") { Add-Content $buildOutputFile $line.SubString($folder.Length+1) }
                else { Add-Content $buildOutputFile $line }
            }
            $parameters = @{OutputTo=$output;appProjectFolder=$folder;appSymbolsFolder=$folder;compilerFolder=$folder;CopyAppToSymbolsFolder=$true}
            Invoke-Command -ScriptBlock $CompileAppWithBcCompilerFolder -ArgumentList $parameters
        }
        Export-ModuleMember -Function Invoke-HelperFixture
    }
    Import-Module $module
    $returned = @(Invoke-HelperFixture -PipelineInitialize $installer)
    Assert-Contract ($returned.Count -eq 1 -and $returned[0] -ceq 'original-package.app') 'Module callback return changed'
    Assert-Contract (([IO.File]::ReadAllLines((Join-Path $fixture 'BuildOutput.txt')) -join '|') -ceq 'compiler-line-one|compiler-line-two') 'Helper dynamic output sink lost scope'
    $count++
    $refused = $false
    try { Invoke-HelperFixture -PipelineInitialize $installer -CompileAppWithBcCompilerFolder {'foreign.app'} | Out-Null }
    catch { $refused = $_.Exception.Message -like 'Existing compiler-folder override*' }
    Assert-Contract $refused 'Existing owner callback displaced'
    $count++
    Write-Host "Callback regressions: $count passed, 0 failed; actual PowerShell callback/collector and native Python, controlled compiler/verifier. No AL/runtime certification."
} finally {
    foreach ($name in $names) { [Environment]::SetEnvironmentVariable($name, $saved[$name]) }
    Remove-Item Function:\git, Function:\Compile-AppWithBcCompilerFolder -ErrorAction SilentlyContinue
    Remove-Module AppSourceCallbackFixture -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $fixture -Recurse -Force
}
