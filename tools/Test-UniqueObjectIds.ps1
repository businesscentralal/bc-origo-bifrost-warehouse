<#
.SYNOPSIS
Checks object IDs by type and enum value IDs across extensions of the same enum.
#>
param(
    [string]$AppFolder = (Join-Path $PSScriptRoot '../app'),
    [switch]$SelfTest
)
$ErrorActionPreference = 'Stop'

function Find-Collisions([string]$Folder) {
    $objects = @{}
    $values = @{}
    $problems = [System.Collections.Generic.List[string]]::new()
    foreach ($file in Get-ChildItem $Folder -Recurse -Filter '*.al') {
        $source = Get-Content $file.FullName -Raw
        $source = [regex]::Replace($source, '(?s)/\*.*?\*/', '')
        $source = [regex]::Replace($source, '(?m)^\s*//.*$', '')
        $object = [regex]::Match($source, '(?im)^\s*(table|tableextension|page|pageextension|report|reportextension|codeunit|xmlport|query|enum|enumextension|permissionset|permissionsetextension)\s+(\d+)\s+"([^"]+)"')
        if (-not $object.Success) { continue }
        $key = $object.Groups[1].Value.ToLowerInvariant() + ':' + $object.Groups[2].Value
        if ($objects.ContainsKey($key)) { $problems.Add("object ${key}: $($objects[$key]) / $($file.Name)") }
        else { $objects[$key] = $file.Name }
        $enum = [regex]::Match($source, '(?im)^\s*enum(?:extension)?\s+\d+\s+"([^"]+)"(?:\s+extends\s+"([^"]+)")?')
        if (-not $enum.Success) { continue }
        $target = $enum.Groups[1].Value
        if ($enum.Groups[2].Success) { $target = $enum.Groups[2].Value }
        foreach ($value in [regex]::Matches($source, '(?im)^\s*value\s*\(\s*(\d+)\s*;')) {
            $key = $target + ':' + $value.Groups[1].Value
            if ($values.ContainsKey($key)) { $problems.Add("enum value ${key}: $($values[$key]) / $($file.Name)") }
            else { $values[$key] = $file.Name }
        }
    }
    return $problems.ToArray()
}

if ($SelfTest) {
    $fixture = Join-Path ([System.IO.Path]::GetTempPath()) ('warehouse-id-' + [guid]::NewGuid().ToString('N'))
    New-Item $fixture -ItemType Directory | Out-Null
    try {
        Set-Content (Join-Path $fixture 'A.al') 'codeunit 70013521 "A ori" {}'
        Set-Content (Join-Path $fixture 'B.al') 'codeunit 70013521 "B ori" {}'
        if (@(Find-Collisions $fixture).Count -ne 1) { throw 'Duplicate codeunit ID was not detected.' }
        Set-Content (Join-Path $fixture 'B.al') 'table 70013521 "B ori" {}'
        if (@(Find-Collisions $fixture).Count -ne 0) { throw 'Separate object type ID spaces were conflated.' }
        Set-Content (Join-Path $fixture 'C.al') "enumextension 70013510 `"C ori`" extends `"Message Type ori`" {`n value(70013516; A) {}`n}"
        Set-Content (Join-Path $fixture 'D.al') "enumextension 70013511 `"D ori`" extends `"Message Type ori`" {`n value(70013516; B) {}`n}"
        if (@(Find-Collisions $fixture).Count -ne 1) { throw 'Duplicate enum ordinal across extensions was not detected.' }
        Set-Content (Join-Path $fixture 'D.al') "enumextension 70013511 `"D ori`" extends `"Other ori`" {`n value(70013516; B) {}`n}"
        if (@(Find-Collisions $fixture).Count -ne 0) { throw 'Separate enum value ID spaces were conflated.' }
        Set-Content (Join-Path $fixture 'A.al') "/// Object docs must not hide declarations.`ncodeunit 70013521 `"A ori`" {}"
        Set-Content (Join-Path $fixture 'B.al') 'codeunit 70013521 "B ori" {}'
        if (@(Find-Collisions $fixture).Count -ne 1) { throw 'Documentation hid a duplicate declaration.' }
        Write-Host 'Unique object IDs: 5 synthetic cases passed.'
    }
    finally { Remove-Item $fixture -Recurse -Force }
    exit 0
}
$problems = @(Find-Collisions $AppFolder)
if ($problems.Count -gt 0) {
    $problems | ForEach-Object { Write-Host "::error::$_" }
    exit 1
}
Write-Host 'Unique object IDs: no object or enum value collisions.'
