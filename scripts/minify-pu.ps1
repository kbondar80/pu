# scripts/minify-pu.ps1 - generate pu.ps1 from pu-unminified.ps1
#
# PowerShell twin of scripts/minify-pu (sh). PowerShell has no shfmt, so the
# minifier removes blank/comment-only lines, trims whitespace, and packs safe
# statement boundaries up to PU_MINIFY_WIDTH such that every function-level
# anchor survives and blocks stay readable for coding agents to inspect.
# Correctness is enforced with the PowerShell language Parser plus the
# eval/test_real.ps1 behavioral suite (unless --no-tests).

$ErrorActionPreference = 'Stop'

function Usage {
    @'
Usage: scripts/minify-pu.ps1 [--check] [--no-tests]

Generate pu.ps1 from pu-unminified.ps1 by stripping comments and blank lines,
trimming whitespace, and packing safe statement boundaries to a target width.

Options:
  --check     verify pu.ps1 is up to date without rewriting it
  --no-tests  skip eval/test_real.ps1 after syntax checks

Environment:
  PU_MINIFY_WIDTH  preferred packed line width; default: 180
'@
}

$CHECK = 0
$RUN_TESTS = 1
$POS = 0
$ARGS2 = @($args)
while ($POS -lt $ARGS2.Count) {
    switch ($ARGS2[$POS]) {
        '--check' { $CHECK = 1 }
        '--no-tests' { $RUN_TESTS = 0 }
        '-h' { [Console]::Out.WriteLine((Usage -join "`n")); exit 0 }
        '--help' { [Console]::Out.WriteLine((Usage -join "`n")); exit 0 }
        default { [Console]::Error.WriteLine('Usage: scripts/minify-pu.ps1 [--check] [--no-tests]'); exit 2 }
    }
    $POS++
}

$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
$ROOT = Split-Path -Parent $SCRIPT_DIR
$SRC = Join-Path $ROOT 'pu-unminified.ps1'
$OUT = Join-Path $ROOT 'pu.ps1'

if (-not (Test-Path -LiteralPath $SRC -PathType Leaf)) {
    [Console]::Error.WriteLine("Error: missing source file $SRC")
    exit 1
}

$MINIFY_WIDTH = 180
if ($env:PU_MINIFY_WIDTH) {
    $MINIFY_WIDTH = $env:PU_MINIFY_WIDTH
}
$mv = ($MINIFY_WIDTH -as [string])
if (-not ($mv -match '^\d+$')) {
    [Console]::Error.WriteLine('Error: PU_MINIFY_WIDTH must be a positive integer')
    exit 1
}
if ($MINIFY_WIDTH -eq 0) {
    [Console]::Error.WriteLine('Error: PU_MINIFY_WIDTH must be greater than zero')
    exit 1
}

# Words that signal a line must continue (: $x $(if ...) elseif ( -or ...).
$CTL_WORDS = @(
    'if', 'else', 'elseif', 'while', 'do', 'for', 'foreach', 'switch',
    'try', 'catch', 'finally', 'return', 'in', 'param', 'function',
    'filter', 'trap', 'begin', 'process', 'end', 'and', 'or', 'not',
    'eq', 'ne', 'gt', 'ge', 'lt', 'le', 'like', 'notlike', 'match',
    'notmatch', 'contains', 'notcontains', 'startswith', 'endswith',
    'replace', 'split', 'join'
)

# Keep a constructor/opening line separate from a closing here-string marker.
function Test-Anchor {
    param([string]$line)
    return ($line -match '^function\s+Global:\w+(\([^)]*\))?\s*\{?$' -or
            $line -match '^function\s+global:\w+(\([^)]*\))?\s*\{?$' -or
            $line -match '^function\s+\w+(\([^)]*\))?\s*\{?$')
}

function Test-Standalone {
    param([string]$line)
    return ($line -match '^(\$global:|$)(SYSTEM|SP|RP|WP|EP|GP|FP|LP|TD|TF|RF)\s*=' -or
            $line -eq 'TASK=""' -or $line -eq "_load_env")
}

function Test-BlockEnd {
    param([string]$line)
    $t = $line.TrimEnd()
    return ($t -eq '}' -or $t -match '^\}(;|$)')
}

function Test-ContinuationBarrier {
    param([string]$ta)
    $t = $ta
    if ($t.Length -eq 0) { return $false }
    if ($t.EndsWith(' ')) { $t = $t.TrimEnd() }
    if ($t.Length -eq 0) { return $false }
    $c = $t.Chars($t.Length - 1)
    if ($c -eq [char]'`') { return $true }
    if ($c -in @('{', '(', '[', ',', '|', '&', '=', '+', '-', '*', '/', '%', '<', '>', '.', ':')) { return $true }
    if ($c -eq '?' -and $t.EndsWith('?')) { return $true }
    if ($c -eq ';') { return $false }
    if ($c -eq [char]'{' -or $c -eq [char]'(') { return $true }
    if ($c -eq [char]'"' -or $c -eq [char]39) {
        $q = 0
        for ($i = 0; $i -lt $t.Length; $i++) { if ($t[$i] -eq [char]'"') { $q++ } }
        if (($q % 2) -ne 0) { return $true }
        return $false
    }
    if ($c -eq [char]'}') { return $false }
    if ($c -eq [char]')') { return $false }
    if ($c -eq [char]']') { return $false }
    if ($c -match '[0-9A-Za-z_]' -or $c -eq '$' -or $c -eq "'") {
        $w = [regex]::Match($t, '[A-Za-z_$][A-Za-z0-9_$]*$')
        if ($w.Success -and $CTL_WORDS -contains $w.Value) { return $true }
        return $false
    }
    return $true
}

