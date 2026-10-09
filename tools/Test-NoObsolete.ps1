<#
.SYNOPSIS
    Fails when the app declares anything obsolete, or hides a warning about obsolete base-app code.

.DESCRIPTION
    Foundation goes to AppSource with no obsolete object, field, control or procedure of its own (Gunnar, 01.10.2026:
    "there should not be any Obsolete object, field or control in the app we are working on for appsource"). That rule is
    about OUR declarations. A thing that is no longer wanted is deleted in one step. This guard keeps it that way.

    It reads every .al file under the app folder and fails on any line that

      - declares ObsoleteState, ObsoleteReason or ObsoleteTag (property syntax, "ObsoleteState = Pending;"),
      - carries an [Obsolete( ... )] attribute, or
      - disables the warning AL0432 (obsolete pending) or AL0667 (obsolete removed) with #pragma warning disable,
        except for the one allowed pragma below.

    The one allowed pragma (the allow-list $AllowedPragmas, below): a "#pragma warning disable AL0432" that wraps ONLY the
    declaration of a variable of type Record "VAT Amount Line" temporary, in a file listed in the allow-list, closed on
    the next line by "#pragma warning restore AL0432". Gunnar, 01.10.2026: "the Obsolete on VAT Amount Line is because
    Microsoft is changing the table to temporary. We still use it." The pragma is kept as a defensive guard: table 290 is
    already TableType = Temporary in BC 28.5 and has no ObsoleteState, so the pragma suppresses nothing today. Any other
    AL0432/AL0667 pragma fails, and so does a second VAT
    pragma in a listed file, a pragma that wraps more than that one declaration, and a pragma with another warning number
    in the same list.

    The allow-list must stay honest: an entry whose file is missing, or whose file no longer holds the allowed pragma,
    is stale and fails. Remove the entry together with the pragma, at the next application version bump in app/app.json, or
    earlier if a compile without the pragma is identical.

    These are not declarations and are not reported: the runtime filters on the system tables, such as
    TableField.SetRange(ObsoleteState, TableField.ObsoleteState::No) or TableMetadata.SetFilter(ObsoleteState, ...), because
    the property name is not at the start of the statement. Comment lines and text inside string literals are ignored.

.PARAMETER AppFolder
    The AL app folder (default: ../app next to this script).

.PARAMETER SelfTest
    Runs the guard against a small synthetic app and checks that it reports every kind of declaration and pragma, accepts
    the allowed VAT Amount Line pragma, rejects every other AL0432 pragma, reports a stale allow-list entry, and reports
    nothing for the runtime filters. Exits 1 when it does not.

.EXAMPLE
    ./tools/Test-NoObsolete.ps1
