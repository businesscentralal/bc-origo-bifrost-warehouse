<#
.SYNOPSIS
    Fails when the committed "<App>.is-IS.xlf" differs from what tools/Update-IcelandicXlf.ps1 would generate from the build (#791).

.DESCRIPTION
    The Icelandic translation file is generated: the compiler writes "<App>.g.xlf" with one trans-unit for every
    caption, tooltip and label of the current source, and tools/Update-IcelandicXlf.ps1 writes "<App>.is-IS.xlf" from it
    and from the is-IS= comments. Nothing compared the committed file with that result, so after the refusal rewording
    of #775 and #780 the committed file carried five units of labels that no longer exist, and a unit could just as
    well be missing for a new label (BC then shows the English text).

    The guard copies the generated g.xlf and the committed is-IS.xlf into a temporary folder, runs
    tools/Update-IcelandicXlf.ps1 on the copy and compares the result with the committed file. It reports

      orphan        a trans-unit id in the committed file that the build does not have;
      missing       a trans-unit id of the build that the committed file does not have;
      out-of-order  the same ids in a different order than the build writes them;
      content       the same ids in the same order, but different text (a target, a note or a size attribute).

    The fix is always the same: compile the app, run tools/Update-IcelandicXlf.ps1 and commit the result. No Icelandic
    wording is judged here. There is no allow-list.

    The g.xlf is a build output (not committed), so the guard needs a compile first. It exits 1 with a message when
    there is no g.xlf in the folder. Compile the app with alc (it writes app/Translations/*.g.xlf) before running it.

.PARAMETER TranslationsFolder
    The app's Translations folder with the g.xlf of the current build and the committed is-IS.xlf
    (default: ../app/Translations next to this script).

.PARAMETER SelfTest
    Runs the guard against small synthetic translation folders and checks that it reports an extra unit, a missing
    unit, a changed order and a changed target, and passes a clean folder. Exits 1 when it does not.

.EXAMPLE
    ./tools/Test-IcelandicXlfInSync.ps1
#>
param(
    [string]$TranslationsFolder = (Join-Path $PSScriptRoot '..\app\Translations'),
    [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'

$script:UpdateScript = Join-Path $PSScriptRoot 'Update-IcelandicXlf.ps1'
$script:UnitPattern = [regex]::new('(?s)<trans-unit id="(?<id>[^"]+)"[^>]*>.*?</trans-unit>')

function Read-Normalized([string]$Path) {
    $text = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    if ($null -eq $text) { return '' }
    return ($text -replace "`r`n", "`n")
}

function Get-UnitIds([string]$Text) {
    return @($script:UnitPattern.Matches($Text) | ForEach-Object { $_.Groups['id'].Value })
}

function Find-Problems([string]$Folder) {
    $gFile = Get-ChildItem -LiteralPath $Folder -Filter '*.g.xlf' -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $gFile) {
        return @("no-build: there is no .g.xlf in $Folder - compile the app first (alc writes it to the Translations folder)")
    }
    $isName = $gFile.Name -replace '\.g\.xlf$', '.is-IS.xlf'
    $committedPath = Join-Path $Folder $isName
    if (-not (Test-Path -LiteralPath $committedPath)) {
        return @("no-file: $isName does not exist in $Folder - run tools/Update-IcelandicXlf.ps1")
    }

    $generatedText = Read-Normalized $gFile.FullName
    if ([string]::IsNullOrEmpty($generatedText) -or -not $script:UnitPattern.IsMatch($generatedText)) {
        return @("empty: $($gFile.Name) has no trans-unit")
    }
    $committed = Read-Normalized $committedPath
    if ([string]::IsNullOrEmpty($committed) -or -not $script:UnitPattern.IsMatch($committed)) {
        return @("empty: $isName has no trans-unit")
    }

    $work = Join-Path ([System.IO.Path]::GetTempPath()) ("xlf-guard-" + [guid]::NewGuid().ToString('N'))
    try {
        New-Item -ItemType Directory -Force -Path $work | Out-Null
        Copy-Item -LiteralPath $gFile.FullName -Destination (Join-Path $work $gFile.Name)
        Copy-Item -LiteralPath $committedPath -Destination (Join-Path $work $isName)
        & $script:UpdateScript -TranslationsFolder $work *>$null
        $expected = Read-Normalized (Join-Path $work $isName)
    }
    finally {
        if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force }
    }

    $problems = [System.Collections.Generic.List[string]]::new()
    $committedIds = @(Get-UnitIds $committed)
    $expectedIds = @(Get-UnitIds $expected)
    $expectedSet = [System.Collections.Generic.HashSet[string]]::new([string[]]$expectedIds)
    $committedSet = [System.Collections.Generic.HashSet[string]]::new([string[]]$committedIds)

    foreach ($id in $committedIds | Where-Object { -not $expectedSet.Contains($_) }) {
        $problems.Add("orphan: ""$id"" is in $isName but the build has no such unit")
    }
    foreach ($id in $expectedIds | Where-Object { -not $committedSet.Contains($_) }) {
        $problems.Add("missing: ""$id"" is in the build but not in $isName")
    }
    if ($problems.Count -eq 0) {
        $a = $committedIds -join "`n"
        $b = $expectedIds -join "`n"
        if ($a -ne $b) {
            $problems.Add("out-of-order: $isName holds the units of the build in a different order than tools/Update-IcelandicXlf.ps1 writes them")
        }
        elseif ($committed -ne $expected) {
            $firstChanged = $null
            $expectedUnits = @{}
            foreach ($m in $script:UnitPattern.Matches($expected)) { $expectedUnits[$m.Groups['id'].Value] = $m.Value }
            foreach ($m in $script:UnitPattern.Matches($committed)) {
                if ($expectedUnits[$m.Groups['id'].Value] -ne $m.Value) { $firstChanged = $m.Groups['id'].Value; break }
            }
            if ($firstChanged) {
                $problems.Add("content: unit ""$firstChanged"" in $isName differs from what tools/Update-IcelandicXlf.ps1 writes (target, note or attribute)")
            }
            else {
                $problems.Add("content: $isName differs from what tools/Update-IcelandicXlf.ps1 writes outside the trans-units (header or whitespace)")
            }
        }
    }
    return $problems.ToArray()
}

function Write-SyntheticGxlf([string]$Folder, [string[]]$Ids) {
    New-Item -ItemType Directory -Force -Path $Folder | Out-Null
    $units = foreach ($id in $Ids) {
        "      <trans-unit id=""$id"" size-unit=""char"" translate=""yes"" xml:space=""preserve"">`n" +
        "        <source>Text of $id</source>`n" +
        "        <note from=""Developer"" annotates=""general"" priority=""2"">is-IS=Texti $id</note>`n" +
        "      </trans-unit>"
    }
    $xlf = "<?xml version=""1.0"" encoding=""utf-8""?>`n" +
    "<xliff version=""1.2"" xmlns=""urn:oasis:names:tc:xliff:document:1.2"">`n" +
    "  <file datatype=""xml"" source-language=""en-US"" original=""Test"">`n" +
    "    <body>`n" +
    "    <group id=""body"">`n" +
    ($units -join "`n") + "`n" +
    "    </group>`n" +
    "    </body>`n" +
    "  </file>`n" +
    "</xliff>`n"
    [System.IO.File]::WriteAllText((Join-Path $Folder 'Test.g.xlf'), $xlf, [System.Text.UTF8Encoding]::new($false))
}

function New-SyntheticCase([string]$Root, [string]$Name, [string[]]$Ids) {
    $folder = Join-Path $Root $Name
    Write-SyntheticGxlf $folder $Ids
    & $script:UpdateScript -TranslationsFolder $folder *>$null
    return $folder
}

function Invoke-SelfTest {
    $root = Join-Path ([System.IO.Path]::GetTempPath()) ("xlf-guard-self-" + [guid]::NewGuid().ToString('N'))
    $failed = $false
    try {
        $ids = @('Table 1 - NamedType 10', 'Table 1 - NamedType 20', 'Codeunit 2 - NamedType 30', 'Codeunit 2 - Method 5 - NamedType 40')

        $clean = New-SyntheticCase $root 'clean' $ids
        $found = @(Find-Problems $clean)
        if ($found.Count -ne 0) { Write-Host "SelfTest FAILED: a clean folder must pass, got: $($found -join '; ')"; $failed = $true }

        # An extra unit in the committed file: the build no longer has it.
        $extra = New-SyntheticCase $root 'extra' $ids
        $isPath = Join-Path $extra 'Test.is-IS.xlf'
        $text = Get-Content -LiteralPath $isPath -Raw -Encoding UTF8
        $orphan = "      <trans-unit id=""Table 9 - NamedType 99"" size-unit=""char"" translate=""yes"" xml:space=""preserve"">`n        <source>Gone</source>`n        <target>Horfið</target>`n      </trans-unit>`n"
        $at = $text.IndexOf('    </group>')
        [System.IO.File]::WriteAllText($isPath, $text.Insert($at, $orphan), [System.Text.UTF8Encoding]::new($false))
        $found = @(Find-Problems $extra)
        if (-not ($found | Where-Object { $_.StartsWith('orphan: "Table 9 - NamedType 99"') })) { Write-Host "SelfTest FAILED: an extra unit must be reported as orphan, got: $($found -join '; ')"; $failed = $true }
        if ($found.Count -ne 1) { Write-Host "SelfTest FAILED: an extra unit must give exactly one problem, got $($found.Count)"; $failed = $true }

        # A unit missing from the committed file: the build has it.
        $missing = New-SyntheticCase $root 'missing' $ids
        $isPath = Join-Path $missing 'Test.is-IS.xlf'
        $text = Get-Content -LiteralPath $isPath -Raw -Encoding UTF8
        $cut = [regex]::Replace($text, '(?s)\s*<trans-unit id="Codeunit 2 - NamedType 30".*?</trans-unit>', '')
        [System.IO.File]::WriteAllText($isPath, $cut, [System.Text.UTF8Encoding]::new($false))
        $found = @(Find-Problems $missing)
        if (-not ($found | Where-Object { $_.StartsWith('missing: "Codeunit 2 - NamedType 30"') })) { Write-Host "SelfTest FAILED: a missing unit must be reported as missing, got: $($found -join '; ')"; $failed = $true }
        if ($found.Count -ne 1) { Write-Host "SelfTest FAILED: a missing unit must give exactly one problem, got $($found.Count)"; $failed = $true }

        # The same units in another order.
        $order = New-SyntheticCase $root 'order' $ids
        $isPath = Join-Path $order 'Test.is-IS.xlf'
        $units = @($script:UnitPattern.Matches((Get-Content -LiteralPath $isPath -Raw -Encoding UTF8)) | ForEach-Object { $_.Value })
        $text = Get-Content -LiteralPath $isPath -Raw -Encoding UTF8
        $swapped = $text.Replace($units[0], '@@A@@').Replace($units[1], $units[0]).Replace('@@A@@', $units[1])
        [System.IO.File]::WriteAllText($isPath, $swapped, [System.Text.UTF8Encoding]::new($false))
        $found = @(Find-Problems $order)
        if (-not ($found | Where-Object { $_.StartsWith('out-of-order:') })) { Write-Host "SelfTest FAILED: a changed order must be reported as out-of-order, got: $($found -join '; ')"; $failed = $true }

        # A changed target (the is-IS= comment in the build is the authority).
        $content = New-SyntheticCase $root 'content' $ids
        $isPath = Join-Path $content 'Test.is-IS.xlf'
        $text = Get-Content -LiteralPath $isPath -Raw -Encoding UTF8
        [System.IO.File]::WriteAllText($isPath, $text.Replace('Texti Table 1 - NamedType 20', 'Annar texti'), [System.Text.UTF8Encoding]::new($false))
        $found = @(Find-Problems $content)
        if (-not ($found | Where-Object { $_.StartsWith('content: unit "Table 1 - NamedType 20"') })) { Write-Host "SelfTest FAILED: a changed target must be reported as content, got: $($found -join '; ')"; $failed = $true }

        # No g.xlf: the guard cannot judge and must say so.
        $empty = Join-Path $root 'empty'
        New-Item -ItemType Directory -Force -Path $empty | Out-Null
        $found = @(Find-Problems $empty)
        if (-not ($found | Where-Object { $_.StartsWith('no-build:') })) { Write-Host "SelfTest FAILED: a folder without g.xlf must be reported as no-build, got: $($found -join '; ')"; $failed = $true }

        # CRLF in the committed file (a Windows checkout) is not a difference.
        $crlf = New-SyntheticCase $root 'crlf' $ids
        $isPath = Join-Path $crlf 'Test.is-IS.xlf'
        $text = Get-Content -LiteralPath $isPath -Raw -Encoding UTF8
        [System.IO.File]::WriteAllText($isPath, ($text -replace "`r`n", "`n" -replace "`n", "`r`n"), [System.Text.UTF8Encoding]::new($false))
        $found = @(Find-Problems $crlf)
        if ($found.Count -ne 0) { Write-Host "SelfTest FAILED: CRLF line endings must pass, got: $($found -join '; ')"; $failed = $true }
    }
    finally {
        if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
    }
    if ($failed) { exit 1 }
    Write-Host 'SelfTest passed.'
}

if ($SelfTest) {
    Invoke-SelfTest
    exit 0
}

$problems = @(Find-Problems $TranslationsFolder)
if ($problems.Count -gt 0) {
    $compared = @($problems | Where-Object { $_ -notmatch '^(no-build|no-file|empty):' })
    if ($compared.Count -gt 0) {
        Write-Host "::error::The committed is-IS.xlf is not what tools/Update-IcelandicXlf.ps1 generates from the build ($($compared.Count) problem(s), #791). Compile the app, run tools/Update-IcelandicXlf.ps1 and commit the result."
    }
    else {
        Write-Host "::error::$($problems[0])"
    }
    $problems | Select-Object -First 50 | ForEach-Object { Write-Host $_ }
    if ($problems.Count -gt 50) { Write-Host "... and $($problems.Count - 50) more" }
    exit 1
}
Write-Host 'The committed is-IS.xlf is what tools/Update-IcelandicXlf.ps1 generates from the build.'
