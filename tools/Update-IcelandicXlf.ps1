<#
.SYNOPSIS
    Rebuilds "<App>.is-IS.xlf" from "<App>.g.xlf" and the is-IS= comments in the AL source.

.DESCRIPTION
    The is-IS= comment on every Caption, ToolTip, InstructionalText and Label is the authority for
    the Icelandic text (see .claude/CLAUDE.md, Translations). The compiler copies each comment into
    the "Developer" note of the generated g.xlf; this script writes the Icelandic translation file
    from it:

      - target = the text after "is-IS=" in the Developer note;
      - otherwise the target the existing is-IS.xlf already has for the same trans-unit id;
      - otherwise no target (Business Central shows the English source) and the unit is reported.

    Units with translate="no" (Locked labels) get no target. Compile the app first so g.xlf is current.

.PARAMETER TranslationsFolder
    The app's Translations folder (default: ../app/Translations next to this script).

.EXAMPLE
    ./tools/Update-IcelandicXlf.ps1
#>
param(
    [string]$TranslationsFolder = (Join-Path $PSScriptRoot '..\app\Translations')
)

$ErrorActionPreference = 'Stop'
$gFile = Get-ChildItem -LiteralPath $TranslationsFolder -Filter '*.g.xlf' | Select-Object -First 1
if (-not $gFile) { throw "No .g.xlf in $TranslationsFolder - compile the app first." }
$isPath = Join-Path $TranslationsFolder ($gFile.Name -replace '\.g\.xlf$', '.is-IS.xlf')

$unitPattern = '(?s)<trans-unit id="(?<id>[^"]+)"[^>]*>.*?</trans-unit>'
$existing = @{}
if (Test-Path -LiteralPath $isPath) {
    $old = Get-Content -LiteralPath $isPath -Raw -Encoding UTF8
    foreach ($m in [regex]::Matches($old, $unitPattern)) {
        $t = [regex]::Match($m.Value, '(?s)<target[^>]*>(?<t>.*?)</target>')
        if ($t.Success) { $existing[$m.Groups['id'].Value] = $t.Groups['t'].Value }
    }
}

$g = Get-Content -LiteralPath $gFile.FullName -Raw -Encoding UTF8
$fromComment = 0; $fromExisting = 0; $missing = [System.Collections.Generic.List[string]]::new()
$result = [regex]::Replace($g, $unitPattern, {
        param($m)
        $unit = $m.Value
        if ($unit -match 'translate="no"') { return $unit }
        $id = $m.Groups['id'].Value
        $target = $null
        $note = [regex]::Match($unit, '(?s)<note from="Developer"[^>]*>(?<n>.*?)</note>')
        if ($note.Success) {
            $i = $note.Groups['n'].Value.IndexOf('is-IS=')
            if ($i -ge 0) { $target = $note.Groups['n'].Value.Substring($i + 6).Trim(); $script:fromComment++ }
        }
        if (-not $target -and $existing.ContainsKey($id)) { $target = $existing[$id]; $script:fromExisting++ }
        if (-not $target) {
            $src = [regex]::Match($unit, '(?s)<source>(?<s>.*?)</source>').Groups['s'].Value
            $script:missing.Add("$id :: $src")
            return $unit
        }
        return [regex]::Replace($unit, '(?s)(\s*)<source>(.*?)</source>', {
                param($s)
                "$($s.Groups[1].Value)<source>$($s.Groups[2].Value)</source>$($s.Groups[1].Value)<target>$target</target>"
            }, 1)
    })
$result = $result -replace 'source-language="en-US"', 'source-language="en-US" target-language="is-IS"'
$result = $result -replace 'target-language="is-IS" target-language="[^"]*"', 'target-language="is-IS"'
[System.IO.File]::WriteAllText($isPath, $result, [System.Text.UTF8Encoding]::new($false))

Write-Host "Wrote $isPath - $fromComment target(s) from is-IS= comments, $fromExisting kept from the previous file, $($missing.Count) without Icelandic."
$missing | Select-Object -First 50 | ForEach-Object { Write-Host "  missing: $_" }
