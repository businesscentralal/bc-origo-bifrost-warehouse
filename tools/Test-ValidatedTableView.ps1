<#
.SYNOPSIS
    Fails when the app applies a caller's tableView without validating it first.

.DESCRIPTION
    Record.SetView and RecordRef.SetView silently ignore a field name that does not exist, so a
    mistyped filter widens the result instead of failing (#78, #139). Every SetView on a value that
    is not a string literal must therefore sit in a procedure that also calls ValidateTableView or
    ApplyTableView ("Message Argument ori"), which answer InvalidFilterField and fail closed.

    The guard reads every .al file under app/src, splits it into procedures and fails on any
    procedure that calls .SetView( with a non-literal argument and has neither call. A SetView whose
    argument the caller has already validated is allowed when the line above it carries the marker
    comment "// tableView validated by the caller".

.PARAMETER AppFolder
    The AL app folder (default: ../app next to this script).

.EXAMPLE
    ./tools/Test-ValidatedTableView.ps1
#>
param(
    [string]$AppFolder = (Join-Path $PSScriptRoot '..\app')
)

$ErrorActionPreference = 'Stop'
$sourceFolder = Join-Path $AppFolder 'src'
$procedureStart = [regex]::new('^\s*(\[[^\]]*\]\s*)*((local|internal|protected)\s+)?(procedure|trigger)\s', 'IgnoreCase')
$setView = [regex]::new("\.SetView\(\s*(?!'[^']*'\s*\))", 'IgnoreCase')
$validation = [regex]::new('\b(ValidateTableView|ApplyTableView)\(', 'IgnoreCase')
$marker = [regex]::new('//\s*tableView validated by the caller', 'IgnoreCase')

$violations = @()
Get-ChildItem -LiteralPath $sourceFolder -Recurse -Filter '*.al' | ForEach-Object {
    $file = $_
    $lines = @(Get-Content -LiteralPath $file.FullName -Encoding UTF8)
    $relative = [System.IO.Path]::GetRelativePath($AppFolder, $file.FullName)

    # Collect procedures as [start, end) line ranges.
    $starts = @()
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($procedureStart.IsMatch($lines[$i])) { $starts += $i }
    }
    for ($p = 0; $p -lt $starts.Count; $p++) {
        $from = $starts[$p]
        $to = if ($p + 1 -lt $starts.Count) { $starts[$p + 1] } else { $lines.Count }
        $body = $lines[$from..($to - 1)]
        $validated = ($body | Where-Object { $validation.IsMatch($_) }).Count -gt 0
        for ($i = $from; $i -lt $to; $i++) {
            if (-not $setView.IsMatch($lines[$i])) { continue }
            if ($lines[$i].TrimStart().StartsWith('//')) { continue }
            if ($validated) { continue }
            if ($i -gt 0 -and $marker.IsMatch($lines[$i - 1])) { continue }
            $violations += "${relative}:$($i + 1): $($lines[$i].Trim())"
        }
    }
}

if ($violations.Count -gt 0) {
    Write-Host "::error::A tableView is applied without ValidateTableView/ApplyTableView ($($violations.Count) line(s)). Validate it first so an unknown field fails closed (#139)."
    $violations | ForEach-Object { Write-Host $_ }
    exit 1
}
Write-Host 'Every applied tableView is validated first.'
