<#
.SYNOPSIS
    Fails when one procedure answers an English sentence that cannot be translated, next to the translated texts of the answer (#710, #722).

.DESCRIPTION
    A message type answers in the language of the call (#137). A label with Locked = true is never translated, so an
    answer that holds a Locked English sentence next to a translated nextStep, hint, expected value or suffix reads half
    English and half Icelandic at lcid 1039 (#684, #686, #701). PR #707 fixed the answers the Icelandic sweep found. This
    guard keeps the pattern from coming back.

    It reads the AL source under app/src and, for every procedure, collects the labels that end up in an answer:

      - the arguments of Error(...), RespondWith*(...), AddError(...) and AddWarning(...);
      - the arguments of a call to a procedure that answers (one that calls those, directly or through other procedures)
        when an argument carries a label, together with the labels that procedure uses itself. A Locked sentence passed to
        TryEvaluateJournalBatchKey is such a case: the procedure adds its own translated expected value to the same error;
      - the labels of a text variable that is assigned from a label and then passed on;
      - the labels the helper procedures called inside those arguments use (BuildInvalidFieldHint, a shared hint);
      - a string literal in those arguments that is an English sentence (a literal is never translated).

    A label counts as

      locked sentence  Locked = true and a sentence: at least three words, ending in . ! ? or : or holding a word such as
                       "or", "is", "must", "not". "a GUID or an integer" and "Table %1 not found." are sentences.
                       A technical token ("Data.Records.Get / Data.Records.Set", "BIFROST GL Post ori") is not.
      translated       a label without Locked = true that holds a word.

    A procedure that has both is reported, with the Locked labels and the translated ones. The fix is to translate the
    Locked sentence (remove Locked = true and add an is-IS= comment, then run tools/Update-IcelandicXlf.ps1), or, when the
    text is a technical key, to take it out of the answer. All text of one procedure is then in one language.

    The generic "hint" every error answer gets from Message Argument ori (AddHelpHint) and the "N problem(s) in the
    request." summary of a MultipleErrors answer (ProblemsInRequestErr) are translated by the platform for every type. They
    count as translated text of every answer (#722), so a Locked English sentence in an answer is a finding by itself, also
    when the procedure answers no other translated label. A Locked sentence that is handed to a procedure that answers
    counts only when that procedure puts the argument into its own answer (it is forwarded to Error, RespondWith*, AddError,
    AddWarning or RaiseCollected*, directly or through other procedures); a SQL string or a reason that is only stored does
    not.

    A second rule reads the names (#772). A label with Locked = true whose name ends in Err, Error, NextStep..., Expected...
    or Hint... is a refusal text, whatever the call that carries it looks like, when its text is English words
    ("Send subject.", "a duration", "%1 is required."). A text of single tokens ("id, identityInsert, primaryKey"), a format
    ("YYYY-MM-DD"), a name list ("Quote, Order, Credit Memo") or a type name ("object", "GUID") is not. The same test of
    English words, not only the test of a sentence, decides which labels in the arguments of an answer count as Locked.
    A real protocol token that is named like a refusal text goes in $AllowedLabels; it is empty and may only shrink.

    The allow-list ($AllowList, below) holds procedures that cannot be fixed now, one entry each with the reason. It is
    empty and may only shrink: an entry whose procedure is no longer reported is stale and fails.

    The source is read with regular expressions, not compiled, so a label reached only through a receiver the guard
    cannot resolve (a variable of another type, a call through a chain) is not followed. That makes the guard miss a case;
    it never reports a procedure whose answer is one language.

.PARAMETER AppFolder
    The AL app folder (default: ../app next to this script).

.PARAMETER Explain
    A procedure name. Prints the labels the guard collected for every procedure of that name, reported or not, and exits 0.

.PARAMETER SelfTest
    Runs the guard against a small synthetic app and checks that it reports a Locked sentence next to a translated
    nextStep, a Locked sentence handed to an answering helper, a Locked text variable, a Locked literal, and a stale
    allow-list entry, and that it passes consistent procedures. Exits 1 when it does not.

.EXAMPLE
    ./tools/Test-MixedLanguageLabels.ps1
#>
param(
    [string]$AppFolder = (Join-Path $PSScriptRoot '..\app'),
    [switch]$SelfTest,
    [string]$Explain = ''
)

$ErrorActionPreference = 'Stop'

# Procedures that cannot be fixed now. File is relative to the app folder, with forward slashes. Procedure is the name
# in the file. Reason names the follow-up issue. Empty on purpose.
$script:AllowList = @()

# Labels that carry an Err, NextStep, Expected or Hint name and a Locked English text, but are real protocol tokens. File is
# relative to the app folder, with forward slashes. Empty on purpose; it may only shrink.
$script:AllowedLabels = @()

# A label named like a refusal text (Err, Error, NextStep..., Expected..., Hint...) is read by the caller (#772).
$script:RefusalLabelName = [regex]::new('(?:Err|Error|NextStep\w*|Expected\w*|Hint\w*)$')

# The translated texts Message Argument ori adds to every error answer on its own: the generic hint (AddHelpHint, every
# error answer of a type that is not Help.*) and the summary of a MultipleErrors answer (ProblemsInRequestErr).
$script:PlatformTexts = @('Message Argument ori.generic hint', 'Message Argument ori.ProblemsInRequestErr')

$script:Stopwords = [System.Collections.Generic.HashSet[string]]::new(
    [string[]]@('a', 'an', 'the', 'or', 'of', 'is', 'are', 'was', 'were', 'to', 'with', 'at', 'in', 'on', 'for', 'and', 'not', 'no', 'be', 'must',
        'has', 'have', 'can', 'cannot', 'which', 'that', 'from', 'by', 'it', 'per', 'than', 'into', 'as', 'but', 'if', 'when', 'only'),
    [System.StringComparer]::OrdinalIgnoreCase)

# The calls whose arguments are the answer. Everything else that answers is found from them.
$script:GenericSinks = @('respondwitherror', 'adderror', 'addwarning', 'error', 'raisecollectederrors')
# Built-ins and generic helpers that carry text but add none of their own.
$script:TextCarriers = [System.Collections.Generic.HashSet[string]]::new(
    [string[]]@('strsubstno', 'format', 'copystr', 'strlen', 'lowercase', 'uppercase', 'selectstr', 'exit', 'add', 'replace', 'get', 'contains',
        'respondwitherror', 'adderror', 'addwarning', 'error', 'respondwithcollectederrors', 'respondwithcollectedproblems',
        'raisecollectederrors', 'respondwithlasterror'),
    [System.StringComparer]::OrdinalIgnoreCase)

$objectStart = [regex]::new('^\s*(codeunit|table|page|enum|enumextension|interface|tableextension|pageextension|query|report|xmlport|permissionset|permissionsetextension)\s+\d*\s*"([^"]+)"', 'IgnoreCase, Multiline')
$procedureStart = [regex]::new('^[ \t]*(?:\[[^\]\r\n]*\]\s*)*(?:(?:local|internal|protected)\s+)?(?:procedure|trigger)\s+(?<name>"[^"]+"|\w+)', 'IgnoreCase, Multiline')
$beginLine = [regex]::new('^\s*begin\b', 'IgnoreCase, Multiline')
$labelDeclaration = [regex]::new("(?<name>""[^""]+""|\w+)\s*:\s*Label\s+'(?<text>(?:[^']|'')*)'\s*(?<props>(?:,(?:[^;']|'(?:[^']|'')*')*)?);", 'IgnoreCase')
$variableDeclaration = [regex]::new('(?<![\w])(?<var>\w+)\s*:\s*(?:Codeunit|Record)\s+"(?<type>[^"]+)"', 'IgnoreCase')
$commentOrString = [regex]::new("(?<s>'(?:[^']|'')*')|//[^\r\n]*")
$stringLiteral = [regex]::new("'(?:[^']|'')*'")
$statementPiece = [regex]::new("(?:'(?:[^']|'')*'|[^';])+")
$identifier = [regex]::new('"[^"]+"|\w+')
$callSite = [regex]::new('(?<![\w])(?:(?<recv>\w+)\.)?(?<name>\w+)\s*\(')
$sinkSite = [regex]::new('^(?:(?:\w+)\.)?(RespondWith\w*|AddError|AddWarning|RaiseCollected\w*|Error)\s*\(', 'IgnoreCase')
$assignment = [regex]::new('(?<![\w."])(?<var>\w+)\s*:=(?<rhs>[^;]*)')
$parameterList = [regex]::new('(?is)\b(?:procedure|trigger)\s+(?:"[^"]+"|\w+)\s*\((?<p>[^)]*)\)')
$parameterName = [regex]::new('^\s*(?:var\s+)?(?<n>[\w", ]+?)\s*:')
$answerName = [regex]::new('^(?:RespondWith\w*|AddError|AddWarning|RaiseCollected\w*|Error)$', 'IgnoreCase')
$seedCall = [regex]::new('(?<![\w])(?:\w+\.)?(?:RespondWith\w*|AddError|AddWarning|RaiseCollected\w*|Error)\s*\(', 'IgnoreCase')

function Test-Prose([string]$Text) {
    $s = [regex]::Replace($Text, '%\d+|\{\d*\}', '').Trim()
    $words = [regex]::Matches($s, "[A-Za-z][A-Za-z']*")
    if ($words.Count -lt 3) { return $false }
    if ([regex]::IsMatch($s, "[.!?:]['"")\]]*$")) { return $true }
    foreach ($w in $words) { if ($script:Stopwords.Contains($w.Value)) { return $true } }
    return $false
}

# True for English words in a text (#772): at least two plain words, such as "a duration", "Send subject." or "Error
# processing record %1". Not a sentence by Test-Prose (no end mark, fewer than three words), but still English next to an
# Icelandic answer. A text of single tokens ("id, identityInsert, primaryKey, fields", "Data.Records.Get / Data.Records.Set"),
# an identifier, a format ("YYYY-MM-DD") or a type name ("object", "GUID") is not.
function Test-Words([string]$Text) {
    $s = [regex]::Replace($Text, '%\d+|\{\d*\}', ' ').Trim()
    if ($s -notmatch '\s') { return $false }
    $items = $s -split '\s*[,;/|]\s*'
    $singleTokens = $true
    foreach ($item in $items) { if ($item.Trim() -match '\s') { $singleTokens = $false; break } }
    if ($singleTokens) { return $false }
    # Lowercase words, and the capitalized first word of a sentence. A capitalized word elsewhere is a name ("Credit Memo").
    $plain = 0
    foreach ($m in [regex]::Matches($s, '(?<![\w.])[a-z]+(?!\w|\.\w|\()')) {
        if ($m.Value.Length -eq 1 -and $m.Value -cne 'a') { continue }
        $plain++
    }
    if ($s -cmatch '^"?[A-Z][a-z]+(?!\w|\.\w|\()') { $plain++ }
    return $plain -ge 2
}

# 'L' for a Locked sentence, 'T' for a translated label that holds a word, $null for anything else (a Locked token, a bare placeholder).
function Get-LabelKind($Label) {
    if ($Label.Locked) {
        if ((Test-Prose $Label.Text) -or (Test-Words $Label.Text)) { return 'L' }
        return $null
    }
    if ([regex]::IsMatch([regex]::Replace($Label.Text, '%\d+', ''), '[A-Za-z]{2,}')) { return 'T' }
    return $null
}

function Read-Source([string]$AppSrc) {
    $objects = @{}
    foreach ($file in Get-ChildItem -LiteralPath $AppSrc -Recurse -Filter '*.al') {
        $text = [System.IO.File]::ReadAllText($file.FullName, [System.Text.Encoding]::UTF8)
        $header = $objectStart.Match($text)
        if (-not $header.Success) { continue }
        $name = $header.Groups[2].Value
        if (-not $objects.ContainsKey($name)) {
            $objects[$name] = @{ Name = $name; Labels = @{}; Variables = @{}; Procedures = @{}; List = [System.Collections.Generic.List[object]]::new() }
        }
        $object = $objects[$name]
        $relative = [System.IO.Path]::GetRelativePath($AppSrc, $file.FullName).Replace('\', '/')
        $starts = $procedureStart.Matches($text)
        $lineNo = 1
        $scanned = 0
        $declarationSpans = [System.Collections.Generic.List[int[]]]::new()
        for ($i = 0; $i -lt $starts.Count; $i++) {
            $from = $starts[$i].Index
            $to = if ($i + 1 -lt $starts.Count) { $starts[$i + 1].Index } else { $text.Length }
            $segment = $text.Substring($from, $to - $from)
            $begin = $beginLine.Match($segment)
            $declaration = if ($begin.Success) { $segment.Substring(0, $begin.Index) } else { $segment }
            $code = if ($begin.Success) { $commentOrString.Replace($segment.Substring($begin.Index), '${s}') } else { '' }
            $declarationSpans.Add([int[]]@($from, $from + $declaration.Length))
            $locals = @{}
            foreach ($l in $labelDeclaration.Matches($declaration)) {
                $locals[$l.Groups['name'].Value.Trim('"')] = @{ Name = $l.Groups['name'].Value.Trim('"'); File = $relative; Index = $from + $l.Index; Text = $l.Groups['text'].Value.Replace("''", "'"); Locked = ($l.Groups['props'].Value -match '(?i)locked\s*=\s*true') }
            }
            $variables = @{}
            foreach ($v in $variableDeclaration.Matches($declaration)) { $variables[$v.Groups['var'].Value.ToLowerInvariant()] = $v.Groups['type'].Value }
            $procName = $starts[$i].Groups['name'].Value.Trim('"')
            $params = [System.Collections.Generic.List[string]]::new()
            $paramList = $parameterList.Match($declaration)
            if ($paramList.Success) {
                foreach ($piece in $paramList.Groups['p'].Value.Split(';')) {
                    $named = $parameterName.Match($piece)
                    if ($named.Success) { foreach ($n in $named.Groups['n'].Value.Split(',')) { $params.Add($n.Trim().Trim('"')) } }
                }
            }
            $nl = $text.IndexOf("`n", $scanned, [Math]::Max(0, $from - $scanned))
            while ($nl -ge 0) { $lineNo++; $scanned = $nl + 1; $nl = if ($scanned -lt $from) { $text.IndexOf("`n", $scanned, $from - $scanned) } else { -1 } }
            $scanned = $from
            $proc = @{
                Name = $procName; File = $relative; Line = $lineNo
                Locals = $locals; Variables = $variables; Code = $code; Object = $name
                Key = "$name|$procName|$from"; Own = $null; Blank = $null; CalleeKeys = $null; HasSeed = $false
                Params = $params; SinkText = $null; Forwards = @{}
            }
            $object.List.Add($proc)
            $lower = $procName.ToLowerInvariant()
            if (-not $object.Procedures.ContainsKey($lower)) { $object.Procedures[$lower] = [System.Collections.Generic.List[object]]::new() }
            $object.Procedures[$lower].Add($proc)
        }
        foreach ($l in $labelDeclaration.Matches($text)) {
            $inside = $false
            foreach ($span in $declarationSpans) { if ($l.Index -ge $span[0] -and $l.Index -lt $span[1]) { $inside = $true; break } }
            if ($inside) { continue }
            $object.Labels[$l.Groups['name'].Value.Trim('"')] = @{ Name = $l.Groups['name'].Value.Trim('"'); File = $relative; Index = $l.Index; Text = $l.Groups['text'].Value.Replace("''", "'"); Locked = ($l.Groups['props'].Value -match '(?i)locked\s*=\s*true') }
        }
        $firstProcedure = if ($starts.Count -gt 0) { $starts[0].Index } else { $text.Length }
        foreach ($v in $variableDeclaration.Matches($text.Substring(0, $firstProcedure))) { $object.Variables[$v.Groups['var'].Value.ToLowerInvariant()] = $v.Groups['type'].Value }
    }
    return $objects
}

function Find-Label($Object, $Proc, [string]$Name) {
    if ($Proc.Locals.ContainsKey($Name)) { return $Proc.Locals[$Name] }
    if ($Object.Labels.ContainsKey($Name)) { return $Object.Labels[$Name] }
    return $null
}

# The procedures a call may reach: the same object for an unqualified call, the declared type of the receiver otherwise.
function Resolve-Call($Objects, $Object, $Proc, $Receiver, [string]$Name) {
    $targets = @()
    if (-not $Receiver) { $targets = @($Object) }
    else {
        $typeName = $Proc.Variables[$Receiver.ToLowerInvariant()]
        if (-not $typeName) { $typeName = $Object.Variables[$Receiver.ToLowerInvariant()] }
        if ($typeName -and $Objects.ContainsKey($typeName)) { $targets = @($Objects[$typeName]) }
    }
    foreach ($t in $targets) {
        if ($t.Procedures.ContainsKey($Name.ToLowerInvariant())) {
            foreach ($q in $t.Procedures[$Name.ToLowerInvariant()]) { [pscustomobject]@{ Object = $t; Proc = $q } }
        }
    }
}

function Get-Blanked([string]$Text) { return $stringLiteral.Replace($Text, "''") }

# The code of a procedure with its string literals emptied, built once.
function Get-BlankCode($Proc) {
    if ($null -eq $Proc.Blank) { $Proc.Blank = Get-Blanked $Proc.Code }
    return $Proc.Blank
}

# The kinds of the labels a procedure names in its body, as 'K|Object.Label'.
function Get-OwnLabels($Objects, $Object, $Proc) {
    if ($null -ne $Proc.Own) { return $Proc.Own }
    $kinds = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($m in $identifier.Matches((Get-BlankCode $Proc))) {
        $label = Find-Label $Object $Proc $m.Value.Trim('"')
        if ($label) {
            $k = Get-LabelKind $label
            if ($k) { [void]$kinds.Add("$k|$($Object.Name).$($m.Value.Trim('"'))") }
        }
    }
    $Proc.Own = $kinds
    return $kinds
}

# Marks every procedure that answers: it calls Error/RespondWith*/AddError/AddWarning/RaiseCollected*, or a procedure that does.
function Find-Answering($Objects) {
    $answering = [System.Collections.Generic.HashSet[string]]::new()
    $all = [System.Collections.Generic.List[object]]::new()
    foreach ($o in $Objects.Values) { foreach ($p in $o.List) { $all.Add(@{ Object = $o; Proc = $p }) } }
    foreach ($e in $all) {
        $proc = $e.Proc
        $proc.CalleeKeys = [System.Collections.Generic.HashSet[string]]::new()
        $proc.HasSeed = $seedCall.IsMatch($proc.Code)
        if ($proc.HasSeed) { [void]$answering.Add($proc.Key) }
        $seen = [System.Collections.Generic.HashSet[string]]::new()
        foreach ($m in $callSite.Matches((Get-BlankCode $proc))) {
            $name = $m.Groups['name'].Value
            if ($script:TextCarriers.Contains($name)) { continue }
            $recv = if ($m.Groups['recv'].Success -and $m.Groups['recv'].Value) { $m.Groups['recv'].Value } else { $null }
            if (-not $seen.Add("$recv.$name")) { continue }
            foreach ($r in (Resolve-Call $Objects $e.Object $proc $recv $name)) { [void]$proc.CalleeKeys.Add($r.Proc.Key) }
        }
    }
    do {
        $changed = $false
        foreach ($e in $all) {
            $proc = $e.Proc
            if ($answering.Contains($proc.Key)) { continue }
            foreach ($key in $proc.CalleeKeys) {
                if ($answering.Contains($key)) { [void]$answering.Add($proc.Key); $changed = $true; break }
            }
        }
    } while ($changed)
    return $answering
}

function Get-ArgumentText([string]$Statement, [int]$OpenIndex) {
    $depth = 0
    $inString = $false
    for ($i = $OpenIndex; $i -lt $Statement.Length; $i++) {
        $c = $Statement[$i]
        if ($inString) {
            if ($c -eq "'") {
                if ($i + 1 -lt $Statement.Length -and $Statement[$i + 1] -eq "'") { $i++ } else { $inString = $false }
            }
        }
        elseif ($c -eq "'") { $inString = $true }
        elseif ($c -eq '(') { $depth++ }
        elseif ($c -eq ')') {
            $depth--
            if ($depth -eq 0) { return $Statement.Substring($OpenIndex + 1, $i - $OpenIndex - 1) }
        }
    }
    return $Statement.Substring($OpenIndex + 1)
}

# The top-level arguments of a call, from the text between its parentheses.
function Split-Arguments([string]$Text) {
    $parts = [System.Collections.Generic.List[string]]::new()
    $depth = 0
    $inString = $false
    $start = 0
    for ($i = 0; $i -lt $Text.Length; $i++) {
        $c = $Text[$i]
        if ($inString) {
            if ($c -eq "'") {
                if ($i + 1 -lt $Text.Length -and $Text[$i + 1] -eq "'") { $i++ } else { $inString = $false }
            }
        }
        elseif ($c -eq "'") { $inString = $true }
        elseif ($c -eq '(' -or $c -eq '[') { $depth++ }
        elseif ($c -eq ')' -or $c -eq ']') { $depth-- }
        elseif ($c -eq ',' -and $depth -eq 0) { $parts.Add($Text.Substring($start, $i - $start)); $start = $i + 1 }
    }
    $parts.Add($Text.Substring($start))
    return $parts
}

# The text of all arguments of the calls in a procedure that put text into the answer.
function Get-SinkText($Proc) {
    if ($null -ne $Proc.SinkText) { return $Proc.SinkText }
    $builder = [System.Text.StringBuilder]::new()
    foreach ($piece in $statementPiece.Matches($Proc.Code)) {
        foreach ($m in $callSite.Matches($piece.Value)) {
            if ($answerName.IsMatch($m.Groups['name'].Value)) { [void]$builder.Append((Get-ArgumentText $piece.Value ($m.Index + $m.Length - 1))).Append(' ') }
        }
    }
    $Proc.SinkText = $builder.ToString()
    return $Proc.SinkText
}

function Test-Identifier([string]$Text, [string]$Name) {
    return [regex]::IsMatch((Get-Blanked $Text), '(?<![\w."])"?' + [regex]::Escape($Name) + '"?(?![\w"])', 'IgnoreCase')
}

# True when the text of the Index-th parameter of a procedure ends up in the answer: it is an argument of a call that
# answers, it is assigned to a variable that is, or it is handed on to another procedure that forwards it.
function Test-Forwards($Objects, $Answering, $Object, $Proc, [int]$Index, [int]$Depth = 0) {
    if ($Index -ge $Proc.Params.Count -or $Depth -gt 4) { return $false }
    $key = "$Index"
    if ($Proc.Forwards.ContainsKey($key)) { return $Proc.Forwards[$key] }
    $Proc.Forwards[$key] = $false
    $name = $Proc.Params[$Index]
    $sinkText = Get-SinkText $Proc
    $found = Test-Identifier $sinkText $name
    if (-not $found) {
        $carriers = @($name)
        $statements = @($statementPiece.Matches($Proc.Code) | ForEach-Object { $_.Value })
        for ($round = 0; $round -lt 3 -and -not $found; $round++) {
            foreach ($s in $statements) {
                foreach ($a in $assignment.Matches($s)) {
                    $rhs = $a.Groups['rhs'].Value
                    foreach ($c in $carriers) {
                        if (Test-Identifier $rhs $c) {
                            if (Test-Identifier $sinkText $a.Groups['var'].Value) { $found = $true }
                            elseif ($carriers -notcontains $a.Groups['var'].Value) { $carriers += $a.Groups['var'].Value }
                        }
                    }
                }
            }
        }
        if (-not $found) {
            foreach ($s in $statements) {
                foreach ($m in $callSite.Matches($s)) {
                    $callName = $m.Groups['name'].Value
                    if ($script:TextCarriers.Contains($callName)) { continue }
                    $recv = if ($m.Groups['recv'].Success -and $m.Groups['recv'].Value) { $m.Groups['recv'].Value } else { $null }
                    $callArguments = @(Split-Arguments (Get-ArgumentText $s ($m.Index + $m.Length - 1)))
                    for ($j = 0; $j -lt $callArguments.Count -and -not $found; $j++) {
                        $hit = $false
                        foreach ($c in $carriers) { if (Test-Identifier $callArguments[$j] $c) { $hit = $true } }
                        if (-not $hit) { continue }
                        foreach ($r in (Resolve-Call $Objects $Object $Proc $recv $callName)) {
                            if ($r.Proc.Key -ne $Proc.Key -and $Answering.Contains($r.Proc.Key) -and (Test-Forwards $Objects $Answering $r.Object $r.Proc $j ($Depth + 1))) { $found = $true; break }
                        }
                    }
                    if ($found) { break }
                }
                if ($found) { break }
            }
        }
    }
    $Proc.Forwards[$key] = $found
    return $found
}

# All labels of one procedure's answers, as a set of 'K|Object.Label' (K = L or T) plus the literal sentences ('L|literal:...').
function Get-AnswerKinds($Objects, $Answering, $Object, $Proc) {
    $kinds = [System.Collections.Generic.HashSet[string]]::new()
    $reachesAnswer = $Proc.HasSeed
    if (-not $reachesAnswer) { foreach ($key in $Proc.CalleeKeys) { if ($Answering.Contains($key)) { $reachesAnswer = $true; break } } }
    if (-not $reachesAnswer) { return $kinds }
    $statements = @($statementPiece.Matches($Proc.Code) | ForEach-Object { $_.Value })
    $assigned = @{}
    foreach ($s in $statements) {
        foreach ($a in $assignment.Matches($s)) {
            $key = $a.Groups['var'].Value.ToLowerInvariant()
            if (-not $assigned.ContainsKey($key)) { $assigned[$key] = [System.Collections.Generic.List[string]]::new() }
            $assigned[$key].Add($a.Groups['rhs'].Value)
        }
    }
    $expression = $null
    $expression = {
        param([string]$Text, [System.Collections.Generic.HashSet[string]]$Seen)
        $found = [System.Collections.Generic.HashSet[string]]::new()
        # The length of a text is not the text (MaxStrLen(PostingDescription) hands on a number).
        $blanked = [regex]::Replace((Get-Blanked $Text), '(?i)\b(?:MaxStrLen|StrLen)\s*\([^()]*\)', '0')
        foreach ($m in $identifier.Matches($blanked)) {
            $n = $m.Value.Trim('"')
            $label = Find-Label $Object $Proc $n
            if ($label) {
                $k = Get-LabelKind $label
                if ($k) { [void]$found.Add("$k|$($Object.Name).$n") }
            }
            elseif ($assigned.ContainsKey($n.ToLowerInvariant()) -and -not $Seen.Contains($n.ToLowerInvariant())) {
                $inner = [System.Collections.Generic.HashSet[string]]::new($Seen)
                [void]$inner.Add($n.ToLowerInvariant())
                foreach ($rhs in $assigned[$n.ToLowerInvariant()]) { foreach ($x in (& $expression $rhs $inner)) { [void]$found.Add($x) } }
            }
        }
        foreach ($m in $callSite.Matches($blanked)) {
            if ($script:TextCarriers.Contains($m.Groups['name'].Value)) { continue }
            $recv = if ($m.Groups['recv'].Success -and $m.Groups['recv'].Value) { $m.Groups['recv'].Value } else { $null }
            foreach ($r in (Resolve-Call $Objects $Object $Proc $recv $m.Groups['name'].Value)) {
                if ($r.Proc.Key -eq $Proc.Key) { continue }
                foreach ($x in (Get-OwnLabels $Objects $r.Object $r.Proc)) { [void]$found.Add($x) }
            }
        }
        return $found
    }
    $literals = {
        param([string]$Text)
        $found = [System.Collections.Generic.List[string]]::new()
        foreach ($m in $stringLiteral.Matches($Text)) {
            $inner = $m.Value.Substring(1, $m.Value.Length - 2).Replace("''", "'")
            if ($inner.Contains(' ') -and (Test-Prose $inner)) { $found.Add("L|literal:" + $inner.Substring(0, [Math]::Min(40, $inner.Length))) }
        }
        return $found
    }
    foreach ($s in $statements) {
        foreach ($m in $callSite.Matches($s)) {
            $name = $m.Groups['name'].Value
            $recv = if ($m.Groups['recv'].Success -and $m.Groups['recv'].Value) { $m.Groups['recv'].Value } else { $null }
            $arguments = Get-ArgumentText $s ($m.Index + $m.Length - 1)
            $isSink = $sinkSite.IsMatch($s.Substring($m.Index))
            if ($isSink) {
                foreach ($x in (& $expression $arguments ([System.Collections.Generic.HashSet[string]]::new()))) { [void]$kinds.Add($x) }
                foreach ($x in (& $literals $arguments)) { [void]$kinds.Add($x) }
                if ($script:GenericSinks -notcontains $name.ToLowerInvariant() -and $name -notmatch '^(?i)respondwithcollected|^(?i)respondwithlasterror') {
                    foreach ($r in (Resolve-Call $Objects $Object $Proc $recv $name)) {
                        if ($r.Proc.Key -ne $Proc.Key) { foreach ($x in (Get-OwnLabels $Objects $r.Object $r.Proc)) { [void]$kinds.Add($x) } }
                    }
                }
                continue
            }
            if ($script:TextCarriers.Contains($name)) { continue }
            $callArguments = @(Split-Arguments $arguments)
            foreach ($r in (Resolve-Call $Objects $Object $Proc $recv $name)) {
                if ($r.Proc.Key -eq $Proc.Key -or -not $Answering.Contains($r.Proc.Key)) { continue }
                # Only an argument the procedure puts into its answer counts; a SQL string or a stored reason does not.
                $given = [System.Collections.Generic.HashSet[string]]::new()
                for ($j = 0; $j -lt $callArguments.Count; $j++) {
                    if (-not (Test-Forwards $Objects $Answering $r.Object $r.Proc $j)) { continue }
                    foreach ($x in (& $expression $callArguments[$j] ([System.Collections.Generic.HashSet[string]]::new()))) { [void]$given.Add($x) }
                    foreach ($x in (& $literals $callArguments[$j])) { [void]$given.Add($x) }
                }
                if ($given.Count -gt 0) {
                    foreach ($x in $given) { [void]$kinds.Add($x) }
                    foreach ($x in (Get-OwnLabels $Objects $r.Object $r.Proc)) { [void]$kinds.Add($x) }
                }
            }
        }
    }
    return $kinds
}

function Find-MixedLanguage([string]$AppFolder, [object[]]$Allowed, [string]$ExplainName = '') {
    $objects = Read-Source (Join-Path $AppFolder 'src')
    $answering = Find-Answering $objects
    $violations = [System.Collections.Generic.List[string]]::new()
    $used = @{}
    foreach ($entry in $Allowed) { $used["$($entry.File)|$($entry.Procedure)"] = 0 }
    foreach ($object in ($objects.Values | Sort-Object { $_.Name })) {
        foreach ($proc in $object.List) {
            if ($ExplainName -and $proc.Name -ne $ExplainName) { continue }
            $kinds = Get-AnswerKinds $objects $answering $object $proc
            $locked = @($kinds | Where-Object { $_.StartsWith('L|') } | ForEach-Object { $_.Substring(2) } | Sort-Object)
            $translated = @($kinds | Where-Object { $_.StartsWith('T|') } | ForEach-Object { $_.Substring(2) } | Sort-Object)
            if ($ExplainName) {
                Write-Host "$($proc.File):$($proc.Line): $($proc.Name)"
                Write-Host "  locked sentence: $($locked -join ', ')"
                Write-Host "  translated     : $($translated -join ', ')"
                continue
            }
            if ($locked.Count -eq 0) { continue }
            $translated = @($script:PlatformTexts) + $translated
            $allowKey = "$($proc.File)|$($proc.Name)"
            if ($used.ContainsKey($allowKey)) { $used[$allowKey]++; continue }
            $violations.Add("$($proc.File):$($proc.Line): [mixed-language] $($proc.Name) answers a Locked sentence (" + ($locked -join ', ') + ') next to translated text (' + (($translated | Select-Object -First 6) -join ', ') + $(if ($translated.Count -gt 6) { ', ...' } else { '' }) + ')')
        }
    }
    if (-not $ExplainName) {
        $usedLabels = @{}
        foreach ($entry in $script:AllowedLabels) { $usedLabels["$($entry.File)|$($entry.Label)"] = 0 }
        foreach ($object in ($objects.Values | Sort-Object { $_.Name })) {
            $labels = [System.Collections.Generic.List[object]]::new()
            foreach ($l in $object.Labels.Values) { $labels.Add($l) }
            foreach ($proc in $object.List) { foreach ($l in $proc.Locals.Values) { $labels.Add($l) } }
            foreach ($label in ($labels | Sort-Object { $_.File }, { $_.Index })) {
                if (-not $label.Locked -or -not $script:RefusalLabelName.IsMatch($label.Name)) { continue }
                if (-not ((Test-Prose $label.Text) -or (Test-Words $label.Text))) { continue }
                $allowKey = "$($label.File)|$($label.Name)"
                if ($usedLabels.ContainsKey($allowKey)) { $usedLabels[$allowKey]++; continue }
                $before = [System.IO.File]::ReadAllText((Join-Path (Join-Path $AppFolder 'src') $label.File), [System.Text.Encoding]::UTF8)
                $line = ($before.Substring(0, [Math]::Min($label.Index, $before.Length)).Split("`n")).Count
                $violations.Add("$($label.File):$($line): [locked-label] $($object.Name).$($label.Name) is named like a refusal text (Err, NextStep, Expected, Hint) and holds the Locked English text '$($label.Text.Substring(0, [Math]::Min(60, $label.Text.Length)))'")
            }
        }
        foreach ($entry in $script:AllowedLabels) {
            if ($usedLabels["$($entry.File)|$($entry.Label)"] -eq 0) {
                $violations.Add("$($entry.File): [stale-allow-list] label $($entry.Label) is no longer a Locked refusal text; remove the entry from `$AllowedLabels in tools/Test-MixedLanguageLabels.ps1")
            }
        }
    }
    foreach ($entry in $Allowed) {
        if ($used["$($entry.File)|$($entry.Procedure)"] -eq 0) {
            $violations.Add("$($entry.File): [stale-allow-list] $($entry.Procedure) no longer mixes Locked and translated text; remove the entry from `$AllowList in tools/Test-MixedLanguageLabels.ps1")
        }
    }
    return ,$violations
}

function Invoke-SelfTest {
    $root = Join-Path ([System.IO.Path]::GetTempPath()) ("mixed-language-" + [guid]::NewGuid().ToString('N'))
    $src = Join-Path $root 'src'
    New-Item -ItemType Directory -Path $src -Force | Out-Null
    try {
        @'
codeunit 1 "Helper ori"
{
    procedure RespondWithPair(var Argument: Record "Message Argument ori"; MessageText: Text)
    var
        ExpectedTxt: Label 'a whole number', Comment = 'is-IS=whole number is';
    begin
        Argument.AddError("Bifrost Error Code ori"::InvalidParameter, MessageText, 'amount', '', ExpectedTxt, '');
    end;

    procedure NoText(var Argument: Record "Message Argument ori")
    var
        HintTxt: Label 'Send a number.', Comment = 'is-IS=Send number.';
    begin
        Argument.AddError("Bifrost Error Code ori"::InvalidParameter, HintTxt, 'amount', '', '', '');
    end;

    procedure SaveReason(var Argument: Record "Message Argument ori"; Reason: Text; Missing: Text)
    var
        MissingTxt: Label 'Send a reason.', Comment = 'is-IS=Send reason.';
    begin
        Store.Save(Reason);
        if Missing = '' then
            Argument.AddError("Bifrost Error Code ori"::InvalidParameter, MissingTxt, 'reason', '', '', '');
    end;

    procedure Description(): Text
    var
        PlainTxt: Label 'A plain description of the thing.', Comment = 'is-IS=Plain description.';
    begin
        exit(PlainTxt);
    end;
}
'@ | Set-Content -LiteralPath (Join-Path $src 'Helper.Codeunit.al') -Encoding UTF8
        @'
codeunit 2 "Bad ori"
{
    var
        GlobalLockedErr: Label 'The thing %1 was not found.', Comment = '%1 = name', Locked = true;

    procedure SameCall(var Argument: Record "Message Argument ori")
    var
        FailedErr: Label 'The request failed.', Locked = true;
        NextStepTxt: Label 'Send it again.', Comment = 'is-IS=Send again.';
    begin
        Argument.AddError("Bifrost Error Code ori"::PreconditionFailed, FailedErr, '', '', '', NextStepTxt);
    end;

    procedure ThroughHelper(var Argument: Record "Message Argument ori")
    var
        Helper: Codeunit "Helper ori";
    begin
        Helper.RespondWithPair(Argument, StrSubstNo(GlobalLockedErr, 'x'));
    end;

    procedure LiteralThroughHelper(var Argument: Record "Message Argument ori")
    var
        Helper: Codeunit "Helper ori";
    begin
        Helper.RespondWithPair(Argument, 'The amount to apply cannot be zero here.');
    end;

    procedure ThroughVariable(var Argument: Record "Message Argument ori")
    var
        StepLockedTxt: Label 'Check the setup first.', Locked = true;
        ErrorTxt: Label 'The setup is incomplete.', Comment = 'is-IS=Setup incomplete.';
        NextStep: Text;
    begin
        NextStep := StepLockedTxt;
        Argument.RespondWithError("Bifrost Error Code ori"::PreconditionFailed, ErrorTxt, '', '', '', NextStep);
    end;

    procedure LiteralSentence(var Argument: Record "Message Argument ori")
    var
        NextStepTxt: Label 'Send it again.', Comment = 'is-IS=Send again.';
    begin
        Error('The value is not allowed here.' + NextStepTxt);
    end;

    procedure OnlyLocked(var Argument: Record "Message Argument ori")
    var
        FailedErr: Label 'The request failed.', Locked = true;
        NextStepTxt: Label 'Send it again.', Locked = true;
    begin
        Argument.AddError("Bifrost Error Code ori"::PreconditionFailed, FailedErr, '', '', '', NextStepTxt);
    end;

    procedure UnusedRefusalText()
    var
        StepNextStepTxt: Label 'Send it again.', Locked = true;
        DurationExpectedLbl: Label 'a duration', Locked = true;
        TokenHintTxt: Label 'Data.Records.Get / Data.Records.Set', Locked = true;
        KeysExpectedTok: Label 'id, identityInsert, primaryKey', Locked = true;
        FormatExpectedLbl: Label 'YYYY-MM-DD', Locked = true;
        ObjectExpectedTok: Label 'object', Locked = true;
        TelemetryMsg: Label 'The usage sync failed after the third try.', Locked = true;
    begin
    end;

    procedure ThroughRaise(var Argument: Record "Message Argument ori")
    var
        SummaryErr: Label 'The application was refused.', Locked = true;
    begin
        Argument.RaiseCollectedErrors("Bifrost Error Code ori"::PreconditionFailed, SummaryErr);
    end;

    procedure Allowed(var Argument: Record "Message Argument ori")
    var
        FailedErr: Label 'The request failed.', Locked = true;
        NextStepTxt: Label 'Send it again.', Comment = 'is-IS=Send again.';
    begin
        Argument.AddError("Bifrost Error Code ori"::PreconditionFailed, FailedErr, '', '', '', NextStepTxt);
    end;
}
'@ | Set-Content -LiteralPath (Join-Path $src 'Bad.Codeunit.al') -Encoding UTF8
        @'
codeunit 3 "Clean ori"
{
    procedure AllTranslated(var Argument: Record "Message Argument ori")
    var
        FailedErr: Label 'The request failed.', Comment = 'is-IS=Request failed.';
        NextStepTxt: Label 'Send it again.', Comment = 'is-IS=Send again.';
    begin
        Argument.AddError("Bifrost Error Code ori"::PreconditionFailed, FailedErr, '', '', '', NextStepTxt);
    end;

    procedure StoredReason(var Argument: Record "Message Argument ori")
    var
        ReasonTxt: Label 'The partner cancelled the subscription.', Locked = true;
        Helper: Codeunit "Helper ori";
    begin
        Helper.SaveReason(Argument, ReasonTxt, 'x');
    end;

    procedure SqlText(var Argument: Record "Message Argument ori")
    var
        Helper: Codeunit "Helper ori";
    begin
        Helper.SaveReason(Argument, 'SELECT * FROM c WHERE c.docType = @docType AND c.tenantId = @tenantId', 'x');
    end;

    procedure LockedToken(var Argument: Record "Message Argument ori")
    var
        MessageTypeTok: Label 'Data.Records.Get / Data.Records.Set', Locked = true;
        NextStepTxt: Label 'Send it again.', Comment = 'is-IS=Send again.';
    begin
        Argument.AddError("Bifrost Error Code ori"::PreconditionFailed, NextStepTxt, '', '', MessageTypeTok, '');
    end;

    procedure LockedOutsideTheAnswer(var Argument: Record "Message Argument ori")
    var
        TelemetryMsg: Label 'The usage sync failed after the third try.', Locked = true;
        NextStepTxt: Label 'Send it again.', Comment = 'is-IS=Send again.';
        Helper: Codeunit "Helper ori";
    begin
        Session.LogMessage('0001', TelemetryMsg, Verbosity::Warning, DataClassification::SystemMetadata, TelemetryScope::ExtensionPublisher, 'x', 'y');
        Helper.NoText(Argument);
        Argument.AddError("Bifrost Error Code ori"::PreconditionFailed, NextStepTxt, '', '', '', '');
    end;

    procedure LockedTextInAComment(var Argument: Record "Message Argument ori")
    var
        FailedErr: Label 'The request failed.', Comment = 'is-IS=Request failed.';
    begin
        // Locked = true would be wrong here: 'The thing was not found.' is translated.
        Argument.AddError("Bifrost Error Code ori"::PreconditionFailed, FailedErr, '', '', '', '');
    end;
}
'@ | Set-Content -LiteralPath (Join-Path $src 'Clean.Codeunit.al') -Encoding UTF8

        $allowed = @(
            @{ File = 'Bad.Codeunit.al'; Procedure = 'Allowed'; Reason = 'self-test' },
            @{ File = 'Clean.Codeunit.al'; Procedure = 'AllTranslated'; Reason = 'self-test: not reported, so stale' }
        )
        $found = Find-MixedLanguage $root $allowed
        $failed = $false
        foreach ($name in @('SameCall', 'ThroughHelper', 'ThroughVariable', 'LiteralSentence', 'LiteralThroughHelper', 'OnlyLocked', 'ThroughRaise')) {
            if (-not ($found | Where-Object { $_.StartsWith('Bad.Codeunit.al:') -and $_.Contains("[mixed-language] $name ") })) { Write-Host "SelfTest FAILED: $name was not reported."; $failed = $true }
        }
        if (-not ($found | Where-Object { $_.Contains('GlobalLockedErr') -and $_.Contains('ExpectedTxt') })) { Write-Host 'SelfTest FAILED: ThroughHelper must name the Locked label and the helper label.'; $failed = $true }
        if ($found | Where-Object { $_.Contains('[mixed-language] Allowed ') }) { Write-Host 'SelfTest FAILED: an allow-listed procedure must not be reported.'; $failed = $true }
        foreach ($name in @('AllTranslated', 'StoredReason', 'SqlText', 'SaveReason', 'LockedToken', 'LockedOutsideTheAnswer', 'LockedTextInAComment', 'RespondWithPair', 'NoText', 'Description')) {
            if ($found | Where-Object { $_.Contains("[mixed-language] $name ") }) { Write-Host "SelfTest FAILED: $name must not be reported."; $failed = $true }
        }
        $stale = @($found | Where-Object { $_.Contains('[stale-allow-list]') })
        if ($stale.Count -ne 1 -or -not $stale[0].StartsWith('Clean.Codeunit.al')) { Write-Host "SelfTest FAILED: expected exactly one stale allow-list report for AllTranslated, got: $($stale -join '; ')"; $failed = $true }
        $named = @($found | Where-Object { $_.Contains('[locked-label]') })
        foreach ($name in @('StepNextStepTxt', 'DurationExpectedLbl')) {
            if (-not ($named | Where-Object { $_.Contains(".$name ") })) { Write-Host "SelfTest FAILED: the Locked refusal label $name was not reported."; $failed = $true }
        }
        foreach ($name in @('TokenHintTxt', 'KeysExpectedTok', 'FormatExpectedLbl', 'ObjectExpectedTok', 'TelemetryMsg')) {
            if ($found | Where-Object { $_.Contains(".$name ") }) { Write-Host "SelfTest FAILED: the token $name must not be reported."; $failed = $true }
        }
        $mixed = @($found | Where-Object { $_.Contains('[mixed-language]') })
        if ($mixed.Count -ne 7) { Write-Host "SelfTest FAILED: expected 7 reports, got $($mixed.Count): $($mixed -join '; ')"; $failed = $true }
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

if ($Explain) {
    [void](Find-MixedLanguage $AppFolder $script:AllowList $Explain)
    exit 0
}

$violations = Find-MixedLanguage $AppFolder $script:AllowList
if ($violations.Count -gt 0) {
    Write-Host "::error::A procedure answers a Locked English sentence next to translated text (a label of its own or the generic hint and summary), so the answer mixes two languages at lcid 1039 ($($violations.Count) procedure(s)). Translate the Locked label (remove Locked = true, add an is-IS= comment, run tools/Update-IcelandicXlf.ps1) (#710, #722)."
    $violations | ForEach-Object { Write-Host $_ }
    exit 1
}
Write-Host 'No procedure answers a Locked English sentence.'