function Test-StartBarrier {
    param([string]$line)
    if ($line.Length -eq 0) { return $true }
    $t = $line.TrimStart()
    if ($t.Length -eq 0) { return $true }
    $c = $t.Chars(0)
    if ($c -in @('}', ')', ']', '.', ',', ';', '|', '{', '`')) { return $true }
    if ($t -match '^(else|elseif|catch|finally|while|until)\b') { return $true }
    if ($t -match '^\(') { return $true }
    return $false
}

# --- minify ---
$lines = [System.IO.File]::ReadAllLines($SRC)
$packed = New-Object System.Collections.Generic.List[string]
$buf = ''
$here = 0
foreach ($line in $lines) {
    $trimmed = $line.Trim()
    if ($here -ne 0) {
        if ($trimmed -match "^('@|`"@)$") { $here = 0 }
        $packed.Add($trimmed)
        continue
    }
    if ($trimmed -eq '') { continue }
    if ($trimmed.StartsWith('#')) { continue }
    if ($trimmed -match "@('|`")\s*$") { $here = 1 }
    $t = $line.Trim()
    if (Test-Anchor $t -or (Test-Standalone $t)) {
        if ($buf -ne '') { $packed.Add($buf); $buf = '' }
        $packed.Add($t)
        continue
    }
    if ($buf -eq '') {
        $buf = $t
    } else {
        $ta = $buf.TrimEnd()
        $tb = $t
        if ((Test-ContinuationBarrier $ta) -or (Test-StartBarrier $tb)) {
            $packed.Add($buf)
            $buf = $t
        } else {
            $sep = '; '
            if (($ta.Length + 2 + $tb.Length) -gt $MINIFY_WIDTH) {
                $packed.Add($buf)
                $buf = $t
            } else {
                $buf = $ta + $sep + $tb
            }
        }
    }
    if ($buf -ne '' -and (Test-BlockEnd $buf)) {
        $packed.Add($buf)
        $buf = ''
    }
}
if ($buf -ne '') { $packed.Add($buf) }

$header = '# generated from pu-unminified.ps1; edit that file, then run scripts/minify-pu'
$all = New-Object System.Collections.Generic.List[string]
$all.Add($header)
foreach ($l in $packed) { $all.Add($l) }
$finalText = ($all -join "`n") + "`n"

$tmp = Join-Path $env:TEMP ('.pu.ps1.' + [System.IO.Path]::GetRandomFileName())
[System.IO.File]::WriteAllText($tmp, $finalText, (New-Object System.Text.UTF8Encoding($false)))

# Syntax check with the real parser.
$errs = $null
$toks = $null
[System.Management.Automation.Language.Parser]::ParseFile($tmp, [ref]$toks, [ref]$errs) | Out-Null
if ($errs.Count -gt 0) {
    [Console]::Error.WriteLine("Error: generated pu.ps1 failed PowerShell syntax check:")
    foreach ($e in $errs) { [Console]::Error.WriteLine('  ' + $e.Message) }
    Remove-Item -LiteralPath $tmp -Force
    exit 1
}

if ($CHECK -eq 1) {
    if (-not (Test-Path -LiteralPath $OUT -PathType Leaf)) {
        [Console]::Error.WriteLine('Error: pu.ps1 does not exist; run scripts/minify-pu.ps1')
        Remove-Item -LiteralPath $tmp -Force
        exit 1
    }
    $cur = [System.IO.File]::ReadAllText($OUT)
    if ($cur -ne $finalText) {
        [Console]::Error.WriteLine('Error: pu.ps1 is stale; run scripts/minify-pu.ps1')
        Remove-Item -LiteralPath $tmp -Force
        exit 1
    }
    [Console]::Out.WriteLine('pu.ps1 is up to date')
    Remove-Item -LiteralPath $tmp -Force
    if ($RUN_TESTS -eq 1 -and (Test-Path -LiteralPath (Join-Path $ROOT 'eval\test_real.ps1') -PathType Leaf)) {
        [Console]::Out.WriteLine('Running behavioral tests against pu.ps1...')
        $env:AGENT = $OUT
        & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $ROOT 'eval\test_real.ps1')
        exit $LASTEXITCODE
    }
    exit 0
}

Move-Item -LiteralPath $tmp -Destination $OUT -Force
[Console]::Out.WriteLine(('Generated pu.ps1 (' + (Get-Item -LiteralPath $OUT).Length + ' bytes, ' + (($finalText -split "`n").Count - 1) + ' lines)'))

if ($RUN_TESTS -eq 1 -and (Test-Path -LiteralPath (Join-Path $ROOT 'eval\test_real.ps1') -PathType Leaf)) {
    [Console]::Out.WriteLine('Running behavioral tests against pu.ps1...')
    $env:AGENT = $OUT
    & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $ROOT 'eval\test_real.ps1')
    exit $LASTEXITCODE
}
exit 0