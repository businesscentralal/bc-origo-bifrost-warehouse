<#
.SYNOPSIS
    Fails when a message type of the shipped app has a name without exactly three dot-separated parts.

.DESCRIPTION
    Every Bifrost message type name is Domain.Entity.Action, for example Item.Reference.Resolve (Gunnar, 16.10.2026,
    #1037). A name with two parts, or with four or more, is not allowed in the app that goes to AppSource.

    The guard reads every .al file under the app folder. In each enum named "Message Type ori", and in each
    enumextension that extends it (with or without a namespace in front), it reads the name of every value, quoted
    (value(10077885; "Help.Tables.Get")) or unquoted (value(1; Probe)). It fails on a name that

      - does not have exactly three parts when split at ".",
      - has an empty part ("Item..Get", ".Item.Get"), or
      - has white space in a part ("Item.Ref Name.Get").

    Line comments (//) and block comments (/* */) are ignored, so a commented-out value is not read. Other enums are
    not checked. There is no allow-list.

    Test apps are exempt (Gunnar, 16.10.2026: "Test app can break the pattern of 3 parts but not appsource app.").
    The guard only reads the folder passed as -AppFolder (default: ../app next to this script) and never the test
    folder, so names such as Test.Bifrost.Vendor.Register in test/ are not checked. A feature app copies this script
    into its own tools/ folder and runs it the same way, on its app/ folder only.

.PARAMETER AppFolder
    The AL app folder (default: ../app next to this script). Never point it at a test app.

.PARAMETER EnumName
    The name of the message type enum (default: Message Type ori).

.PARAMETER SelfTest
    Runs the guard against a small synthetic repository and checks that it accepts valid names, reports 2-, 4- and
    5-part names, an empty part, an unquoted name and a quoted name with spaces, ignores comments and other enums, and
    ignores a 4-part name in the test folder. Exits 1 when it does not.

.EXAMPLE
    ./tools/Test-MessageTypeNames.ps1
#>
param(
    [string]$AppFolder = (Join-Path $PSScriptRoot '..\app'),
    [string]$EnumName = 'Message Type ori',
    [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'

# AL identifier: "Quoted Name" or Plain_Name. A namespace prefix (Origo.Bifrost.) may stand in front of the extended enum.
$identifier = '(?:"[^"]*"|[A-Za-z_][A-Za-z0-9_]*)'
$objectHeader = [regex]::new(
    "(?im)^\s*(?<kind>enum|enumextension)\s+\d+\s+(?<name>$identifier)(?:\s+extends\s+(?:$identifier\s*\.\s*)*(?<base>$identifier))?",
    'IgnoreCase, Multiline')
$valueDecl = [regex]::new('(?i)\bvalue\s*\(\s*\d+\s*;\s*(?:"(?<quoted>[^"]*)"|(?<plain>[A-Za-z_][A-Za-z0-9_]*))\s*\)')

function Remove-AlComments([string]$Text) {
    # Replaces comments with spaces and keeps line breaks, so offsets still give the right line number.
    # Text inside '...' strings and "..." identifiers is kept as it is.
    $sb = [System.Text.StringBuilder]::new($Text.Length)
    $state = 'code'
    for ($i = 0; $i -lt $Text.Length; $i++) {
        $c = $Text[$i]
        $next = if ($i + 1 -lt $Text.Length) { $Text[$i + 1] } else { [char]0 }
        switch ($state) {
            'code' {
                if ($c -eq '/' -and $next -eq '/') { $state = 'line'; [void]$sb.Append(' '); continue }
                if ($c -eq '/' -and $next -eq '*') { $state = 'block'; [void]$sb.Append('  '); $i++; continue }
                if ($c -eq "'") { $state = 'string' }
                elseif ($c -eq '"') { $state = 'ident' }
                [void]$sb.Append($c)
            }
            'line' {
                if ($c -eq "`n") { $state = 'code'; [void]$sb.Append($c) }
                else { [void]$sb.Append(' ') }
            }
            'block' {
                if ($c -eq '*' -and $next -eq '/') { $state = 'code'; [void]$sb.Append('  '); $i++; continue }
                if ($c -eq "`n" -or $c -eq "`r") { [void]$sb.Append($c) } else { [void]$sb.Append(' ') }
            }
            'string' {
                if ($c -eq "'") { $state = 'code' }
                elseif ($c -eq "`n") { $state = 'code' }
                [void]$sb.Append($c)
            }
            'ident' {
                if ($c -eq '"' -or $c -eq "`n") { $state = 'code' }
                [void]$sb.Append($c)
            }
        }
    }
    return $sb.ToString()
}

function Test-ThreePartName([string]$Name) {
    $parts = $Name.Split('.')
    if ($parts.Count -ne 3) { return "has $($parts.Count) part(s)" }
    foreach ($part in $parts) {
        if ($part.Length -eq 0) { return 'has an empty part' }
        if ($part -match '\s') { return 'has white space in a part' }
    }
    return $null
}

function Get-Unquoted([string]$Identifier) {
    return $Identifier.Trim().Trim('"')
}

function Find-BadMessageTypeNames([string]$Folder, [string]$Enum) {
    $violations = New-Object 'System.Collections.Generic.List[string]'
    $checked = 0
    foreach ($file in Get-ChildItem -LiteralPath $Folder -Recurse -Filter '*.al') {
        $relative = [System.IO.Path]::GetRelativePath($Folder, $file.FullName).Replace('\', '/')
        $code = Remove-AlComments (Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8)
        $headers = @($objectHeader.Matches($code))
        for ($h = 0; $h -lt $headers.Count; $h++) {
            $header = $headers[$h]
            $isMessageType = if ($header.Groups['kind'].Value -ieq 'enum') {
                (Get-Unquoted $header.Groups['name'].Value) -ieq $Enum
            }
            else {
                $header.Groups['base'].Success -and ((Get-Unquoted $header.Groups['base'].Value) -ieq $Enum)
            }
            if (-not $isMessageType) { continue }
            # The object runs to the next enum/enumextension header in the same file, or to the end of the file.
            $start = $header.Index + $header.Length
            $end = if ($h + 1 -lt $headers.Count) { $headers[$h + 1].Index } else { $code.Length }
            foreach ($value in $valueDecl.Matches($code.Substring($start, $end - $start))) {
                $checked++
                $name = if ($value.Groups['quoted'].Success) { $value.Groups['quoted'].Value } else { $value.Groups['plain'].Value }
                $problem = Test-ThreePartName $name
                if ($problem) {
                    $lineNo = ($code.Substring(0, $start + $value.Index) -split "`n").Count
                    $violations.Add("${relative}:${lineNo}: `"$name`" $problem")
                }
            }
        }
    }
    return [pscustomobject]@{ Checked = $checked; Violations = $violations }
}

function Invoke-SelfTest {
    $root = Join-Path ([System.IO.Path]::GetTempPath()) ("message-type-names-" + [guid]::NewGuid().ToString('N'))
    $app = Join-Path $root 'app/src'
    $test = Join-Path $root 'test/src'
    New-Item -ItemType Directory -Path $app, $test -Force | Out-Null
    try {
        # Valid: three parts, quoted, in the enum itself and in a namespace-qualified extension. Comments are ignored.
        @'
namespace Origo.Bifrost;
enum 1 "Message Type ori"
{
    Extensible = true;
    value(10; "Item.Reference.Resolve") { Caption = 'Item.Reference.Resolve', Locked = true; }
    value(11; "Help.Tables.Get") // "Two.Parts" in a trailing comment
    {
    }
    // value(12; "Commented.Out.Four.Parts")
    /* value(13; "Block.Comment")
       value(14; Probe) */
}
'@ | Set-Content -LiteralPath (Join-Path $app 'MessageType.Enum.al') -Encoding UTF8
        @'
namespace Origo.Bifrost.Warehouse;
using Origo.Bifrost;
enumextension 2 "Valid MsgType ori" extends Origo.Bifrost."Message Type ori"
{
    value(20; "Warehouse.Shipment.Post") { }
}
'@ | Set-Content -LiteralPath (Join-Path $app 'Valid.EnumExt.al') -Encoding UTF8
        # Invalid: 2, 4 and 5 parts, an empty part, a leading dot, an unquoted name, a quoted name with spaces.
        @'
enumextension 3 "Bad MsgType ori" extends "Message Type ori"
{
    value(30; "Metering.Probe") { }
    value(31; "Test.Bifrost.Vendor.Register") { }
    value(32; "A.B.C.D.E") { }
    value(33; "Item..Get") { }
    value(34; ".Item.Get") { }
    value(35; Probe) { }
    value(36; "Item.Ref Name.Get") { }
}
'@ | Set-Content -LiteralPath (Join-Path $app 'Bad.EnumExt.al') -Encoding UTF8
        # Not a message type: other enums and enum extensions are not checked.
        @'
enum 4 "Other Enum ori"
{
    value(0; "Two.Parts") { }
    value(1; Plain) { }
}
enumextension 5 "Other Ext ori" extends "Some Base Enum"
{
    value(50; "A.B.C.D") { }
}
'@ | Set-Content -LiteralPath (Join-Path $app 'Other.Enum.al') -Encoding UTF8
        # Test apps are exempt: a 4-part name in the test folder is never read.
        @'
enumextension 98860 "Test Bifrost Msg Type" extends "Message Type ori"
{
    value(98860; "Test.Bifrost.Vendor.Register") { }
}
'@ | Set-Content -LiteralPath (Join-Path $test 'TestBifrostMsgType.EnumExt.al') -Encoding UTF8

        $result = Find-BadMessageTypeNames (Join-Path $root 'app') 'Message Type ori'
        $found = @($result.Violations)
        $failures = New-Object 'System.Collections.Generic.List[string]'
        $expected = @(
            '"Metering.Probe" has 2 part(s)',
            '"Test.Bifrost.Vendor.Register" has 4 part(s)',
            '"A.B.C.D.E" has 5 part(s)',
            '"Item..Get" has an empty part',
            '".Item.Get" has an empty part',
            '"Probe" has 1 part(s)',
            '"Item.Ref Name.Get" has white space in a part'
        )
        foreach ($e in $expected) {
            if (-not ($found | Where-Object { $_.StartsWith('src/Bad.EnumExt.al:') -and $_.EndsWith($e) })) { $failures.Add("not reported: $e") }
        }
        if ($found.Count -ne $expected.Count) { $failures.Add("expected $($expected.Count) reports, got $($found.Count): $($found -join '; ')") }
        if ($found | Where-Object { -not $_.StartsWith('src/Bad.EnumExt.al:') }) { $failures.Add("reported a valid name, a comment, another enum or the test folder: $($found -join '; ')") }
        # 2 valid values in the enum + 1 in the valid extension + 7 bad ones; comments, other enums and test/ are not read.
        if ($result.Checked -ne 10) { $failures.Add("expected 10 message type values read, got $($result.Checked)") }
        # The line number points at the value.
        if (-not ($found | Where-Object { $_.StartsWith('src/Bad.EnumExt.al:3:') })) { $failures.Add("line number of the first bad value is not 3: $($found -join '; ')") }

        if ($failures.Count -gt 0) {
            $failures | ForEach-Object { Write-Host "SELF-TEST FAILED: $_" }
            exit 1
        }
        Write-Host 'Self-test passed: three-part names are accepted; 2-, 4- and 5-part names, empty parts, an unquoted name and a name with spaces are reported; comments, other enums and the test folder are ignored.'
    }
    finally {
        Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
    }
}

if ($SelfTest) { Invoke-SelfTest; exit 0 }

if (-not (Test-Path -LiteralPath $AppFolder)) { throw "App folder not found: $AppFolder" }
$result = Find-BadMessageTypeNames $AppFolder $EnumName
if ($result.Checked -eq 0) { throw "No value of enum `"$EnumName`" or of an extension of it found under $AppFolder - the guard checked nothing." }
if ($result.Violations.Count -gt 0) {
    Write-Host "::error::$($result.Violations.Count) message type name(s) do not have exactly three parts (Domain.Entity.Action, #1037):"
    $result.Violations | ForEach-Object { Write-Host "  $_" }
    exit 1
}
Write-Host "Every message type name in the app has exactly three parts ($($result.Checked) checked; test apps are exempt)."
