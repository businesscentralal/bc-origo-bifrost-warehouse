<#
.SYNOPSIS
Checks per-type object IDs, extended-enum ordinals and dependency identities before compilation.
#>
param([string]$RepositoryRoot = (Split-Path $PSScriptRoot -Parent))

$ErrorActionPreference = 'Stop'
& python (Join-Path $PSScriptRoot 'check_build_inputs.py') --root $RepositoryRoot
if ($LASTEXITCODE -ne 0) { throw 'Build input allocation/dependency checks failed.' }
