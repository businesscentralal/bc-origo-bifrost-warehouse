<#
.SYNOPSIS
    Fails when the app returns or documents an AL call stack to a caller.

.DESCRIPTION
    Since #138 an error response never carries the call stack: RespondWithLastError and
    "Message Error ori" log it to telemetry (event ORI-BIF-0180) instead. This guard keeps it that way.
    It fails on any line under app/src that

      - adds or replaces a "callstack" property on a JSON object (.Add('callstack' / .Replace('callstack',
        any casing), or
      - puts "callstack" into help text (HelpBuilder.AppendLine).

    The telemetry codeunit (app/src/Setup/Telemetry) is allowed to name the callStack dimension.

.PARAMETER AppFolder
    The AL app folder (default: ../app next to this script).

.EXAMPLE
    ./tools/Test-NoClientCallstack.ps1
#>
param(
    [string]$AppFolder = (Join-Path $PSScriptRoot '..\app')
)

$ErrorActionPreference = 'Stop'
$sourceFolder = Join-Path $AppFolder 'src'
$telemetryFolder = [System.IO.Path]::GetFullPath((Join-Path $sourceFolder 'Setup/Telemetry'))
$jsonProperty = [regex]::new("\.(Add|Replace)\(\s*'callstack'", 'IgnoreCase')
$helpText = [regex]::new("HelpBuilder\.Append(Line)?\(.*callstack", 'IgnoreCase')

$violations = @()
Get-ChildItem -LiteralPath $sourceFolder -Recurse -Filter '*.al' | ForEach-Object {
    $file = $_
    if ([System.IO.Path]::GetFullPath($file.FullName).StartsWith($telemetryFolder)) {
        return
    }
    $lineNo = 0
    foreach ($line in (Get-Content -LiteralPath $file.FullName -Encoding UTF8)) {
        $lineNo++
        if ($jsonProperty.IsMatch($line) -or $helpText.IsMatch($line)) {
            $relative = [System.IO.Path]::GetRelativePath($AppFolder, $file.FullName)
            $violations += "${relative}:${lineNo}: $($line.Trim())"
        }
    }
}

if ($violations.Count -gt 0) {
    Write-Host "::error::A call stack is returned or documented to callers ($($violations.Count) line(s)). Log it with Telemetry ori.LogErrorCallStack instead (#138)."
    $violations | ForEach-Object { Write-Host $_ }
    exit 1
}
Write-Host 'No call stack is returned or documented to callers.'
