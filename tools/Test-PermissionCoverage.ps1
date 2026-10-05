<#
.SYNOPSIS
    Fails when a page, query, report or xmlport is granted by no assignable permission set (#434).

.DESCRIPTION
    A user who is not SUPER gets a permission error when an object opens that none of his permission sets
    grants. Nothing compared the objects of the app with the permission sets, so 22 pages and queries went
    unnoticed until the AppSource readiness review. This guard reads the AL source under app/src and
    reports three kinds of problem:

      not-granted   A page, query, report or xmlport that no assignable permission set grants (Execute),
                    directly, through a wildcard (page * = X) or through IncludedPermissionSets.
      source-table  A permission set grants a page whose source table is a Bifrost table (not a temporary
                    one) but does not grant tabledata on that table (R or r). Source tables of the base
                    application are not checked: no Bifrost set grants them.
      admin-page    A page that calls AssertLicenseAdmin is not granted by 'BIFROST LicAdm ori', or is
                    granted by 'BIFROST Read ori' or 'BIFROST API ori', which ordinary users hold.

    A new page therefore needs a line in the permission set of the role that uses it in the same change.
    There is no allow-list: an object that really needs no grant does not exist in this app.

.PARAMETER AppFolder
    The AL app folder (default: ../app next to this script).

.PARAMETER SelfTest
    Runs the guard against small synthetic apps and checks that it reports each kind of problem and
    passes a clean app. Exits 1 when it does not.

.EXAMPLE
    ./tools/Test-PermissionCoverage.ps1
#>
param(
    [string]$AppFolder = (Join-Path $PSScriptRoot '..\app'),
    [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'

# The sets ordinary users and service identities hold, and the set that administers licensing.
$script:OrdinarySets = @('BIFROST Read ori', 'BIFROST API ori')
$script:LicenseAdminSet = 'BIFROST LicAdm ori'
$script:ExecutableKinds = @('page', 'query', 'report', 'xmlport')

$objectHeader = [regex]::new('^\s*(page|query|report|xmlport|table|permissionset)\s+\d+\s+("([^"]+)"|(\w+))', 'IgnoreCase')
$grantLine = [regex]::new('\b(table|tabledata|page|query|report|xmlport)\s+("([^"]+)"|\*|(\w+))\s*=\s*([A-Za-z]*)', 'IgnoreCase')
$sourceTable = [regex]::new('^\s*SourceTable\s*=\s*("([^"]+)"|(\w+))\s*;', 'IgnoreCase')
$included = [regex]::new('IncludedPermissionSets\s*=\s*(?<list>[^;]*);', 'IgnoreCase')

function Read-Objects([string]$AppFolder) {
    $objects = [System.Collections.Generic.List[object]]::new()
    foreach ($file in Get-ChildItem -LiteralPath (Join-Path $AppFolder 'src') -Recurse -Filter '*.al') {
        $lines = @(Get-Content -LiteralPath $file.FullName -Encoding UTF8 | Where-Object { $_ -notmatch '^\s*//' })
        $text = $lines -join "`n"
        $header = $null
        foreach ($line in $lines) {
            $header = $objectHeader.Match($line)
            if ($header.Success) { break }
        }
        if (-not $header -or -not $header.Success) { continue }
        $kind = $header.Groups[1].Value.ToLowerInvariant()
        $name = if ($header.Groups[3].Success) { $header.Groups[3].Value } else { $header.Groups[4].Value }
        $object = [pscustomobject]@{
            Kind        = $kind
            Name        = $name
            File        = [System.IO.Path]::GetRelativePath($AppFolder, $file.FullName)
            Text        = $text
            Source      = $null
            Temporary   = $false
            Assignable  = ($text -match '(?i)Assignable\s*=\s*true')
            Grants      = [System.Collections.Generic.List[object]]::new()
            Includes    = [System.Collections.Generic.List[string]]::new()
        }
        if ($kind -eq 'page') {
            foreach ($line in $lines) {
                $m = $sourceTable.Match($line)
                if ($m.Success) { $object.Source = if ($m.Groups[2].Success) { $m.Groups[2].Value } else { $m.Groups[3].Value }; break }
            }
            $object.Temporary = ($text -match '(?i)SourceTableTemporary\s*=\s*true')
        }
        if ($kind -eq 'table') {
            $object.Temporary = ($text -match '(?i)TableType\s*=\s*Temporary')
        }
        if ($kind -eq 'permissionset') {
            foreach ($line in $lines) {
                foreach ($m in $grantLine.Matches($line)) {
                    $target = if ($m.Groups[3].Success) { $m.Groups[3].Value } elseif ($m.Groups[4].Success) { $m.Groups[4].Value } else { '*' }
                    $object.Grants.Add([pscustomobject]@{ Kind = $m.Groups[1].Value.ToLowerInvariant(); Name = $target; Letters = $m.Groups[5].Value })
                }
            }
            $inc = $included.Match($text)
            if ($inc.Success) {
                foreach ($part in $inc.Groups['list'].Value.Split(',')) {
                    $n = $part.Trim().Trim('"')
                    if ($n) { $object.Includes.Add($n) }
                }
            }
        }
        $objects.Add($object)
    }
    return , $objects
}

# The grants of a set and of every set it includes (sets of other apps are not known and add nothing).
function Get-EffectiveGrants($sets, [string]$name, $seen) {
    if ($seen.Contains($name) -or -not $sets.ContainsKey($name)) { return @() }
    [void]$seen.Add($name)
    $grants = [System.Collections.Generic.List[object]]::new()
    $grants.AddRange($sets[$name].Grants)
    foreach ($child in $sets[$name].Includes) {
        $inherited = Get-EffectiveGrants $sets $child $seen
        if ($inherited) { $grants.AddRange($inherited) }
    }
    return , $grants
}

function Test-Grants($grants, [string]$kind, [string]$name, [string]$letterPattern) {
    foreach ($g in $grants) {
        if ($g.Kind -ne $kind) { continue }
        if ($g.Name -ne $name -and $g.Name -ne '*') { continue }
        if ($g.Letters -match $letterPattern) { return $true }
    }
    return $false
}

function Find-Problems([string]$AppFolder) {
    $objects = Read-Objects $AppFolder
    $sets = @{}
    $tables = @{}
    foreach ($o in $objects) {
        if ($o.Kind -eq 'permissionset') { $sets[$o.Name] = $o }
        if ($o.Kind -eq 'table') { $tables[$o.Name] = $o }
    }
    $effective = @{}
    foreach ($name in $sets.Keys) {
        $effective[$name] = Get-EffectiveGrants $sets $name (New-Object 'System.Collections.Generic.HashSet[string]')
    }
    $assignable = @($sets.Keys | Where-Object { $sets[$_].Assignable } | Sort-Object)

    $problems = [System.Collections.Generic.List[string]]::new()
    foreach ($o in $objects | Where-Object { $script:ExecutableKinds -contains $_.Kind } | Sort-Object Kind, Name) {
        $grantedBy = @($assignable | Where-Object { Test-Grants $effective[$_] $o.Kind $o.Name '(?i)X' })
        if ($grantedBy.Count -eq 0) {
            $problems.Add("not-granted: $($o.Kind) ""$($o.Name)"" is granted by no assignable permission set ($($o.File))")
        }
        if ($o.Kind -ne 'page') { continue }

        foreach ($setName in $grantedBy) {
            $t = $o.Source
            if ($t -and $tables.ContainsKey($t) -and -not $o.Temporary -and -not $tables[$t].Temporary) {
                if (-not (Test-Grants $effective[$setName] 'tabledata' $t '(?i)R')) {
                    $problems.Add("source-table: ""$setName"" grants page ""$($o.Name)"" but not tabledata ""$t"" (its source table) ($($o.File))")
                }
            }
        }

        if ($o.Text -match 'AssertLicenseAdmin\s*\(') {
            if ($grantedBy -notcontains $script:LicenseAdminSet) {
                $problems.Add("admin-page: page ""$($o.Name)"" calls AssertLicenseAdmin but ""$($script:LicenseAdminSet)"" does not grant it ($($o.File))")
            }
            foreach ($ordinary in $script:OrdinarySets) {
                if ($grantedBy -contains $ordinary) {
                    $problems.Add("admin-page: page ""$($o.Name)"" calls AssertLicenseAdmin but ""$ordinary"" grants it to ordinary users ($($o.File))")
                }
            }
        }
    }
    return $problems.ToArray()
}

function Write-SyntheticApp([string]$Folder, [hashtable]$Files) {
    $src = Join-Path $Folder 'src'
    New-Item -ItemType Directory -Force -Path $src | Out-Null
    foreach ($name in $Files.Keys) {
        Set-Content -LiteralPath (Join-Path $src $name) -Value $Files[$name] -Encoding UTF8
    }
}

function Invoke-SelfTest {
    $root = Join-Path ([System.IO.Path]::GetTempPath()) ("perm-guard-" + [guid]::NewGuid().ToString('N'))
    $failed = $false
    try {
        $tableOk = "table 1 ""Real Tab ori""`n{`n}"
        $tableTemp = "table 2 ""Buffer ori""`n{`n    TableType = Temporary;`n}"
        $pageOk = "page 10 ""Ok Page ori""`n{`n    SourceTable = ""Real Tab ori"";`n}"
        $pageBuffer = "page 11 ""Buffer Page ori""`n{`n    SourceTable = ""Buffer ori"";`n}"
        $pageNoGrant = "page 12 ""Forgotten Page ori""`n{`n}"
        $queryNoGrant = "query 13 ""Forgotten Query ori""`n{`n}"
        $pageNoTable = "page 14 ""Table Missing Page ori""`n{`n    SourceTable = ""Real Tab ori"";`n}"
        $pageAdmin = "page 15 ""Admin Page ori""`n{`n    trigger OnOpenPage()`n    begin`n        UsageMgt.AssertLicenseAdmin();`n    end;`n}"
        $pageAdminLeak = "page 16 ""Leaked Admin Page ori""`n{`n    trigger OnOpenPage()`n    begin`n        UsageMgt.AssertLicenseAdmin();`n    end;`n}"
        $pageInherited = "page 17 ""Inherited Page ori""`n{`n}"
        $report = "report 18 ""Forgotten Report ori""`n{`n}"
        $unassignable = "page 19 ""Dead Grant Page ori""`n{`n}"
        $read = "permissionset 100 ""BIFROST Read ori""`n{`n    Assignable = true;`n    IncludedPermissionSets = ""Inner ori"";`n    Permissions =`n        table ""Real Tab ori"" = X,`n        tabledata ""Real Tab ori"" = R,`n        page ""Ok Page ori"" = X,`n        page ""Buffer Page ori"" = X,`n        page ""Leaked Admin Page ori"" = X;`n}"
        $inner = "permissionset 101 ""Inner ori""`n{`n    Access = Internal;`n    Assignable = false;`n    Permissions =`n        page ""Inherited Page ori"" = X;`n}"
        $lic = "permissionset 102 ""BIFROST LicAdm ori""`n{`n    Assignable = true;`n    Permissions =`n        page ""Admin Page ori"" = X,`n        page ""Leaked Admin Page ori"" = X,`n        page ""Table Missing Page ori"" = X;`n}"
        $dead = "permissionset 103 ""Dead ori""`n{`n    Assignable = false;`n    Permissions =`n        page ""Dead Grant Page ori"" = X;`n}"

        $badFiles = @{
            'tab.al' = $tableOk; 'tmp.al' = $tableTemp; 'p1.al' = $pageOk; 'p2.al' = $pageBuffer; 'p3.al' = $pageNoGrant
            'q1.al' = $queryNoGrant; 'p4.al' = $pageNoTable; 'p5.al' = $pageAdmin; 'p6.al' = $pageAdminLeak
            'p7.al' = $pageInherited; 'r1.al' = $report; 'p8.al' = $unassignable
            'read.al' = $read; 'inner.al' = $inner; 'lic.al' = $lic; 'dead.al' = $dead
        }
        Write-SyntheticApp (Join-Path $root 'bad') $badFiles
        $found = @(Find-Problems (Join-Path $root 'bad'))
        $expected = @(
            'not-granted: page "Forgotten Page ori"',
            'not-granted: query "Forgotten Query ori"',
            'not-granted: report "Forgotten Report ori"',
            'not-granted: page "Dead Grant Page ori"',
            'source-table: "BIFROST LicAdm ori" grants page "Table Missing Page ori" but not tabledata "Real Tab ori"',
            'admin-page: page "Leaked Admin Page ori" calls AssertLicenseAdmin but "BIFROST Read ori" grants it to ordinary users'
        )
        foreach ($e in $expected) {
            if (-not ($found | Where-Object { $_.StartsWith($e) })) { Write-Host "SelfTest FAILED: not reported: $e"; $failed = $true }
        }
        if ($found.Count -ne $expected.Count) { Write-Host "SelfTest FAILED: expected $($expected.Count) problems, got $($found.Count): $($found -join '; ')"; $failed = $true }

        $clean = @{
            'tab.al' = $tableOk; 'tmp.al' = $tableTemp; 'p1.al' = $pageOk; 'p2.al' = $pageBuffer; 'p5.al' = $pageAdmin; 'p7.al' = $pageInherited
            'read.al' = "permissionset 100 ""BIFROST Read ori""`n{`n    Assignable = true;`n    IncludedPermissionSets = ""Inner ori"";`n    Permissions =`n        tabledata ""Real Tab ori"" = r,`n        page ""Ok Page ori"" = X,`n        page ""Buffer Page ori"" = X;`n}"
            'inner.al' = $inner
            'lic.al' = "permissionset 102 ""BIFROST LicAdm ori""`n{`n    Assignable = true;`n    Permissions =`n        page ""Admin Page ori"" = X;`n}"
        }
        Write-SyntheticApp (Join-Path $root 'clean') $clean
        $found = @(Find-Problems (Join-Path $root 'clean'))
        if ($found.Count -ne 0) { Write-Host "SelfTest FAILED: a clean app must pass, got: $($found -join '; ')"; $failed = $true }

        $wild = @{
            'p3.al' = $pageNoGrant; 'q1.al' = $queryNoGrant
            'all.al' = "permissionset 100 ""All ori""`n{`n    Assignable = true;`n    Permissions =`n        page * = X,`n        query * = X;`n}"
        }
        Write-SyntheticApp (Join-Path $root 'wild') $wild
        $found = @(Find-Problems (Join-Path $root 'wild'))
        if ($found.Count -ne 0) { Write-Host "SelfTest FAILED: a wildcard grant must cover pages and queries, got: $($found -join '; ')"; $failed = $true }
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

$problems = @(Find-Problems $AppFolder)
if ($problems.Count -gt 0) {
    Write-Host "::error::$($problems.Count) page(s), query/queries or report(s) are not covered by the permission sets (#434). Grant each object to the set of the role that uses it, with the tabledata its page reads."
    $problems | ForEach-Object { Write-Host $_ }
    exit 1
}
Write-Host 'Every page, query, report and xmlport is granted by an assignable permission set.'