#>
param(
    [string]$AppFolder = (Join-Path $PSScriptRoot '..\app'),
    [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'

# The allow-list. File is relative to the app folder, with forward slashes. Each entry allows exactly ONE pragma pair
# around a "Record "VAT Amount Line" temporary" variable declaration. Delete the entry together with the pragma.
$AllowedPragmas = @()

# A property declaration starts the statement: "ObsoleteState = Pending;". A runtime filter never does.
$property = [regex]::new('^\s*Obsolete(State|Reason|Tag)\s*=', 'IgnoreCase')
$attribute = [regex]::new('\[\s*Obsolete\s*[\(\]]', 'IgnoreCase')
$pragma = [regex]::new('^\s*#pragma\s+warning\s+disable\b.*\b(AL0432|AL0667)\b', 'IgnoreCase')
$stringLiteral = [regex]::new("'(?:[^']|'')*'")
# The only shape the allow-list accepts: disable AL0432 / the one declaration / restore AL0432.
$allowedDisable = [regex]::new('^\s*#pragma\s+warning\s+disable\s+AL0432\s*$', 'IgnoreCase')
$allowedDeclaration = [regex]::new('^\s*\w+\s*:\s*Record\s+"VAT Amount Line"\s+temporary\s*;\s*$', 'IgnoreCase')
$allowedRestore = [regex]::new('^\s*#pragma\s+warning\s+restore\s+AL0432\s*$', 'IgnoreCase')

function Find-Obsolete([string]$Folder, [object[]]$Allowed) {
    $violations = New-Object 'System.Collections.Generic.List[string]'
    $used = @{}
    foreach ($entry in $Allowed) { $used[$entry.File] = 0 }
    foreach ($file in Get-ChildItem -LiteralPath $Folder -Recurse -Filter '*.al') {
        $relative = [System.IO.Path]::GetRelativePath($Folder, $file.FullName).Replace('\', '/')
        $isListed = $used.ContainsKey($relative)
        $lines = @(Get-Content -LiteralPath $file.FullName -Encoding UTF8)
        for ($i = 0; $i -lt $lines.Count; $i++) {
            $line = $lines[$i]
            $lineNo = $i + 1
            if ($line.TrimStart().StartsWith('//')) { continue }
            $code = $stringLiteral.Replace($line, "''")
            $kind = $null
            if ($pragma.IsMatch($line)) {
                $kind = 'pragma'
                $wrapsOnlyVat = $allowedDisable.IsMatch($line) -and ($i + 2 -lt $lines.Count) `
                    -and $allowedDeclaration.IsMatch($lines[$i + 1]) -and $allowedRestore.IsMatch($lines[$i + 2])
                if ($isListed -and $wrapsOnlyVat -and $used[$relative] -eq 0) {
                    $used[$relative] = 1
                    continue
                }
            }
            elseif ($property.IsMatch($code)) { $kind = 'declaration' }
            elseif ($attribute.IsMatch($code)) { $kind = 'attribute' }
            if ($kind) { $violations.Add("${relative}:${lineNo}: [$kind] $($line.Trim())") }
        }
    }
    foreach ($entry in $Allowed) {
        if ($used[$entry.File] -eq 0) {
            $violations.Add("$($entry.File): [stale-allow-list] no allowed VAT Amount Line pragma in this file any more; remove the entry from `$AllowedPragmas in tools/Test-NoObsolete.ps1")
        }
    }
    return ,$violations
}

function Invoke-SelfTest {
    $root = Join-Path ([System.IO.Path]::GetTempPath()) ("no-obsolete-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $root -Force | Out-Null
    try {
        @'
namespace Origo.Bifrost;
table 1 "Thing ori"
{
    ObsoleteState = Pending;
    ObsoleteReason = 'Gone.';
    ObsoleteTag = '28.0';
    fields
    {
        field(1; Old; Integer)
        {
            ObsoleteState = Removed;
        }
    }
    [Obsolete('Use New instead.', '28.0')]
    procedure Old()
    begin
    end;

#pragma warning disable AL0432
    procedure UsesObsolete()
    begin
    end;
#pragma warning restore AL0432

#pragma warning disable AL0667, AL0432
#pragma warning disable AL0667
}
'@ | Set-Content -LiteralPath (Join-Path $root 'Bad.Table.al') -Encoding UTF8
        @'
namespace Origo.Bifrost;
codeunit 2 "Clean ori"
{
    procedure Filters()
    var
        TableField: Record Field;
        TableMetadata: Record "Table Metadata";
    begin
        TableField.SetRange(ObsoleteState, TableField.ObsoleteState::No);
        TableField.SetFilter(ObsoleteState, '%1|%2', TableField.ObsoleteState::No, TableField.ObsoleteState::Pending);
        TableMetadata.SetFilter(ObsoleteState, '%1|%2', TableMetadata.ObsoleteState::No, TableMetadata.ObsoleteState::Pending);
        // ObsoleteState = Pending; is only a comment, and so is [Obsolete('x', '1')].
        Message('ObsoleteState = Pending; [Obsolete(] #pragma warning disable AL0432');
    end;

#pragma warning disable AL0432x
#pragma warning disable AA0137
}
'@ | Set-Content -LiteralPath (Join-Path $root 'Clean.Codeunit.al') -Encoding UTF8
        # Allowed: the VAT Amount Line pragma, in a listed file, wrapping only that declaration.
        @'
codeunit 3 "Vat Ok ori"
{
    local procedure Build()
    var
        SalesLine: Record "Sales Line";
        // Kept as a defensive guard: table 290 VAT Amount Line is already temporary in BC 28.
#pragma warning disable AL0432
        TempVATAmountLine: Record "VAT Amount Line" temporary;
#pragma warning restore AL0432
    begin
    end;
}
'@ | Set-Content -LiteralPath (Join-Path $root 'VatOk.Codeunit.al') -Encoding UTF8
        # Not allowed, in a listed file: another table, AL0667, an extra variable inside the pragma, and the second
        # well-formed VAT pair (the first one, "TempVATAmountLine3", uses up the one allowed pragma).
        @'
codeunit 4 "Vat Bad ori"
{
    local procedure Build()
    var
#pragma warning disable AL0432
        TempOther: Record "Some Obsolete Table" temporary;
#pragma warning restore AL0432
#pragma warning disable AL0667
        TempVATAmountLine: Record "VAT Amount Line" temporary;
#pragma warning restore AL0667
#pragma warning disable AL0432
        TempVATAmountLine2: Record "VAT Amount Line" temporary;
        Other: Record Customer;
#pragma warning restore AL0432
#pragma warning disable AL0432
        TempVATAmountLine3: Record "VAT Amount Line" temporary;
#pragma warning restore AL0432
#pragma warning disable AL0432
        TempVATAmountLine4: Record "VAT Amount Line" temporary;
#pragma warning restore AL0432
    begin
    end;
}
'@ | Set-Content -LiteralPath (Join-Path $root 'VatBad.Codeunit.al') -Encoding UTF8
        # Not listed: the allowed shape in a file that is not in the allow-list.
        @'
codeunit 5 "Vat Unlisted ori"
{
    local procedure Build()
    var
#pragma warning disable AL0432
        TempVATAmountLine: Record "VAT Amount Line" temporary;
#pragma warning restore AL0432
    begin
    end;
}
'@ | Set-Content -LiteralPath (Join-Path $root 'VatUnlisted.Codeunit.al') -Encoding UTF8

        $allowed = @(
            @{ File = 'VatOk.Codeunit.al'; Reason = 'self-test' },
            @{ File = 'VatBad.Codeunit.al'; Reason = 'self-test' },
            @{ File = 'Gone.Codeunit.al'; Reason = 'self-test: the file does not exist, so the entry is stale' }
        )
        $found = Find-Obsolete $root $allowed
        $failed = $false
        $bad = @($found | Where-Object { $_.StartsWith('Bad.Table.al:') })
        $clean = @($found | Where-Object { $_.StartsWith('Clean.Codeunit.al:') })
        $vatOk = @($found | Where-Object { $_.StartsWith('VatOk.Codeunit.al') })
        $vatBad = @($found | Where-Object { $_.StartsWith('VatBad.Codeunit.al:') })
        $vatUnlisted = @($found | Where-Object { $_.StartsWith('VatUnlisted.Codeunit.al:') })
        $stale = @($found | Where-Object { $_.Contains('[stale-allow-list]') })
        # 3 table properties + 1 field property + 1 attribute + 3 pragma disables; the restore line is not a disable.
        if ($bad.Count -ne 8) { Write-Host "SelfTest FAILED: expected 8 reports in Bad.Table.al, got $($bad.Count): $($bad -join '; ')"; $failed = $true }
        foreach ($kind in @('[declaration]', '[attribute]', '[pragma]')) {
            if (-not ($bad | Where-Object { $_.Contains($kind) })) { Write-Host "SelfTest FAILED: no $kind reported."; $failed = $true }
        }
        if ($clean.Count -ne 0) { Write-Host "SelfTest FAILED: the runtime filters must not be reported: $($clean -join '; ')"; $failed = $true }
        # The allowed VAT Amount Line pragma passes.
        if ($vatOk.Count -ne 0) { Write-Host "SelfTest FAILED: the allowed VAT Amount Line pragma must pass: $($vatOk -join '; ')"; $failed = $true }
        # Any other AL0432 pragma fails: other table, AL0667, extra variable inside the pragma, second VAT pair.
        if ($vatBad.Count -ne 4) { Write-Host "SelfTest FAILED: expected 4 reports in VatBad.Codeunit.al (other table, AL0667, extra variable, second VAT pair), got $($vatBad.Count): $($vatBad -join '; ')"; $failed = $true }
        if ($vatUnlisted.Count -ne 1) { Write-Host "SelfTest FAILED: a VAT pragma in a file that is not in the allow-list must fail, got $($vatUnlisted.Count)."; $failed = $true }
        # A stale allow-list entry fails.
        if ($stale.Count -ne 1 -or -not $stale[0].StartsWith('Gone.Codeunit.al')) { Write-Host "SelfTest FAILED: expected exactly one stale allow-list report for Gone.Codeunit.al, got: $($stale -join '; ')"; $failed = $true }
        if ($failed) { exit 1 }
        Write-Host 'SelfTest passed.'
    }
    finally {
        Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
    }
}

if ($SelfTest) {
    Invoke-SelfTest
    exit 0
}

$violations = Find-Obsolete $AppFolder $AllowedPragmas
if ($violations.Count -gt 0) {
    Write-Host "::error::The app must not declare anything obsolete or suppress AL0432/AL0667 before the AppSource publish, except the one allowed VAT Amount Line pragma ($($violations.Count) line(s)). Delete the code, or move the call to the supported replacement."
    $violations | ForEach-Object { Write-Host $_ }
    exit 1
}
Write-Host 'No obsolete declaration and no AL0432/AL0667 pragma in the app, apart from the allow-listed VAT Amount Line pragmas.'
