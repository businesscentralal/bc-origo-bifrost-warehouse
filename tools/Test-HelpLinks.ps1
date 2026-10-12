<#
.SYNOPSIS
    Verifies the context-sensitive help link of every page of the app.

.DESCRIPTION
    Every page and page extension under app/src must declare ContextSensitiveHelpPage, and the help
    page it names must exist on the documentation site (businesscentralal/bifrost) in both locales:

      en-US  help/<app>/<slug>.md
      is-IS  i18n/is-IS/docusaurus-plugin-content-docs-help-<app>/current/<slug>.md

    Business Central opens <contextSensitiveHelpUrl with the user's locale><slug>, so a missing file
    in either locale is a broken Help link for those users.

.PARAMETER DocsPath
    Path to a checkout of businesscentralal/bifrost.

.PARAMETER AppFolder
    The AL app folder (default: ../app next to this script).

.PARAMETER DocsApp
    The documentation app id the pages belong to (default: foundation).

.EXAMPLE
    ./tools/Test-HelpLinks.ps1 -DocsPath D:\Git\Public\bifrost
#>
param(
    [Parameter(Mandatory)][string]$DocsPath,
    [string]$AppFolder = (Join-Path $PSScriptRoot '..\app'),
    [string]$DocsApp = 'warehouse'
)

$ErrorActionPreference = 'Stop'
$enDir = Join-Path $DocsPath "help/$DocsApp"
$isDir = Join-Path $DocsPath "i18n/is-IS/docusaurus-plugin-content-docs-help-$DocsApp/current"
foreach ($dir in $enDir, $isDir) {
    if (-not (Test-Path -LiteralPath $dir)) { throw "Help folder not found: $dir" }
}

$problems = [System.Collections.Generic.List[string]]::new()
$pageCount = 0
Get-ChildItem -LiteralPath (Join-Path $AppFolder 'src') -Recurse -Filter '*.al' | ForEach-Object {
    $text = Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8
    $header = [regex]::Match($text, '(?m)^\s*(page|pageextension)\s+(\d+)\s+"([^"]+)"')
    if (-not $header.Success) { return }
    $pageCount++
    $name = "$($header.Groups[1].Value) $($header.Groups[2].Value) `"$($header.Groups[3].Value)`""
    $help = [regex]::Match($text, "ContextSensitiveHelpPage\s*=\s*'([^']*)'")
    if (-not $help.Success) {
        # A page extension inherits the help of the page it extends.
        if ($header.Groups[1].Value -eq 'page') { $problems.Add("$name has no ContextSensitiveHelpPage") }
        return
    }
    $slug = $help.Groups[1].Value
    if ($slug -notmatch '^[a-z0-9]+(-[a-z0-9]+)*$') {
        $problems.Add("$name uses '$slug' - use a lower-case kebab-case slug without '#' or '/'")
        return
    }
    if (-not (Test-Path -LiteralPath (Join-Path $enDir "$slug.md"))) { $problems.Add("$name -> '$slug': missing en-US help/$DocsApp/$slug.md") }
    if (-not (Test-Path -LiteralPath (Join-Path $isDir "$slug.md"))) { $problems.Add("$name -> '$slug': missing is-IS help page $slug.md") }
}

Write-Host "Checked $pageCount page(s) against $DocsPath"
if ($problems.Count -gt 0) {
    $problems | ForEach-Object { Write-Host "::error::$_" }
    throw "$($problems.Count) help link problem(s)."
}
Write-Host 'Every page links to a help page that exists in en-US and is-IS.'
