<#
.SYNOPSIS
    Fails when an Icelandic keyword list has fewer entries than the English one.

.DESCRIPTION
    The keyword list of a message type (the KeywordsLbl label of its implementation codeunit) is a comma-joined text that
    the help search ranks by. Its Icelandic translation (the is-IS= text in the Comment of the label, and from there the
    target in "<App>.is-IS.xlf") is joined the same way, so an entry that is dropped in translation takes a search term
    away from the Icelandic caller, and the entries after it no longer line up with the English ones (#695, #698).

    Entries are counted the way the search does (Default Discovery ori, SplitKeywords): split at ",", trim, lower case,
    leave out empty entries and repeats. The guard fails when

      - the is-IS= text of a KeywordsLbl has fewer entries than the English text,
      - a KeywordsLbl has no is-IS= text at all, or
      - the target of a KeywordsLbl unit in the Icelandic xlf has fewer entries than its source
        (the file is checked when it exists; regenerate it with tools/Update-IcelandicXlf.ps1).

    More Icelandic entries than English ones are fine (an integrator may type an English word on purpose, for example
    "delta", next to the Icelandic one).

.PARAMETER AppFolder
    The AL app folder (default: ../app next to this script).

.PARAMETER SelfTest
    Runs the guard against a small synthetic app and checks that it reports a short list, a missing is-IS= text, a list
    that is short only after repeats are removed and a short xlf target, and accepts a list that is as long as, or longer
    than, the English one. Exits 1 when it does not.

.EXAMPLE
    ./tools/Test-IcelandicKeywordCounts.ps1
#>
param(
    [string]$AppFolder = (Join-Path $PSScriptRoot '..\app'),
    [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'

# One declaration per line: KeywordsLbl: Label '<English>', Comment = 'is-IS=<Icelandic>';  ('' is an escaped quote)
$declaration = [regex]::new("KeywordsLbl\s*:\s*Label\s+'(?<en>(?:[^']|'')*)'(?<rest>.*);\s*$")
$icelandic = [regex]::new("is-IS=(?<is>(?:[^']|'')*)'")
$unitPattern = [regex]::new('(?s)<trans-unit id="(?<id>[^"]+)"[^>]*>(?<body>.*?)</trans-unit>')

function Get-KeywordCount([string]$Text) {
    $terms = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($part in $Text.Split(',')) {
        $term = $part.Trim().ToLowerInvariant()
        if ($term -ne '') { [void]$terms.Add($term) }
    }
    return $terms.Count
}

function Find-ShortKeywordLists([string]$Folder) {
    $violations = New-Object 'System.Collections.Generic.List[string]'
    $checked = 0
    foreach ($file in Get-ChildItem -LiteralPath $Folder -Recurse -Filter '*.al') {
        $relative = [System.IO.Path]::GetRelativePath($Folder, $file.FullName).Replace('\', '/')
        $lineNo = 0
        foreach ($line in Get-Content -LiteralPath $file.FullName -Encoding UTF8) {
            $lineNo++
            $m = $declaration.Match($line)
            if (-not $m.Success) { continue }
            $checked++
            $english = $m.Groups['en'].Value.Replace("''", "'")
            $is = $icelandic.Match($m.Groups['rest'].Value)
            if (-not $is.Success) {
                $violations.Add("${relative}:${lineNo}: KeywordsLbl has no is-IS= text")
                continue
            }
            $nEn = Get-KeywordCount $english
            $nIs = Get-KeywordCount ($is.Groups['is'].Value.Replace("''", "'"))
            if ($nIs -lt $nEn) {
                $violations.Add("${relative}:${lineNo}: the Icelandic keyword list has $nIs entries, the English one has $nEn")
            }
        }
    }
    return [pscustomobject]@{ Checked = $checked; Violations = $violations }
}

function Find-ShortKeywordTargets([string]$XlfPath) {
    $violations = New-Object 'System.Collections.Generic.List[string]'
    $checked = 0
    if (-not (Test-Path -LiteralPath $XlfPath)) { return [pscustomobject]@{ Checked = 0; Violations = $violations } }
    $text = Get-Content -LiteralPath $XlfPath -Raw -Encoding UTF8
    foreach ($unit in $unitPattern.Matches($text)) {
        $body = $unit.Groups['body'].Value
        if ($body -notmatch 'NamedType KeywordsLbl') { continue }
        $source = [regex]::Match($body, '(?s)<source>(?<s>.*?)</source>')
        $target = [regex]::Match($body, '(?s)<target[^>]*>(?<t>.*?)</target>')
        if (-not $source.Success) { continue }
        $checked++
        $note = [regex]::Match($body, 'Xliff Generator[^>]*>(?<n>[^<]*)</note>').Groups['n'].Value
        if (-not $target.Success) {
            $violations.Add("$($unit.Groups['id'].Value) ($note): no Icelandic target")
            continue
        }
        $nSource = Get-KeywordCount $source.Groups['s'].Value
        $nTarget = Get-KeywordCount $target.Groups['t'].Value
        if ($nTarget -lt $nSource) {
            $violations.Add("$($unit.Groups['id'].Value) ($note): the Icelandic target has $nTarget entries, the source has $nSource")
        }
    }
    return [pscustomobject]@{ Checked = $checked; Violations = $violations }
}

function Invoke-SelfTest {
    $root = Join-Path ([System.IO.Path]::GetTempPath()) ("kwcount-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $root | Out-Null
    try {
        $files = @{
            'Ok.al'        = "        KeywordsLbl: Label 'a, b, c', Comment = 'is-IS=x, y, z';"
            'Longer.al'    = "        KeywordsLbl: Label 'delta, b', Comment = 'is-IS=delta, delta samstilling, b';"
            'Short.al'     = "        KeywordsLbl: Label 'a, b, c', Comment = 'is-IS=x, y';"
            'NoIs.al'      = "        KeywordsLbl: Label 'a, b', Locked = true;"
            'Repeats.al'   = "        KeywordsLbl: Label 'a, b, c', Comment = 'is-IS=x, y, Y, x ';"
            'Apostrophe.al' = "        KeywordsLbl: Label 'it''s a, b', Comment = 'is-IS=x, y';"
        }
        foreach ($name in $files.Keys) { Set-Content -LiteralPath (Join-Path $root $name) -Value $files[$name] -Encoding UTF8 }
        $result = Find-ShortKeywordLists $root
        $expected = @('Short.al', 'NoIs.al', 'Repeats.al')
        $failures = New-Object 'System.Collections.Generic.List[string]'
        if ($result.Checked -ne 6) { $failures.Add("expected 6 declarations, found $($result.Checked)") }
        foreach ($name in $expected) {
            if (-not ($result.Violations | Where-Object { $_ -like "$name*" })) { $failures.Add("did not report $name") }
        }
        foreach ($name in 'Ok.al', 'Longer.al', 'Apostrophe.al') {
            if ($result.Violations | Where-Object { $_ -like "$name*" }) { $failures.Add("reported $name, which is fine") }
        }

        $xlf = Join-Path $root 'T.is-IS.xlf'
        $units = @(
            '<trans-unit id="u1"><source>a, b, c</source><target>x, y</target><note from="Xliff Generator" annotates="general" priority="3">Codeunit One - Method GetKeywords - NamedType KeywordsLbl</note></trans-unit>',
            '<trans-unit id="u2"><source>a, b</source><target>x, y</target><note from="Xliff Generator" annotates="general" priority="3">Codeunit Two - Method GetKeywords - NamedType KeywordsLbl</note></trans-unit>',
            '<trans-unit id="u3"><source>a, b, c</source><target>x</target><note from="Xliff Generator" annotates="general" priority="3">Codeunit Three - Method GetCaption - NamedType CaptionLbl</note></trans-unit>'
        )
        Set-Content -LiteralPath $xlf -Value ('<xliff><file><body>' + ($units -join '') + '</body></file></xliff>') -Encoding UTF8
        $xr = Find-ShortKeywordTargets $xlf
        if ($xr.Checked -ne 2) { $failures.Add("expected 2 keyword units in the xlf, found $($xr.Checked)") }
        if (-not ($xr.Violations | Where-Object { $_ -like 'u1*' })) { $failures.Add('did not report the short xlf target u1') }
        if ($xr.Violations | Where-Object { $_ -like 'u2*' -or $_ -like 'u3*' }) { $failures.Add('reported a unit that is fine (u2) or not a keyword list (u3)') }

        if ($failures.Count -gt 0) {
            $failures | ForEach-Object { Write-Host "SELF-TEST FAILED: $_" }
            exit 1
        }
        Write-Host 'Self-test passed: short lists, a missing is-IS= text, repeats and a short xlf target are reported; longer and equal lists are accepted.'
    }
    finally {
        Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
    }
}

if ($SelfTest) { Invoke-SelfTest; exit 0 }

if (-not (Test-Path -LiteralPath $AppFolder)) { throw "App folder not found: $AppFolder" }
$sourceResult = Find-ShortKeywordLists $AppFolder
$xlfPath = Get-ChildItem -LiteralPath (Join-Path $AppFolder 'Translations') -Filter '*.is-IS.xlf' -ErrorAction SilentlyContinue | Select-Object -First 1
$xlfResult = if ($xlfPath) { Find-ShortKeywordTargets $xlfPath.FullName } else { [pscustomobject]@{ Checked = 0; Violations = @() } }

if ($sourceResult.Checked -eq 0) { throw "No KeywordsLbl found under $AppFolder - the guard checked nothing." }
$all = @($sourceResult.Violations) + @($xlfResult.Violations)
if ($all.Count -gt 0) {
    Write-Host "$($all.Count) Icelandic keyword list(s) have fewer entries than the English one:"
    $all | ForEach-Object { Write-Host "  $_" }
    Write-Host 'Give every English keyword an Icelandic entry (a different word is fine), then run tools/Update-IcelandicXlf.ps1.'
    exit 1
}
Write-Host "Every Icelandic keyword list has at least as many entries as the English one ($($sourceResult.Checked) in the source, $($xlfResult.Checked) in the xlf)."
