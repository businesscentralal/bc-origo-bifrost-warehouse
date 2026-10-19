# Reconcile every expected postcompile hook against the actual output folders.
# Failed compiler paths rethrow before this hook: workflow evidence must retain failure.
& (Join-Path $env:GITHUB_WORKSPACE 'tools/Assert-AppSourceBuild.ps1') -Stage Finalize
