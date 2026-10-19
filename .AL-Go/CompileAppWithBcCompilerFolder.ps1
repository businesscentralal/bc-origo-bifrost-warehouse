param([hashtable] $CompilationParams)

$ErrorActionPreference = 'Stop'

function Enable-LinuxCompilerManifestStamps {
    # BcContainerHelper 6.1.19 stamps /SourceCommit and /BuildUrl only when the compiler
    # file version is at least 12.0.12.41479. Linux ELF alc has no PE file version, so the
    # helper skips those arguments and the package commit does not match the run.
    if (-not ($IsLinux -or $IsMacOS)) {
        return
    }
    $command = Get-Command Compile-AppWithBcCompilerFolder -ErrorAction Stop
    $body = $command.Definition
    if ($body -match 'no PE file version') {
        return
    }
    $pattern = '(?m)^(?<indent>[ \t]*)\[System\.Version\]\$alcVersion = \$alcItem\.VersionInfo\.FileVersion\s*$'
    if ($body -notmatch $pattern) {
        if (-not $command.Module -and $body -notmatch 'alcItem') {
            return
        }
        throw 'BcContainerHelper compiler version assignment was not found; manifest stamps cannot be restored.'
    }
    $patched = [regex]::Replace($body, $pattern, {
            param($match)
            $indent = $match.Groups['indent'].Value
            @"
${indent}[System.Version]`$alcVersion = `$null
${indent}try { `$alcVersion = [System.Version]`$alcItem.VersionInfo.FileVersion } catch { `$alcVersion = `$null }
${indent}if (-not `$alcVersion -or `$alcVersion -lt [System.Version]'1.0.0.0') {
${indent}    # Linux ELF alc reports no PE file version, so the helper skips /SourceCommit and /BuildUrl.
${indent}    `$alcVersion = [System.Version]'12.0.12.41479'
${indent}}
"@
        })
    if ($command.Module) {
        # Export-ModuleMember snapshots the function. Replace the module copy and the exported command.
        $patchedBlock = $command.Module.NewBoundScriptBlock([scriptblock]::Create($patched))
        & $command.Module { param($block) ${function:script:Compile-AppWithBcCompilerFolder} = $block } $patchedBlock
        $field = $command.GetType().GetField('_scriptBlock', [System.Reflection.BindingFlags]'Instance,NonPublic')
        if (-not $field) {
            throw 'Cannot update the exported compiler function.'
        }
        $field.SetValue($command, $patchedBlock)
        return
    }
    Set-Item -Path 'function:global:Compile-AppWithBcCompilerFolder' -Value ([scriptblock]::Create($patched))
}

# Real helper callback installed by PipelineInitialize: capture inputs BEFORE its post-build copy
# puts the newly compiled product into the symbols folder. Forward every original
# parameter to the genuine helper; keep its error/exit behavior and output sink.
& (Join-Path $env:GITHUB_WORKSPACE 'tools/Assert-AppSourceBuild.ps1') -Stage BeforeCompile -CompilationParams $CompilationParams
$compileLog = Join-Path $env:GITHUB_WORKSPACE ".buildartifacts/AppSourceGate/$env:BuildMode/current-compile.txt"
[System.IO.File]::WriteAllText($compileLog, '')
$forwardOutput = $CompilationParams['OutputTo']
if (-not ($forwardOutput -is [scriptblock])) {
    throw 'Actual helper compiler output callback unavailable.'
}
$actual = $CompilationParams.Clone()
$actual.OutputTo = {
    param($Line)
    [System.IO.File]::AppendAllText($compileLog, ([string]$Line + [Environment]::NewLine), [System.Text.UTF8Encoding]::new($false))
    $forwardOutput.Invoke($Line) | Out-Null
}.GetNewClosure()
Enable-LinuxCompilerManifestStamps
Compile-AppWithBcCompilerFolder @actual
