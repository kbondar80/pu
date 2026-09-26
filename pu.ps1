# generated from pu-unminified.ps1; edit that file, then run scripts/minify-pu
try { [Console]::TreatControlCAsInput = $false } catch { }; $global:ESC = [char]27; $global:U_PLACEHOLDER = [char]0x23FA; $global:U_ELLIPSIS = [char]0x2026
$global:U_MIDDOT = [char]0x00B7; $global:_STATE = 'idle'; $global:_CHILD = 0; $global:SPIN_PID = ''; $global:SPIN_MSG = ''; $global:PROMPT_LAST_INPUT = ''; $global:UPIN = ''
$global:PUSRC = ''
function Global:CleanKey([string]$k) {
if ($null -eq $k) { return '' }; $k = $k -replace '^[\s]+', ''; $k = $k -replace '[\s]+$', ''; $k = $k -replace '^export[\s]*', ''; $k = $k -replace '^OPENAI_API_KEY=', ''
$k = $k -replace '^ANTHROPIC_API_KEY=', ''; $k = $k -replace '^"', ''
$k = $k -replace '"$', ''
$k = $k -replace "^'", ''; $k = $k -replace "'$", ''; $k = $k -replace '\s', ''; return $k
}
function Global:Pu-HomeDir {
if ($env:HOME) { return $env:HOME }; if ($env:USERPROFILE) { return $env:USERPROFILE }; $h = $HOME; if ($h) { return $h }
return (Join-Path $env:SystemDrive ('Users\' + $env:USERNAME))
}
function Global:_load_env {
$hf = Join-Path (Pu-HomeDir) '.pu.env'; if (-not (Test-Path -LiteralPath $hf -PathType Leaf)) { return }; try { $lines = [System.IO.File]::ReadAllLines($hf) } catch { return }
foreach ($raw in $lines) {
if (-not $raw) { continue }; $eq = $raw.IndexOf('='); if ($eq -lt 0) { continue }; $k = $raw.Substring(0, $eq); $v = $raw.Substring($eq + 1); $k = $k -replace '^[\s]+', ''
$k = $k -replace '[\s]+$', ''; $k = $k -replace '^export[\s]*', ''; $v = CleanKey $v; switch ($k) {
'OPENAI_API_KEY'          { if (-not $env:OPENAI_API_KEY) { $env:OPENAI_API_KEY = $v } }
'ANTHROPIC_API_KEY'       { if (-not $env:ANTHROPIC_API_KEY) { $env:ANTHROPIC_API_KEY = $v } }
'AGENT_PROVIDER'          { if (-not $env:AGENT_PROVIDER) { $env:AGENT_PROVIDER = $v } }; 'AGENT_MODEL'             { if (-not $env:AGENT_MODEL) { $env:AGENT_MODEL = $v } }
'AGENT_EFFORT'            { if (-not $env:AGENT_EFFORT) { $env:AGENT_EFFORT = $v } }
'AGENT_REASONING_SUMMARY' { if (-not $env:AGENT_REASONING_SUMMARY) { $env:AGENT_REASONING_SUMMARY = $v } }
'AGENT_ENDPOINT'          { if (-not $env:AGENT_ENDPOINT) { $env:AGENT_ENDPOINT = $v } }
}
}
}
_load_env; if ($env:OPENAI_API_KEY) { $env:OPENAI_API_KEY = CleanKey $env:OPENAI_API_KEY }; if ($env:ANTHROPIC_API_KEY) { $env:ANTHROPIC_API_KEY = CleanKey $env:ANTHROPIC_API_KEY }
if ($env:AGENT_PROVIDER) {
$global:PROVIDER = $env:AGENT_PROVIDER
} else {
$global:PROVIDER = 'anthropic'; if ($env:AGENT_MODEL) {
if ($env:AGENT_MODEL -match '^(gpt-|o1|o3|o4)') { $global:PROVIDER = 'openai' }
elseif ($env:AGENT_MODEL -like 'claude-*') { $global:PROVIDER = 'anthropic' }
} elseif ($env:OPENAI_API_KEY -and -not $env:ANTHROPIC_API_KEY) {
$global:PROVIDER = 'openai'
}
}
switch ($global:PROVIDER) {
'openai' { $global:MODEL = $(if ($env:AGENT_MODEL) { $env:AGENT_MODEL } else { 'gpt-5.5' }) }
default  { $global:MODEL = $(if ($env:AGENT_MODEL) { $env:AGENT_MODEL } else { 'claude-opus-4-7' }) }
}
$global:MAX_STEPS = $(if ($env:AGENT_MAX_STEPS) { $env:AGENT_MAX_STEPS } else { 100 }); $global:MAX_TOKENS = $(if ($env:AGENT_MAX_TOKENS) { $env:AGENT_MAX_TOKENS } else { 4096 })
$global:AGENT_RESERVE = $(if ($env:AGENT_RESERVE) { $env:AGENT_RESERVE } else { 16000 })
$global:AGENT_KEEP_RECENT = $(if ($env:AGENT_KEEP_RECENT) { $env:AGENT_KEEP_RECENT } else { 80000 })
$global:AGENT_TOOL_TRUNC = $(if ($env:AGENT_TOOL_TRUNC) { $env:AGENT_TOOL_TRUNC } else { 100000 })
$global:AGENT_READ_MAX = $(if ($env:AGENT_READ_MAX) { $env:AGENT_READ_MAX } else { 1000000 })
$global:AGENT_LOG_TRUNC = $(if ($env:AGENT_LOG_TRUNC) { $env:AGENT_LOG_TRUNC } else { 20000 }); $global:LOG = $(if ($env:AGENT_LOG) { $env:AGENT_LOG } else { '.pu-events.jsonl' })
$global:HISTORY = $(if ($env:AGENT_HISTORY) { $env:AGENT_HISTORY } else { '.pu-history.json' }); $global:CONFIRM = $(if ($env:AGENT_CONFIRM) { $env:AGENT_CONFIRM } else { 0 })
$global:CTX_LIMIT = $(if ($env:AGENT_CONTEXT_LIMIT) { $env:AGENT_CONTEXT_LIMIT } else { 400000 }); $global:VERBOSE = $(if ($env:AGENT_VERBOSE) { $env:AGENT_VERBOSE } else { 1 })
$global:THINKING = $(if ($env:AGENT_THINKING) { $env:AGENT_THINKING } else { '' })
$global:EFFORT = $(if ($env:AGENT_EFFORT) { $env:AGENT_EFFORT } elseif ($env:AGENT_THINKING) { $env:AGENT_THINKING } else { 'medium' })
$global:REASONING_SUMMARY = $(if ($env:AGENT_REASONING_SUMMARY) { $env:AGENT_REASONING_SUMMARY } else { 'auto' }); $global:EFFORT_OK = 0
if ("$global:PROVIDER`:$global:MODEL" -like 'openai:gpt-5.5*') { $global:EFFORT_OK = 1 }
elseif ("$global:PROVIDER`:$global:MODEL" -like 'anthropic:claude-opus-4-7*') {
if (-not $env:AGENT_CONTEXT_LIMIT) { $global:CTX_LIMIT = 272000 }; $global:EFFORT_OK = 1
}
elseif ("$global:PROVIDER`:$global:MODEL" -like 'anthropic:claude-opus-4-6*' -or
"$global:PROVIDER`:$global:MODEL" -like 'anthropic:claude-sonnet-4-6*' -or
"$global:PROVIDER`:$global:MODEL" -like 'anthropic:claude-opus-4-5*') { $global:EFFORT_OK = 1 }; $global:PIPE = 0; $global:COST = 0; $global:INTERACTIVE = 0; $global:MSGS = ''
$global:TOKEN_IN = 0; $global:TOKEN_OUT = 0; $global:COST_USD = 0; $global:TASK = ''; $global:PU_API_RC = -1; $global:PWDSTR = ''
if (-not $global:PWDSTR) { $global:PWDSTR = (Get-Location).Path }; $global:TODAYSTR = (Get-Date -Format 'yyyy-MM-dd'); $global:PUSRC = $MyInvocation.MyCommand.Path
function Global:Pu-ErrWrite([string]$s) {
if ($s) { [Console]::Error.Write($s) }
}
function Global:info([string]$m) {
if ($global:PIPE -eq 0) { Pu-ErrWrite ("`r$ESC[K$ESC[36m[pu]$ESC[0m " + $m + "`n") }
}
function Global:err([string]$m) {
Pu-ErrWrite ("`r$ESC[K$ESC[31m[!] $m$ESC[0m`n")
}
function Global:dbg([string]$m) {
if ($global:VERBOSE -eq 1) { Pu-ErrWrite ("`r$ESC[K[v] $m`n") }
}
function Global:_think([string]$m) {
if ($global:PIPE -eq 0 -and $m) { Pu-ErrWrite ("`r$ESC[K$ESC[2mthinking:$ESC[0m " + $m + "`n") }
}
function Global:_say([string]$m) {
if ($global:PIPE -eq 0) { Pu-ErrWrite ("`r$ESC[K" + $m + "`n") }
}
function Global:_tool([string]$a, [string]$b) {
if ($global:PIPE -eq 0) {
Pu-ErrWrite (("`r$ESC[K$ESC[2m{0}$ESC[0m $ESC[36m{1}$ESC[0m $ESC[2m{2}$ESC[0m`n") -f $global:U_PLACEHOLDER, $a, $b)
}
}
function Global:_p([string]$p) {
$pwdv = $global:PWDSTR; if ($p.StartsWith($pwdv + '\') -or $p.StartsWith($pwdv + '/')) { return $p.Substring($pwdv.Length + 1) }; $h = Pu-HomeDir
if ($h -and ($p.StartsWith($h + '\') -or $p.StartsWith($h + '/'))) { return '~' + $p.Substring($h.Length) }; return $p
}
function Global:_tool_out([string]$s) {
if ($global:PIPE -eq 1) { return }; if (-not $s) { return }; if ($s -match '^(Error:|\[exit:|\[denied)') { return }; $lines = $s -split "`n"; $n = $lines.Count
$k = [Math]::Min(10, $n); for ($i = 0; $i -lt $k; $i++) {
Pu-ErrWrite (("  $ESC[2m{0}$ESC[0m`n") -f $lines[$i])
}
if ($n -gt 10) {
Pu-ErrWrite (("  $ESC[2m{0} ({1} more lines)$ESC[0m`n") -f $global:U_ELLIPSIS, ($n - 10))
}
}
function Global:Pu-SayFinal([string]$s) {
[Console]::Out.WriteLine($s)
}
function Global:_num([string]$name, [string]$val) {
if (-not ($val -match '^\d+$')) {
err "$name must be a non-negative integer"; exit 1
}
}
foreach ($nv in @(
@('MAX_STEPS', ($global:MAX_STEPS -as [string])),
@('MAX_TOKENS', ($global:MAX_TOKENS -as [string])),
@('CTX_LIMIT', ($global:CTX_LIMIT -as [string])),
@('AGENT_RESERVE', ($global:AGENT_RESERVE -as [string])),
@('AGENT_KEEP_RECENT', ($global:AGENT_KEEP_RECENT -as [string])),
@('AGENT_TOOL_TRUNC', ($global:AGENT_TOOL_TRUNC -as [string])),
@('AGENT_READ_MAX', ($global:AGENT_READ_MAX -as [string])),
@('AGENT_LOG_TRUNC', ($global:AGENT_LOG_TRUNC -as [string]))
)) { _num $nv[0] $nv[1] }; if (-not ($global:CTX_LIMIT -gt $global:AGENT_RESERVE)) {
err 'AGENT_CONTEXT_LIMIT must be greater than AGENT_RESERVE'; exit 1
}
$global:SYSTEM = $(if ($env:AGENT_SYSTEM) { $env:AGENT_SYSTEM } else {
("You are an expert coding assistant. You can read, write, edit, grep, find, ls, and run powershell.`n" +
"Tools: read(path,offset,limit); powershell(command); edit(path,oldText,newText); write(path,content); grep(pattern,path); find(path,name); ls(path).`n" +
"Guidelines: prefer grep/find/ls over powershell for exploration; working directory is $global:PWDSTR, do not cd in powershell commands; combine related grep searches with alternation.`n" +
"Use read instead of cat/Get-Content; write only for new files or complete rewrites; edit only with exact unique oldText, reading surrounding lines after failures and never retrying the same failed oldText.`n" +
"Before tool calls briefly say what you are checking/changing and why; be concise; show file paths clearly. Do not reveal hidden chain-of-thought; use public rationale summaries only.`n" +
"Current date: $global:TODAYSTR`n" +
"Current working directory: $global:PWDSTR`n" +
"Your source code is at $global:PUSRC. Use read to inspect it if asked about your capabilities/configuration.")
}); $global:SP = '{"type":"object","properties":{"command":{"type":"string","description":"Shell command"}},"required":["command"]}'
$global:RP = '{"type":"object","properties":{"path":{"type":"string"},"offset":{"type":"integer","description":"Start line"},"limit":{"type":"integer","description":"Max lines"}},"required":["path"]}'
$global:WP = '{"type":"object","properties":{"path":{"type":"string"},"content":{"type":"string"}},"required":["path","content"]}'
$global:EP = '{"type":"object","properties":{"path":{"type":"string"},"oldText":{"type":"string","description":"Exact text to find"},"newText":{"type":"string","description":"Replacement"}},"required":["path","oldText","newText"]}'
$global:GP = '{"type":"object","properties":{"pattern":{"type":"string"},"path":{"type":"string"}},"required":["pattern"]}'
$global:FP = '{"type":"object","properties":{"path":{"type":"string"},"name":{"type":"string","description":"Glob"}},"required":["path"]}'
$global:LP = '{"type":"object","properties":{"path":{"type":"string"}},"required":["path"]}'
$global:TD = ('{"name":"powershell","description":"Run a powershell command","input_schema":' + $global:SP + '},{"name":"read","description":"Read file contents","input_schema":' + $global:RP + '},{"name":"write","description":"Write content to file, creates dirs","input_schema":' + $global:WP + '},{"name":"edit","description":"Edit file with exact text replacement","input_schema":' + $global:EP + '},{"name":"grep","description":"Search for pattern in files","input_schema":' + $global:GP + '},{"name":"find","description":"Find files by name glob","input_schema":' + $global:FP + '},{"name":"ls","description":"List directory","input_schema":' + $global:LP + '}')
$global:TF = ('{"type":"function","function":{"name":"powershell","description":"Run a powershell command","parameters":' + $global:SP + '}},{"type":"function","function":{"name":"read","description":"Read file contents","parameters":' + $global:RP + '}},{"type":"function","function":{"name":"write","description":"Write content to file","parameters":' + $global:WP + '}},{"type":"function","function":{"name":"edit","description":"Edit file with exact text replacement","parameters":' + $global:EP + '}},{"type":"function","function":{"name":"grep","description":"Search for pattern","parameters":' + $global:GP + '}},{"type":"function","function":{"name":"find","description":"Find files","parameters":' + $global:FP + '}},{"type":"function","function":{"name":"ls","description":"List directory","parameters":' + $global:LP + '}}')
$global:RF = ('{"type":"function","name":"powershell","description":"Run a powershell command","parameters":' + $global:SP + ',"strict":false},{"type":"function","name":"read","description":"Read file contents","parameters":' + $global:RP + ',"strict":false},{"type":"function","name":"write","description":"Write content to file","parameters":' + $global:WP + ',"strict":false},{"type":"function","name":"edit","description":"Edit file with exact replacement","parameters":' + $global:EP + ',"strict":false},{"type":"function","name":"grep","description":"Search for pattern","parameters":' + $global:GP + ',"strict":false},{"type":"function","name":"find","description":"Find files","parameters":' + $global:FP + ',"strict":false},{"type":"function","name":"ls","description":"List directory","parameters":' + $global:LP + ',"strict":false}')
function Global:think_param {
$pm = "$global:PROVIDER`:$global:MODEL"; if ($pm -like 'anthropic:claude-opus-4-7*' -or
$pm -like 'anthropic:claude-opus-4-6*' -or
$pm -like 'anthropic:claude-sonnet-4-6*' -or
$pm -like 'anthropic:claude-opus-4-5*') {
return ',"effort":"' + $global:EFFORT + '","thinking":{"type":"adaptive"}'
}
switch ($global:THINKING) {
'low'    { return ',"thinking":{"type":"enabled","budget_tokens":1024}' }; 'medium' { return ',"thinking":{"type":"enabled","budget_tokens":4096}' }
'high'   { return ',"thinking":{"type":"enabled","budget_tokens":10000}' }; 'xhigh'  { return ',"thinking":{"type":"enabled","budget_tokens":10000}' }
'max'    { return ',"thinking":{"type":"enabled","budget_tokens":10000}' }; default  { return '' }
}
}
function Global:JsonEscape([string]$s) {
if ($null -eq $s) { return '' }; $sb = New-Object System.Text.StringBuilder; for ($i = 0; $i -lt $s.Length; $i++) {
$c = $s[$i]; $n = [int][char]$c; if ($n -lt 32) {
if ($n -eq 9) { [void]$sb.Append('\t') }
elseif ($n -eq 10) { [void]$sb.Append('\n') }
elseif ($n -eq 13) { [void]$sb.Append('\r') }; continue
}
if ($c -eq '\') { [void]$sb.Append('\\') }
elseif ($c -eq '"') { [void]$sb.Append('\"') }
else { [void]$sb.Append($c) }
}
return $sb.ToString()
}
function Global:Unescape-JsonString([string]$s, [int]$open) {
$sb = New-Object System.Text.StringBuilder; $i = $open + 1
while ($i -lt $s.Length) {
$c = $s[$i]; if ($c -eq '\' -and ($i + 1) -lt $s.Length) {
$n = $s[$i + 1]; if ($n -eq 'u' -and ($i + 6) -le $s.Length) {
$hex = $s.Substring($i + 2, 4); if ($hex -match '^[0-9A-Fa-f]{4}$') {
[int]$cp = [Convert]::ToInt32($hex, 16); if ($cp -ge 0xD800 -and $cp -le 0xDBFF -and ($i + 11) -lt $s.Length -and $s[$i + 6] -eq '\' -and $s[$i + 7] -eq 'u') {
$hex2 = $s.Substring($i + 8, 4); if ($hex2 -match '^[0-9A-Fa-f]{4}$') {
[int]$cp2 = [Convert]::ToInt32($hex2, 16); if ($cp2 -ge 0xDC00 -and $cp2 -le 0xDFFF) {
[int]$cpf = 0x10000 + (($cp - 0xD800) * 0x400) + ($cp2 - 0xDC00); [void]$sb.Append([char]::ConvertFromUtf32($cpf)); $i += 12; continue
}
}
}
[void]$sb.Append([char]$cp); $i += 6; continue
}
}
if ($n -eq 'n') { [void]$sb.Append([char]10); $i += 2; continue }
elseif ($n -eq 't') { [void]$sb.Append([char]9); $i += 2; continue }
elseif ($n -eq 'r') { [void]$sb.Append([char]13); $i += 2; continue }
elseif ($n -eq '"') { [void]$sb.Append('"'); $i += 2; continue }
elseif ($n -eq '\') { [void]$sb.Append('\'); $i += 2; continue }
elseif ($n -eq '/') { [void]$sb.Append('/'); $i += 2; continue }
else { [void]$sb.Append($c); [void]$sb.Append($n); $i += 2; continue }
}
if ($c -eq '"') { return $sb.ToString() }; [void]$sb.Append($c); $i++
}
return $sb.ToString()
}
function Global:jp([string]$s, [string]$key) {
if ($null -eq $s) { return '' }; $tgt = '"' + $key + '":'; $n = $s.IndexOf($tgt); if ($n -lt 0) { return '' }; $pos = $n + $tgt.Length
while ($pos -lt $s.Length -and ([char]::IsWhiteSpace($s[$pos]) -or $s[$pos] -eq [char]9)) { $pos++ }; if ($pos -ge $s.Length) { return '' }; $c = $s[$pos]
if ($c -eq '"') { return (Unescape-JsonString $s $pos) }; if ($c -eq '[' -or $c -eq '{') {
$o = Get-Balanced-Json $s $pos; if ($null -eq $o) { return '' }; return $o
}
$end = $pos
while ($end -lt $s.Length -and $s[$end] -ne ',' -and $s[$end] -ne '}' -and $s[$end] -ne ']') { $end++ }; return $s.Substring($pos, $end - $pos)
}
function Global:jb([string]$s, [string]$key) {
if ($null -eq $s) { return '' }; $tgt = '"' + $key + '"'; $n = $s.IndexOf($tgt); if ($n -lt 0) { return '' }; $i = $n - 1
while ($i -ge 0 -and $s[$i] -ne '{') { $i-- }; if ($i -lt 0) { return '' }; $o = Get-Balanced-Json $s $i; if ($null -eq $o) { return '' }; return $o
}
function Global:Get-Balanced-Json([string]$s, [int]$start) {
if ($start -ge $s.Length) { return $null }; $c0 = $s[$start]; if ($c0 -ne '{' -and $c0 -ne '[') { return $null }; $d = 0; $q = $false; $e = $false; $o = ''
for ($j = $start; $j -lt $s.Length; $j++) {
$c = $s[$j]; $o = $o + $c; if ($e) { $e = $false; continue }; if ($c -eq '\' -and $q) { $e = $true; continue }; if ($c -eq '"') { $q = -not $q; continue }; if ($q) { continue }
if ($c -eq '{' -or $c -eq '[') { $d++ }
elseif ($c -eq '}' -or $c -eq ']') {
$d--
if ($d -eq 0) { return $o }
}
}
return $null
}
function Global:Get-Matched-JsonObjects([string]$s, [string]$pattern) {
$out = New-Object System.Collections.Generic.List[string]; if ($null -eq $s) { return $out }; $d = 0; $q = $false; $e = $false; $start = -1; for ($i = 0; $i -lt $s.Length; $i++) {
$c = $s[$i]; if ($e) { $e = $false; continue }; if ($c -eq '\' -and $q) { $e = $true; continue }; if ($c -eq '"') { $q = -not $q; continue }; if ($q) { continue }
if ($c -eq '{') {
if ($d -eq 0) { $start = $i }; $d++
} elseif ($c -eq '}') {
$d--
if ($d -eq 0 -and $start -ge 0) {
$obj = $s.Substring($start, $i - $start + 1); if ($obj -match $pattern) { [void]$out.Add($obj) }; $start = -1
}
}
}
return $out
}
function Global:oa_items([string]$s) {
return (Get-Matched-JsonObjects $s '"type"[ ]*:[ ]*"(reasoning|function_call)"')
}
function Global:each_summary_text([string]$s) {
return (Get-Matched-JsonObjects $s '"type"[ ]*:[ ]*"summary_text"')
}
function Global:each_tool_use([string]$s, [string]$marker) {
$out = New-Object System.Collections.Generic.List[string]; if ($null -eq $s) { return $out }; $p = $s.IndexOf($marker)
while ($p -ge 0) {
$i = $p - 1
while ($i -ge 0 -and $s[$i] -ne '{') { $i-- }; if ($i -lt 0) { break }; $o = Get-Balanced-Json $s $i; if ($null -eq $o) { break }; [void]$out.Add($o)
$p = $s.IndexOf($marker, $i + $o.Length)
}
return $out
}
function Global:reasoning_summaries([string]$s) {
$parts = @(); $items = each_summary_text $s; foreach ($o in $items) {
$t = jp $o 'text'; if ($t) { $parts += $t }
}
return ($parts -join "`n")
}
function Global:Parse-Json([string]$s) {
try { return ($s | ConvertFrom-Json) } catch { return $null }
}
function Global:_trunc_text([int]$Mtext, [string]$text) {
$lines = @($text -split "`n"); $nr = 0; $total = 0; $lineLen = New-Object System.Collections.Generic.List[int]; foreach ($l in $lines) {
if ($nr -eq 0 -and $l -eq '' -and $text -eq '') { break }; $nr++
$ll = $l.Length; [void]$lineLen.Add($ll); $total += $ll + 1
}
if ($nr -eq 0) { return '' }; if ($total -le $Mtext) {
$out = New-Object System.Text.StringBuilder; for ($i = 0; $i -lt $nr; $i++) {
$l = $lines[$i]; if ($i -gt 0) { [void]$out.Append("`n") }; [void]$out.Append($l)
}
return $out.ToString()
}
if ($nr -gt 40) {
$marker = '...[' + ($nr - 40) + ' lines truncated]...'; $n = 40
} else {
$marker = '...[long lines truncated]...'; $n = $nr
}
$reserve = $marker.Length + $n + 8; $per = [int][Math]::Floor(($Mtext - $reserve) / $n); if ($per -lt 30) { $per = 30 }; $clip = {
param($s, $lim); if ($s.Length -le $lim) { return $s }; return '...[line truncated: ' + $s.Length + ' chars]...'
}
$out = New-Object System.Text.StringBuilder; if ($nr -gt 40) {
for ($i = 0; $i -lt 30; $i++) {
$l = (& $clip $lines[$i] $per); [void]$out.Append($l); [void]$out.Append("`n")
}
[void]$out.Append($marker); [void]$out.Append("`n"); for ($i = $nr - 9; $i -lt $nr; $i++) {
$l = (& $clip $lines[$i] $per); [void]$out.Append($l); [void]$out.Append("`n")
}
return $out.ToString()
} else {
for ($i = 0; $i -lt $nr; $i++) {
$l = (& $clip $lines[$i] $per); [void]$out.Append($l); [void]$out.Append("`n")
}
[void]$out.Append($marker); return $out.ToString()
}
}
function Global:Invoke-Pu([string]$url, [hashtable]$headers, [string]$method, [string]$body) {
$global:PU_API_RC = -1; try {
$req = [System.Net.HttpWebRequest]::Create($url); $req.Method = $method; $req.ContentType = 'application/json'; $req.Timeout = 120000; $req.ReadWriteTimeout = 120000
foreach ($hk in $headers.Keys) { $req.Headers[$hk] = $headers[$hk] }; if ($body) {
$bytes = [System.Text.Encoding]::UTF8.GetBytes($body); $req.ContentLength = $bytes.Length; $st = $req.GetRequestStream(); $st.Write($bytes, 0, $bytes.Length); $st.Close()
} else {
$req.ContentLength = 0
}
$resp = $req.GetResponse(); $sr = New-Object System.IO.StreamReader($resp.GetResponseStream()); $content = $sr.ReadToEnd(); $sr.Close(); $resp.Close(); $global:PU_API_RC = 0
return $content
} catch {
$we = $_.Exception; $hr = $null; if ($we -is [System.Net.WebException]) { $hr = $we.Response }; if ($null -ne $hr) {
$sr = New-Object System.IO.StreamReader($hr.GetResponseStream()); $content = $sr.ReadToEnd(); $sr.Close(); $hr.Close(); $global:PU_API_RC = 0; return $content
}
$global:PU_API_RC = 1; return ($_.Exception.Message)
}
}
function Global:call_api([string]$m) {
$sys_esc = JsonEscape $SYSTEM; [int]$mt = [int]$MAX_TOKENS; $eb = $THINKING; $ep = ''; if ($env:AGENT_ENDPOINT) { $ep = $env:AGENT_ENDPOINT.TrimEnd('/') }; $tp = think_param
if ($EFFORT_OK -eq 1) { if (-not $eb) { $eb = $EFFORT } }; switch ($eb) {
'minimal' { if ($mt -lt 4096) { $mt = 4096 } }; 'low'     { if ($mt -lt 4096) { $mt = 4096 } }; 'medium'  { if ($mt -lt 8192) { $mt = 8192 } }
'high'    { if ($mt -lt 16000) { $mt = 16000 } }; 'xhigh'   { if ($mt -lt 32000) { $mt = 32000 } }; 'max'     { if ($mt -lt 32000) { $mt = 32000 } }
}
$hd = @{}; if ($PROVIDER -eq 'anthropic') {
$hd['x-api-key'] = $env:ANTHROPIC_API_KEY; $hd['anthropic-version'] = '2023-06-01'
$body = '{"model":"' + $MODEL + '","max_tokens":' + $mt + ',"system":"' + $sys_esc + '","tools":[' + $TD + '],"messages":' + $m + $tp + '}'
$url = $(if ($ep) { $ep } else { 'https://api.anthropic.com' }) + '/v1/messages'; return (Invoke-Pu $url $hd 'POST' $body)
} else {
$hd['Authorization'] = 'Bearer ' + $env:OPENAI_API_KEY; $rs = ''; switch ($REASONING_SUMMARY) {
''            { $rs = '' }; 'none'        { $rs = '' }; 'off'         { $rs = '' }; '0'           { $rs = '' }; 'false'       { $rs = '' }
'concise'     { $rs = ',"summary":"concise"' }; 'detailed'    { $rs = ',"summary":"detailed"' }; 'auto'        { $rs = ',"summary":"auto"' }
default       { $rs = ',"summary":"auto"' }
}
$rp = ''; if ($EFFORT_OK -eq 1) {
switch ($EFFORT) {
''    { }; 'none' { }; default { $rp = ',"reasoning":{"effort":"' + $EFFORT + '"' + $rs + '}' }
}
}
$body = '{"model":"' + $MODEL + '","max_output_tokens":' + $mt + $rp + ',"instructions":"' + $sys_esc + '","input":' + $m + ',"tools":[' + $RF + ']}'
$url = $(if ($ep) { $ep } else { 'https://api.openai.com' }) + '/v1/responses'; return (Invoke-Pu $url $hd 'POST' $body)
}
}
function Global:parse_response([string]$resp) {
$global:TY = ''; $global:TN = ''; $global:TI = ''; $global:TX = ''; $global:TS = ''; $global:CB = ''; $global:TINP = ''; $global:TC = ''; if ($PROVIDER -eq 'anthropic') {
$tu = jb $resp 'tool_use'; if ($tu) {
$global:TY = 'T'; $global:TN = jp $tu 'name'; $global:TI = jp $tu 'id'; $global:TINP = jp $tu 'input'; $tt = jb $resp 'text'; $global:TX = jp $tt 'text'
$global:CB = jp $resp 'content'
} else {
$global:TY = 'X'; $tt = jb $resp 'text'; $global:TX = jp $tt 'text'
}
} else {
$global:TC = jp $resp 'output'; $global:TS = reasoning_summaries $resp; $call = jb $global:TC 'function_call'; if ($call) {
$global:TY = 'T'; $global:TI = jp $call 'call_id'; if (-not $global:TI) { $global:TI = jp $call 'id' }; $global:TN = jp $call 'name'; $global:TINP = jp $call 'arguments'
$tt = jb $resp 'output_text'; $global:TX = jp $tt 'text'; if (-not $global:TX) { $global:TX = jp $resp 'output_text' }
} else {
$global:TY = 'X'; $tt = jb $resp 'output_text'; $global:TX = jp $tt 'text'; if (-not $global:TX) { $global:TX = jp $resp 'output_text' }; $global:TC = ''
}
}
}
function Global:SleepSec([double]$n) { Start-Sleep -Seconds $n }; function Global:Pu-Save-Attrs([string]$fp) {
try {
if (-not (Test-Path -LiteralPath $fp -PathType Leaf)) { return $false }
return (([System.IO.File]::GetAttributes($fp) -band [System.IO.FileAttributes]::ReadOnly) -eq [System.IO.FileAttributes]::ReadOnly)
} catch { return $false }
}
function Global:Pu-Clear-Attrs([string]$fp) {
try {
$a = [System.IO.File]::GetAttributes($fp); [System.IO.File]::SetAttributes($fp, ($a -band (-bnot [System.IO.FileAttributes]::ReadOnly)))
} catch { }
}
function Global:Pu-Restore-Attrs([string]$fp, [bool]$ro) {
if (-not $ro) { return }; try {
$a = [System.IO.File]::GetAttributes($fp); [System.IO.File]::SetAttributes($fp, ($a -bor [System.IO.FileAttributes]::ReadOnly))
} catch { }
}
function Global:run_tool([string]$tool_name, [string]$inp) {
if ($CONFIRM -eq 1) {
if (-not (_stdin_is_console)) { return '[denied: no tty]' }; Pu-ErrWrite ('[?] ' + $tool_name + ': ' + $inp.Substring(0, [Math]::Min(80, $inp.Length)) + ' [y/N] ')
$yn = _read_line; if ($yn -ne 'y' -and $yn -ne 'Y') { return '[denied]' }
}
$out = ''; $rc = 0; $in = Parse-Json $inp; switch ($tool_name) {
'powershell' {
$cmd = ''; if ($in) { $cmd = [string]$in.command }; _tool 'powershell' $cmd; $out = Pu-RunShell $cmd; $rc = $LASTEXITCODE; if ($rc -ne 0) { $out = $out + "`n[exit:$rc]" }
}
'bash' {
$cmd = ''; if ($in) { $cmd = [string]$in.command }; _tool 'powershell' $cmd; $out = Pu-RunShell $cmd; $rc = $LASTEXITCODE; if ($rc -ne 0) { $out = $out + "`n[exit:$rc]" }
}
'read' {
$fp = ''; $off = ''; $lim = ''; if ($in) {
$fp = [string]$in.path; $off = [string]$in.offset; $lim = [string]$in.limit
}
if ($fp -match '^-') { $fp = './' + $fp }; $fp = Pu-ResolvePath $fp; if ($off -eq '0') { $off = '1' }; $rd_disp = _p $fp
if ($off) { $rd_disp = $rd_disp + ':' + $off + $(if ($lim) { '-' + ([int]$off + [int]$lim - 1) } else { '' }) }; _tool 'read' $rd_disp
if (Test-Path -LiteralPath $fp -PathType Leaf) {
if ($off -and $off -notmatch '^\d+$') { $out = 'Error: offset must be a positive integer'; $rc = 1 }
elseif ($lim -and $lim -notmatch '^\d+$') { $out = 'Error: limit must be a positive integer'; $rc = 1 }
elseif ($lim -eq '0') { $out = ''; $rc = 0 }
else {
$sz = (Get-Item -LiteralPath $fp).Length; if (-not $off -and -not $lim -and $sz -gt $AGENT_READ_MAX) {
$out = "Error: $fp is $sz bytes " + [char]0x2014 + " pass offset/limit to read a range"; $rc = 1
} elseif ($off -and $lim) {
$out = Pu-ReadRange $fp ([int]$off) ([int]$lim)
} elseif ($off) {
$out = Pu-ReadRange $fp ([int]$off) ([int]::MaxValue)
} elseif ($lim) {
$out = Pu-ReadRange $fp 1 ([int]$lim)
} else {
$out = [System.IO.File]::ReadAllText($fp)
}
}
} else {
$out = "Error: file not found: $fp"; $rc = 1
}
}
'write' {
$fp = ''; $ct = ''; if ($in) {
$fp = [string]$in.path; $ct = [string]$in.content
}
if ($fp -match '^-') { $fp = './' + $fp }; $fp = Pu-ResolvePath $fp; _tool 'write' (_p $fp)
if ($ct -match 'to=functions\.' -or $ct.Contains('<|channel|>') -or $ct.Contains('<|start|>assistant')) {
$out = 'Error: content contains harmony channel markers (likely model CoT leakage); refusing write'; $rc = 1
} else {
$dir = Split-Path -Parent $fp; if ($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)) {
try { New-Item -ItemType Directory -Path $dir -Force | Out-Null } catch { $out = "Error creating directory for $fp"; $rc = 1 }
}
if ($rc -eq 0) {
$prevRO = Pu-Save-Attrs $fp; try {
$tmp = Join-Path $(if ($dir) { $dir } else { '.' }) ('.pu.' + [System.IO.Path]::GetRandomFileName())
[System.IO.File]::WriteAllText($tmp, $ct, (New-Object System.Text.UTF8Encoding($false))); if ($prevRO) { Pu-Clear-Attrs $fp }; Move-Item -LiteralPath $tmp -Destination $fp -Force
if ($prevRO) { Pu-Restore-Attrs $fp $true }; $out = "Wrote to $fp"
} catch {
if ($tmp -and (Test-Path -LiteralPath $tmp)) { Remove-Item -LiteralPath $tmp -Force }; $out = "Error writing $fp"; $rc = 1
}
}
}
}
'edit' {
$fp = ''; $old = ''; $new = ''; if ($in) {
$fp = [string]$in.path; $old = [string]$in.oldText; $new = [string]$in.newText
}
if ($fp -match '^-') { $fp = './' + $fp }; $fp = Pu-ResolvePath $fp; _tool 'edit' (_p $fp); if (-not $old) {
$out = 'Error: oldText must not be empty'; $rc = 1
} elseif ($new -match 'to=functions\.' -or $new.Contains('<|channel|>') -or $new.Contains('<|start|>assistant')) {
$out = 'Error: newText contains harmony channel markers (likely model CoT leakage); refusing edit'; $rc = 1
} elseif (Test-Path -LiteralPath $fp -PathType Leaf) {
try {
$content = [System.IO.File]::ReadAllText($fp); $count = 0; $idx = 0
while (($idx = $content.IndexOf($old, $idx)) -ge 0) { $count++; $idx += $old.Length }; if ($count -gt 1) {
$out = "Error: oldText matched multiple times in $fp. Use a larger unique oldText block."; $rc = 1
} elseif ($count -eq 0) {
$out = "Error: oldText not found in $fp. Read exact surrounding lines before retrying; do not retry the same oldText."; $rc = 1
} else {
$newContent = $content.Replace($old, $new); $prevRO = Pu-Save-Attrs $fp; $dir = Split-Path -Parent $fp
$tmp = Join-Path $(if ($dir) { $dir } else { '.' }) ('.pu.' + [System.IO.Path]::GetRandomFileName())
[System.IO.File]::WriteAllText($tmp, $newContent, (New-Object System.Text.UTF8Encoding($false))); if ($prevRO) { Pu-Clear-Attrs $fp }
Move-Item -LiteralPath $tmp -Destination $fp -Force; if ($prevRO) { Pu-Restore-Attrs $fp $true }; $out = "Edited $fp"
}
} catch {
if ($tmp -and (Test-Path -LiteralPath $tmp)) { Remove-Item -LiteralPath $tmp -Force }; $out = "Error editing $fp"; $rc = 1
}
} else {
$out = "Error: file not found: $fp"; $rc = 1
}
}
'grep' {
$pat = ''; $gp = ''; if ($in) {
$pat = [string]$in.pattern; $gp = [string]$in.path
}
if (-not $gp) { $gp = '.' }; _tool 'grep' ($pat + ' ' + (_p $gp)); if ($gp -match '^-') { $gp = './' + $gp }; $gp = Pu-ResolvePath $gp; $out = Pu-Grep $pat $gp; $rc = $LASTEXITCODE
if ($rc -eq 1) { $out = 'No matches'; $rc = 0 }; $out = (($out -split "`n") | Select-Object -First 100) -join "`n"
}
'find' {
$fp2 = ''; $fn = ''; if ($in) {
$fp2 = [string]$in.path; $fn = [string]$in.name
}
if (-not $fp2) { $fp2 = '.' }; _tool 'find' ((_p $fp2) + ' ' + $fn); if ($fp2 -match '^-') { $fp2 = './' + $fp2 }; $fp2 = Pu-ResolvePath $fp2; $out = Pu-Find $fp2 $fn
$rc = $LASTEXITCODE
}
'ls' {
$lp = ''; if ($in) { $lp = [string]$in.path }; if (-not $lp) { $lp = '.' }; _tool 'ls' (_p $lp); if ($lp -match '^-') { $lp = './' + $lp }; $lp = Pu-ResolvePath $lp
$out = Pu-Ls $lp; $rc = $LASTEXITCODE
}
default {
$out = "Error: unknown tool: $tool_name"; $rc = 1
}
}
$Mt = [int]$AGENT_TOOL_TRUNC; if ($tool_name -ne 'read' -and $out.Length -gt $Mt) { $out = _trunc_text $Mt $out }; return $out
}
function Global:Pu-ShellTask([string]$cmd) {
& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command $cmd 2>&1; return $LASTEXITCODE
}
function Global:Pu-RunShell([string]$cmd) {
$pin = '[Console]::OutputEncoding=[System.Text.Encoding]::UTF8;'; $fixed = $pin + "`n" + $cmd
$cap = & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command $fixed 2>&1; $global:LASTEXITCODE = $LASTEXITCODE; if (-not $cap) { return '' }; $parts = @()
foreach ($x in @($cap)) {
if ($x -is [System.Management.Automation.ErrorRecord]) { $parts += $x.ToString() } else { $parts += [string]$x }
}
$text = ($parts -join "`n"); if ($text.EndsWith("`n")) { $text = $text.Substring(0, $text.Length - 1) }; return $text
}
function Global:Pu-ReadRange([string]$fp, [int]$startLine, [int]$countLines) {
$all = [System.IO.File]::ReadAllLines($fp); $outLines = New-Object System.Collections.Generic.List[string]
for ($i = $startLine - 1; $i -lt $startLine - 1 + $countLines -and $i -lt $all.Length; $i++) {
if ($i -ge 0) { [void]$outLines.Add($all[$i]) }
}
return ($outLines -join "`n")
}
$global:PU_NOISE_DIRS = @('.git', 'node_modules', 'dist', 'build', 'target', '.venv')
$global:PU_NOISE_FILES = @('.pu-events.jsonl', '.pu-history.json', '.pu-history.json.meta', 'agent.jsonl'); function Global:Pu-Grep([string]$pat, [string]$gp) {
$outLines = New-Object System.Collections.Generic.List[string]; $re = $null; try { $re = [regex]::new($pat, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase) } catch {
Write-Output "Error: invalid pattern: $pat"; $global:LASTEXITCODE = 2; return
}
$files = @(); if (Test-Path -LiteralPath $gp -PathType Container) {
$files = @(Get-ChildItem -LiteralPath $gp -File -Recurse -Force -ErrorAction SilentlyContinue |
Where-Object {
$p = $_.FullName; $inNoise = $false; foreach ($nd in $PU_NOISE_DIRS) { if ($p -match ([regex]::Escape('\') + $nd + [regex]::Escape('\'))) { $inNoise = $true; break } }
if ($inNoise) { return $false }; if ($PU_NOISE_FILES -contains $_.Name) { return $false }; return $true
})
} elseif (Test-Path -LiteralPath $gp -PathType Leaf) {
$files = @(Get-Item -LiteralPath $gp)
} else {
$global:LASTEXITCODE = 1; return ''
}
foreach ($f in $files) {
try {
$ln = 0; foreach ($line in [System.IO.File]::ReadLines($f.FullName)) {
$ln++
if ($re.IsMatch($line)) {
$disp = $f.FullName.Replace($PWD.Path + '\', '').Replace('\', '/'); $outLines.Add($disp + ':' + $ln + ':' + $line)
}
}
} catch { }
}
if ($outLines.Count -eq 0) { $global:LASTEXITCODE = 1; return '' }; $global:LASTEXITCODE = 0; return ($outLines -join "`n")
}
function Global:Pu-Find([string]$fp2, [string]$fn) {
$items = @(); if (Test-Path -LiteralPath $fp2 -PathType Leaf) {
$items = @(Get-Item -LiteralPath $fp2)
} elseif (Test-Path -LiteralPath $fp2 -PathType Container) {
$items = @(Get-ChildItem -LiteralPath $fp2 -Recurse -Force -ErrorAction SilentlyContinue |
Where-Object {
$p = $_.FullName; $inNoise = $false; foreach ($nd in $PU_NOISE_DIRS) { if ($p -match ([regex]::Escape('\') + $nd + [regex]::Escape('\'))) { $inNoise = $true; break } }
if ($inNoise) { return $false }; if ($PU_NOISE_FILES -contains $_.Name) { return $false }; return $true
})
} else {
$global:LASTEXITCODE = 1; return ''
}
$out = New-Object System.Collections.Generic.List[string]; if ($fn) {
foreach ($i in $items) {
if ($i.Name -like $fn) {
$disp = $i.FullName.Replace($PWD.Path + '\', '').Replace('\', '/'); if ($disp) { $out.Add($disp) }
}
}
} else {
foreach ($i in $items) {
$disp = $i.FullName.Replace($PWD.Path + '\', '').Replace('\', '/'); if ($disp) {
$depth = ($disp -split '/').Count - 1; if ($depth -lt 3) { $out.Add($disp) }
}
}
}
if ($out.Count -eq 0) { $global:LASTEXITCODE = 0; return '' }; $global:LASTEXITCODE = 0; return ($out | Select-Object -First 100) -join "`n"
}
function Global:Pu-Ls([string]$lp) {
$out = New-Object System.Collections.Generic.List[string]; try {
$items = @(Get-ChildItem -LiteralPath $lp -Force -ErrorAction Stop); foreach ($i in $items) {
$mode = if ($i.PSIsContainer) { 'd---------' } else { '----------' }; $sz = if ($i.PSIsContainer) { '' } else { ('{0,10}' -f $i.Length) }
$dt = $i.LastWriteTime.ToString('MMM d HH:mm', [Globalization.CultureInfo]::InvariantCulture); $out.Add($mode + ' ' + $sz + ' ' + $dt + ' ' + $i.Name)
}
$global:LASTEXITCODE = 0
} catch {
$out.Add($_.Exception.Message); $global:LASTEXITCODE = 1
}
return ($out -join "`n")
}
function Global:Pu-ResolvePath([string]$p) {
if ([string]::IsNullOrWhiteSpace($p)) { return $p }; if ([System.IO.Path]::IsPathRooted($p)) { return $p }; return [System.IO.Path]::GetFullPath((Join-Path (Get-Location).Path $p))
}
$global:Utf8NoBom = New-Object System.Text.UTF8Encoding($false); $global:LOG = Pu-ResolvePath $global:LOG; $global:HISTORY = Pu-ResolvePath $global:HISTORY
function Global:Pu-WriteAllText([string]$path, [string]$content) {
$path = Pu-ResolvePath $path; $dir = Split-Path -Parent $path; if ($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)) {
New-Item -ItemType Directory -Path $dir -Force | Out-Null
}
[System.IO.File]::WriteAllText($path, $content, $global:Utf8NoBom)
}
function Global:Pu-AppendAllText([string]$path, [string]$content) {
$path = Pu-ResolvePath $path; $dir = Split-Path -Parent $path; if ($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)) {
New-Item -ItemType Directory -Path $dir -Force | Out-Null
}
[System.IO.File]::AppendAllText($path, $content, $global:Utf8NoBom)
}
function Global:save {
if ($HISTORY) {
Pu-WriteAllText $HISTORY $MSGS; Pu-WriteAllText ($HISTORY + '.meta') ($PROVIDER + ':' + $MODEL)
}
}
function Global:load {
if (-not $HISTORY) { $global:MSGS = ''; return $false }; if ((Test-Path -LiteralPath $HISTORY -PathType Leaf) -and (Test-Path -LiteralPath ($HISTORY + '.meta') -PathType Leaf)) {
$meta = [System.IO.File]::ReadAllText($HISTORY + '.meta'); if ($meta -eq ($PROVIDER + ':' + $MODEL)) {
$global:MSGS = [System.IO.File]::ReadAllText($HISTORY); if ($MSGS.StartsWith('[') -and $MSGS -ne '[]') { return $true }
}
}
$global:MSGS = ''; return $false
}
function Global:log([string]$s, [string]$t, [string]$c) {
$cs = $c; if ($cs.Length -gt $AGENT_LOG_TRUNC) { $cs = _trunc_text $AGENT_LOG_TRUNC $cs }; $esc = JsonEscape $cs
$line = '{"s":' + $s + ',"t":"' + $t + '","c":"' + $esc + '"}' + "`n"; Pu-AppendAllText $LOG $line
}
function Global:_replay {
if ($INTERACTIVE -ne 1) { return }; if (-not (Test-Path -LiteralPath $LOG -PathType Leaf)) { return }; info ("Last messages from ${LOG}:")
$all = [System.IO.File]::ReadAllLines($LOG); $tail = @($all | Select-Object -Last 200); $buf = New-Object System.Collections.Generic.List[string]; $buf.Clear()
foreach ($l in $tail) {
if ($l -match '"t":"start"') { $buf.Clear() }; $buf.Add($l)
}
$PU_LOG_TTY = $false; foreach ($l in $buf) {
$t = jp $l 't'; $c = jp $l 'c'; switch ($t) {
'start' { Pu-ErrWrite ("`r$ESC[K$ESC[36m>$ESC[0m " + $c + "`n") }; 'response' { Pu-ErrWrite ($c + "`n") }; 'tool_call' { Pu-ErrWrite ($global:U_PLACEHOLDER + ' ' + $c + "`n") }
'error' { err $c }; 'max_steps' { err $c }
}
}
}
function Global:append([string]$msg) {
if (-not $MSGS -or $MSGS -eq '[]') { $global:MSGS = '[' + $msg + ']' }
else { $global:MSGS = $MSGS.Substring(0, $MSGS.Length - 1) + ',' + $msg + ']' }
}
$global:RA = '"role":"assistant"'; $global:RU = '"role":"user"'; $global:RT = '"role":"tool"'
function Global:track_tokens([string]$resp) {
$u = jb $resp 'usage'; $a = ''; $b = ''; $a = jp $u 'input_tokens'; $b = jp $u 'output_tokens'; if ($PROVIDER -ne 'anthropic') {
if (-not $a) { $a = jp $u 'prompt_tokens' }; if (-not $b) { $b = jp $u 'completion_tokens' }
}
if (-not $a) { $a = '0' }; if (-not $b) { $b = '0' }; $global:TOKEN_IN = [long]$global:TOKEN_IN + [long]$a; $global:TOKEN_OUT = [long]$global:TOKEN_OUT + [long]$b
$pi = 0.0; $po = 0.0; if ($env:AGENT_PRICE_IN_PER_MTOK) { $pi = [double]$env:AGENT_PRICE_IN_PER_MTOK }
if ($env:AGENT_PRICE_OUT_PER_MTOK) { $po = [double]$env:AGENT_PRICE_OUT_PER_MTOK }; $inc = ([long]$a * $pi + [long]$b * $po) / 1000000.0
$global:COST_USD = [Math]::Round([double]$global:COST_USD + $inc, 6)
}
function Global:_fmtk([long]$n) {
if ($n -ge 1000000) { return ('{0:0.0}M' -f ($n / 1000000.0)) }; if ($n -ge 1000) { return ('{0:0}k' -f [Math]::Floor($n / 1000.0)) }; return ('{0}' -f $n)
}
function Global:_ctxp {
$c = [double]$CTX_LIMIT; $n = [double]$MSGS.Length; $pct = if ($c -gt 0) { 100.0 * $n / $c } else { 0.0 }; return ('{0:0.0}%/{1}k' -f $pct, ([int]($c / 1000)))
}
function Global:_branch {
$g = Get-Command git -ErrorAction SilentlyContinue; if (-not $g) { return '' }; $old = $ErrorActionPreference; $ErrorActionPreference = 'SilentlyContinue'
try { $b = (& git branch --show-current 2>$null | Out-String).Trim() } catch { $b = '' }; $ErrorActionPreference = $old; if ($b) { return ' (' + $b + ')' }; return ''
}
function Global:_status {
$d = $global:PWDSTR; $h = Pu-HomeDir; if ($h -and $d.StartsWith($h + '\')) { $d = '~/' + $d.Substring($h.Length + 1) }
$s = $d + (_branch) + (( ' ' + [char]0x2191) + (_fmtk $TOKEN_IN) + (' ' + [char]0x2193) + (_fmtk $TOKEN_OUT)); if ($COST -eq 1) { $s = $s + (' ${0:0.000}' -f $COST_USD) }
$s = $s + ' ' + (_ctxp) + ' (' + $PROVIDER + ') ' + $MODEL; if ($EFFORT_OK -eq 1) { $s = $s + (' ' + [char]0x2022 + ' ') + $EFFORT }; return $s
}
function Global:spin_start([string]$msg) { }; function Global:spin_stop { }
function Global:_ctx_balanced([string]$s) {
if ($null -eq $s) { return $true }; $d = 0; $q = $false; $e = $false; for ($i = 0; $i -lt $s.Length; $i++) {
$c = $s[$i]; if ($e) { $e = $false; continue }; if ($c -eq '\') { if ($q) { $e = $true }; continue }; if ($c -eq '"') { $q = -not $q; continue }; if ($q) { continue }
if ($c -eq '{') { $d++ }
elseif ($c -eq '}') { $d-- }
}
return ($d -eq 0 -and -not $q)
}
function Global:_ctx_id([string]$s, [string]$key) {
if ($null -eq $s) { return '' }; $m = [regex]::Match($s, '"' + $key + '"[ \t]*:[ \t]*"(?<v>[^"]+)"'); if ($m.Success) { return $m.Groups['v'].Value }; return ''
}
function Global:_ctx_iscall([string]$s) {
return ($s -match '"type"[ \t]*:[ \t]*"function_call"' -and
$s -notmatch '"type"[ \t]*:[ \t]*"function_call_output"')
}
function Global:_ctx_outstub([string]$s) {
return '{"type":"function_call_output","call_id":"' + (_ctx_id $s 'call_id') +
'","output":"[large or malformed tool output omitted during compaction: ' + $s.Length + ' chars]"}'
}
function Global:_ctx_msgstub([string]$s) {
return '{"role":"user","content":"[large or malformed message omitted during compaction: ' + $s.Length + ' chars]"}'
}
function Global:_ctx_toolresultstub([string]$s) {
return '{"role":"user","content":[{"type":"tool_result","tool_use_id":"' + (_ctx_id $s 'tool_use_id') +
'","content":"[large or malformed tool result omitted during compaction: ' + $s.Length + ' chars]"}]}'
}
function Global:_ctx_toolusestub([string]$s) {
return '{"role":"assistant","content":[{"type":"tool_use","id":"' + (_ctx_id $s 'id') +
'","name":"' + (_ctx_id $s 'name') +
'","input":{"omitted":"large or malformed tool input omitted during compaction: ' + $s.Length + ' chars"}}]}'
}
function Global:_ctx_rolestub([string]$s) {
if ($s -match '"type"[ \t]*:[ \t]*"tool_result"') { return (_ctx_toolresultstub $s) }; if ($s -match '"type"[ \t]*:[ \t]*"tool_use"') { return (_ctx_toolusestub $s) }
return (_ctx_msgstub $s)
}
function Global:_ctx_callstub([string]$s) {
return '{"type":"function_call","call_id":"' + (_ctx_id $s 'call_id') +
'","name":"' + (_ctx_id $s 'name') +
'","arguments":"{\\\"omitted\\\":\\\"large or malformed tool arguments omitted during compaction: ' + $s.Length + ' chars\\\"}"}'
}
function Global:_ctx_entries([string]$text, [int]$outmax, [int]$max) {
$out = New-Object System.Collections.Generic.List[string]; if ([string]::IsNullOrEmpty($text)) { return '' }; if ($outmax -eq 0) { $outmax = 4000 }
if ($max -eq 0) { $max = 12000 }; $data = $text; if ($data.StartsWith('[')) { $data = $data.Substring(1) }; $tlen = $data.Length
if ($tlen -gt 0 -and $data.EndsWith(']')) { $data = $data.Substring(0, $tlen - 1) }; $chunks = @($data.Split([string[]]@('},{'), [System.StringSplitOptions]::None))
$nC = $chunks.Count; $pending = ''; $ptype = ''; for ($i = 0; $i -lt $nC; $i++) {
$raw = $chunks[$i]; $isn = ($i -lt $nC - 1); if ($pending -ne '') {
$pending = $pending + '},{' + $raw; $cand = $pending; if ($isn) { $cand = $cand + '}' }; if ($cand.Length -gt $max) {
if ($ptype -eq 'role') { [void]$out.Add((_ctx_rolestub $cand)) }
elseif (_ctx_iscall $cand) { [void]$out.Add((_ctx_callstub $cand)) }; $pending = ''; $ptype = ''; continue
}
if (_ctx_balanced $cand) { [void]$out.Add($cand); $pending = ''; $ptype = '' }; continue
}
$e = $(if ($i -gt 0) { '{' } else { '' }) + $raw; $cand = $e; if ($isn) { $cand = $cand + '}' }; if ($cand -match '^\{[ \t]*"type"[ \t]*:[ \t]*"function_call_output"') {
if ($cand.Length -le $outmax -and (_ctx_balanced $cand)) { [void]$out.Add($cand) }
else { [void]$out.Add((_ctx_outstub $cand)) }; continue
}
if ($cand -match '^\{[ \t]*"(role|id|type)"' -and -not (_ctx_balanced $cand) -and $cand.Length -le $max) {
$pending = $e; if ($cand -match '^\{[ \t]*"role"') { $ptype = 'role' } else { $ptype = 'other' }; continue
}
if (_ctx_iscall $cand) {
if ($cand.Length -le $max -and (_ctx_balanced $cand)) { [void]$out.Add($cand) }
else { [void]$out.Add((_ctx_callstub $cand)) }; continue
}
if ($cand -match '^\{[ \t]*"(role|id|type)"') {
if ($cand.Length -le $max -and (_ctx_balanced $cand)) { [void]$out.Add($cand) }
elseif ($cand -match '^\{[ \t]*"role"') { [void]$out.Add((_ctx_rolestub $cand)) }; continue
}
}
return ($out -join "`n")
}
function Global:_ctx_filter_openai_pairs([string]$s) {
$lines = @($s -split "`n"); $out = New-Object System.Collections.Generic.List[string]; $seen = @{}; foreach ($line in $lines) {
if ($line -eq '') { continue }; $id = _ctx_id $line 'call_id'; if ($line -match '^\{.*"type"[ \t]*:[ \t]*"function_call"' -and
$line -notmatch '^\{.*"type"[ \t]*:[ \t]*"function_call_output"') {
if ($id -ne '') { $seen[$id] = $true }; [void]$out.Add($line); continue
}
if ($line -match '^\{.*"type"[ \t]*:[ \t]*"function_call_output"') {
if ($id -ne '' -and $seen.ContainsKey($id)) { [void]$out.Add($line) }; continue
}
[void]$out.Add($line)
}
return ($out -join "`n")
}
function Global:_ctx_filter_anthropic_pairs([string]$s) {
$lines = @($s -split "`n"); if ($lines.Count -eq 1 -and $lines[0] -eq '') { $lines = @() }; $a = New-Object System.Collections.Generic.List[string]; $useLine = @{}; $resLine = @{}
$useAt = @{}; $resAt = @{}; for ($n = 0; $n -lt $lines.Count; $n++) {
$line = $lines[$n]; if ($line -eq '') { continue }; [void]$a.Add($line); $idx = $n + 1; if ($line -match '"type"[ \t]*:[ \t]*"tool_use"') {
$ids = @(); foreach ($m in [regex]::Matches($line, '"id"[ \t]*:[ \t]*"[^"]+"')) {
$t = $m.Value; $t = $t -replace '^.*"id"[ \t]*:[ \t]*"', ''; $t = $t -replace '"$', ''; $ids += $t
}
$useLine[$idx] = $ids; foreach ($b in $ids) { if ($b -ne '' -and -not $useAt.ContainsKey($b)) { $useAt[$b] = $idx } }
}
if ($line -match '"type"[ \t]*:[ \t]*"tool_result"') {
$ids = @(); foreach ($m in [regex]::Matches($line, '"tool_use_id"[ \t]*:[ \t]*"[^"]+"')) {
$t = $m.Value; $t = $t -replace '^.*"tool_use_id"[ \t]*:[ \t]*"', ''; $t = $t -replace '"$', ''; $ids += $t
}
$resLine[$idx] = $ids; foreach ($b in $ids) { if ($b -ne '' -and -not $resAt.ContainsKey($b)) { $resAt[$b] = $idx } }
}
}
function okuse([string[]]$list, [int]$idx) {
foreach ($b in $list) {
if ($b -ne '' -and (( -not $resAt.ContainsKey($b)) -or ($resAt[$b] -le $idx))) { return $false }
}
return $true
}
function okres([string[]]$list, [int]$idx) {
foreach ($b in $list) {
if ($b -ne '' -and (( -not $useAt.ContainsKey($b)) -or ($useAt[$b] -ge $idx))) { return $false }
}
return $true
}
$out = New-Object System.Collections.Generic.List[string]; for ($i = 1; $i -le $a.Count; $i++) {
if ($useLine.ContainsKey($i) -and -not (okuse $useLine[$i] $i)) { continue }; if ($resLine.ContainsKey($i) -and -not (okres $resLine[$i] $i)) { continue }
[void]$out.Add($a[$i - 1])
}
return ($out -join "`n")
}
function Global:_ctx_valid([string]$x, [int]$cap) {
if (-not $x.StartsWith('[')) { return $false }; if ($x.Length -gt $cap) { return $false }; if ($x.Contains(',,') -or $x.StartsWith('[,') -or $x.EndsWith(',]')) { return $false }
return $true
}
function Global:_ctx_local_memory([string]$mid, [string]$f) {
$b = New-Object System.Text.StringBuilder; if ($f) { [void]$b.AppendLine('Focus: ' + $f) }; [void]$b.AppendLine('Goal:'); [void]$b.AppendLine('User constraints/directives:')
$u = 0; foreach ($ln in @($mid -split "`n")) {
if ($ln -match '"role":"user"' -and $u -lt 8) {
$s = $ln -replace '\\n', ' '; $s = $s -replace '\\"', '"'; if ($s.Length -gt 260) { $s = $s.Substring(0, 260) + '...' }; [void]$b.AppendLine('- ' + $s); $u++
}
}
[void]$b.AppendLine('Files read:'); $seenPath = @{}; $pn = 0; foreach ($m in [regex]::Matches($mid, '"path":"[^"]+"')) {
if ($pn -ge 20) { break }; $t = $m.Value.Substring(8); $t = $t.Substring(0, $t.Length - 1)
if (-not $seenPath.ContainsKey($t)) { $seenPath[$t] = $true; [void]$b.AppendLine('- ' + $t); $pn++ }
}
[void]$b.AppendLine('Files changed:'); $cn = 0; foreach ($ln in @($mid -split "`n")) {
if ($cn -ge 20) { break }; if ($ln -match '"name":"(write|edit)"|Wrote to |Edited ') { [void]$b.AppendLine('- ' + $ln); $cn++ }
}
[void]$b.AppendLine('Commands run:'); $qn = 0; foreach ($m in [regex]::Matches($mid, '"command":"[^"]+"')) {
if ($qn -ge 20) { break }; $t = $m.Value.Substring(10); $t = $t.Substring(0, $t.Length - 1); [void]$b.AppendLine('- ' + $t); $qn++
}
[void]$b.AppendLine('Errors/failures:'); $en = 0; foreach ($ln in @($mid -split "`n")) {
if ($en -ge 30) { break }; if ($ln -match 'Error:|\[exit:[0-9]+\]|\[denied\]|failed|Failed') { [void]$b.AppendLine('- ' + $ln); $en++ }
}
[void]$b.AppendLine('Decisions made:'); [void]$b.AppendLine('- See retained recent transcript for latest decisions.'); [void]$b.AppendLine('Important snippets/facts:')
[void]$b.AppendLine('- Older bulky tool output may have been omitted; re-read files from disk as needed.'); [void]$b.AppendLine('Open TODOs / next steps:')
[void]$b.AppendLine('- Continue from the latest retained user request and recent transcript.'); $all = $b.ToString().TrimEnd("`r", "`n"); $h = $all -split "`n"
if ($h.Count -gt 120) { $all = ($h | Select-Object -First 120) -join "`n" }; return $all
}
function Global:_ctx_last_resort([int]$cap, [string]$f) {
$msg = '[Earlier context was compacted locally due to size.'; if ($f) { $msg = $msg + ' Focus: ' + $f + '.' }; $msg = $msg + ' Continue from the latest user request.]'
$x = '[{"role":"user","content":"' + (JsonEscape $msg) + '"}]'; if ($x.Length -le $cap) { return $x }; return '[]'
}
function Global:_ctx_tail_start([string]$o, [int]$k) {
$lines = @($o -split "`n"); if ($lines.Count -eq 1 -and $lines[0] -eq '') { return 2 }; $s = 0; $i = $lines.Count
while ($i -gt 1) {
$s += $lines[$i - 1].Length; if ($s -gt $k) { break }; $i--
}
return $i + 1
}
function Global:_ctx_adjust_start([string]$o, [int]$nn, [int]$c) {
$lines = @($o -split "`n"); $guard = 0
while ($true) {
$h = ''; if ($c -ge 1 -and $c -le $lines.Count) { $h = $lines[$c - 1] }; if ($h.Contains('reasoning')) { break }
if ($h.Contains('tool_result') -or $h.Contains('function_call_output') -or $h.Contains('"type":"function_call"')) { $c-- }
else { break }; $guard++
if ($c -le 2 -or $guard -gt 20) { break }
}
if ($c -lt 2) { $c = $nn - 2 }; return $c
}
function Global:_ctx_sanitize_openai([string]$m, [int]$cap) {
if ($PROVIDER -ne 'openai') { return $m }; if (-not ($m.Contains('"type":"function_call_output"') -or
$m.Contains('"type"' + '"function_call_output"'))) { return $m }; [string]$o = _ctx_entries $m 0 0; $f = _ctx_filter_openai_pairs $o
$new = '[' + (($f -split "`n") -join ',') + ']'; if ($f -eq $o) {
if (-not ($new.Contains('large or malformed tool '))) { return $m }
}
if (_ctx_valid $new $cap) {
log 0 compact ("old=" + $m.Length + " new=" + $new.Length + " cap=" + $cap + " mode=sanitize-openai-pairs"); return $new
}
return $m
}
function Global:_ctx_sanitize_anthropic([string]$m, [int]$cap) {
if ($PROVIDER -ne 'anthropic') { return $m }; if (-not ($m.Contains('"type":"tool_result"') -or $m.Contains('"type"' + '"tool_result"') -or
$m.Contains('"type":"tool_use"') -or $m.Contains('"type"' + '"tool_use"'))) { return $m }; [string]$o = _ctx_entries $m 0 0; $f = _ctx_filter_anthropic_pairs $o
$new = '[' + (($f -split "`n") -join ',') + ']'; if ($f -eq $o) {
if (-not ($new.Contains('large or malformed tool '))) { return $m }
}
if (_ctx_valid $new $cap) {
log 0 compact ("old=" + $m.Length + " new=" + $new.Length + " cap=" + $cap + " mode=sanitize-anthropic-pairs"); return $new
}
return $m
}
function Global:_ctx_sanitize_pairs([string]$m, [int]$cap) {
switch ($PROVIDER) {
'openai'    { return (_ctx_sanitize_openai $m $cap) }; 'anthropic' { return (_ctx_sanitize_anthropic $m $cap) }; default     { return $m }
}
}
function Global:trim_context([string]$m, [string]$f) {
$cap = [int]$CTX_LIMIT - [int]$AGENT_RESERVE; if (-not $f -and $m.Length -le $cap) { return (_ctx_sanitize_pairs $m $cap) }
info ('Compacting (' + $m.Length + 'b > ' + $cap + 'b)' + $(if ($f) { ' focus: ' + $f } else { '' })); [string]$o = _ctx_entries $m 0 0; switch ($PROVIDER) {
'openai'    { $o = _ctx_filter_openai_pairs $o }; 'anthropic' { $o = _ctx_filter_anthropic_pairs $o }
}
$olines = @($o -split "`n"); $n = 0; foreach ($l in $olines) { if ($l -ne '') { $n++ } }; if ($n -lt 6) {
if ($m.Length -le $cap) { return $m }; return (_ctx_last_resort $cap $f)
}
$half = [int][Math]::Floor($cap / 2); $kb = [int]$AGENT_KEEP_RECENT; if ($kb -gt $half) { $kb = $half }; if ($kb -lt 2000) { $kb = 2000 }; $c = _ctx_tail_start $o $kb
$c = _ctx_adjust_start $o $n $c; $a = $olines[0]; $midLines = New-Object System.Collections.Generic.List[string]; for ($i = 1; $i -lt $c - 1 -and $i -lt $n; $i++) {
$l = $olines[$i]; if ($l.Length -gt 4000) { $midLines.Add('[large transcript entry omitted: ' + $l.Length + ' chars]') }
else { $midLines.Add($l) }
}
if ($midLines.Count -gt 160) { $fullM = ($midLines | Select-Object -Last 160); $midLines = @(); foreach ($x in $fullM) { $midLines.Add([string]$x) } }
$mid = ($midLines -join "`n"); if (-not $mid) { $mid = '[older transcript omitted]' }; $p = $(if ($f) { 'Focus: ' + $f + '. ' } else { '' }) +
'Summarize the earlier transcript into this exact compact memory card. Be concise. Preserve actionable coding-agent state: user intent, constraints, files touched, edits, errors, decisions, and next steps. Prefer paths/ranges over copied bulk. Do not call tools.'
$p = $p + "`n`n" + 'Goal:' + "`n" + 'User constraints/directives:' + "`n" + 'Files read:' + "`n" +
'Files changed:' + "`n" + 'Commands run:' + "`n" + 'Errors/failures:' + "`n" + 'Decisions made:' + "`n" +
'Important snippets/facts:' + "`n" + 'Open TODOs / next steps:' + "`n`n" + 'Transcript/facts:' + "`n" + $mid; $req = '[{"role":"user","content":"' + (JsonEscape $p) + '"}]'
$res = call_api $req; parse_response $res; $compaction_summary_text = $global:TX; $mode = ''; if (-not $compaction_summary_text -or $compaction_summary_text -eq 'null') {
err 'Summarization failed; using local compaction memory'; $compaction_summary_text = _ctx_local_memory $mid $f; $mode = 'local'
} else {
$mode = 'normal'
}
if ($mode -eq 'local') {
$s = '{"role":"user","content":"[Earlier compacted locally:\n' + (JsonEscape $compaction_summary_text) + ']"}'
} else {
$s = '{"role":"user","content":"[Earlier compacted memory:\n' + (JsonEscape $compaction_summary_text) + ']"}'
}
while ($true) {
$c = _ctx_tail_start $o $kb; $c = _ctx_adjust_start $o $n $c; $r = ''; for ($i = $c; $i -le $n; $i++) {
if ($r) { $r = $r + ',' }; $r = $r + $olines[$i - 1]
}
$new = '[' + $a + ',' + $s + ',' + $r + ']'; if (_ctx_valid $new $cap) {
log 0 compact ('old=' + $m.Length + ' new=' + $new.Length + ' cap=' + $cap + ' mode=' + $mode + ' tail=' + $kb); return $new
}
if ($kb -le 2000) { break }; $kb = [int][Math]::Floor($kb / 2); if ($kb -lt 2000) { $kb = 2000 }
}
if ($mode -eq 'local') {
$localnote = _ctx_mid_notes $o $n; $compaction_summary_text = _ctx_local_memory $localnote $f
$s = '{"role":"user","content":"[Earlier compacted locally:\n' + (JsonEscape $compaction_summary_text) + ']"}'
}
$new = '[' + $a + ',' + $s + ']'; if (_ctx_valid $new $cap) {
log 0 compact ('old=' + $m.Length + ' new=' + $new.Length + ' cap=' + $cap + ' mode=' + $mode + '-no-tail'); return $new
}
$localnote = _ctx_mid_notes $o $n; $localnote = _ctx_local_memory $localnote $f; $s = '{"role":"user","content":"[Earlier compacted locally:\n' + (JsonEscape $localnote) + ']"}'
$new = '[' + $s + ']'; if (_ctx_valid $new $cap) {
log 0 compact ('old=' + $m.Length + ' new=' + $new.Length + ' cap=' + $cap + ' mode=emergency'); return $new
}
$new = _ctx_last_resort $cap $f; log 0 compact ('old=' + $m.Length + ' new=' + $new.Length + ' cap=' + $cap + ' mode=last-resort'); return $new
}
function Global:_ctx_mid_notes([string]$o, [int]$n) {
$lines = New-Object System.Collections.Generic.List[string]; for ($i = 1; $i -lt $n; $i++) {
$l = @($o -split "`n")[$i]; if ($l.Length -gt 4000) { $lines.Add('[large transcript entry omitted: ' + $l.Length + ' chars]') }
else { $lines.Add($l) }
}
$ret = @(); if ($lines.Count -gt 160) { $end = @($lines | Select-Object -Last 160); foreach ($x in $end) { $ret += [string]$x } }
else { foreach ($x in $lines) { $ret += [string]$x } }; return ($ret -join "`n")
}
function Global:run_task([string]$task) {
$global:_STATE = 'busy'; if ($task.StartsWith('!')) {
$cr = Pu-ShellTask ($task.Substring(1)); if ($global:_STATE -eq 'idle') { return 130 }; return $cr
}
if (-not (_ensure_key)) { return 1 }; $task_esc = JsonEscape $task; if (-not $MSGS) { [void](load) }; if ($MSGS) {
append ('{"role":"user","content":"' + $task_esc + '"}')
} else {
$global:MSGS = '[{"role":"user","content":"' + $task_esc + '"}]'
}
log 0 start $task; $step = 0; $empty_final = 0; $ctx_retry = 0
while ($step -lt [int]$MAX_STEPS) {
$step++
$global:MSGS = trim_context $MSGS ''; $global:_STATE = 'busy'; $resp = ''; $retry = 0
while ($retry -lt 3) {
$cr = 0; $resp = call_api $MSGS; if ($env:AGENT_DEBUG_API) {
try {
New-Item -ItemType Directory -Path $env:AGENT_DEBUG_API -Force | Out-Null; Pu-WriteAllText (Join-Path $env:AGENT_DEBUG_API ('input-' + $step + '-' + $retry + '.json')) $MSGS
Pu-WriteAllText (Join-Path $env:AGENT_DEBUG_API ('resp-' + $step + '-' + $retry + '.json')) $resp
} catch { }
}
if ($_STATE -eq 'idle') { err '[interrupted]'; return 130 }; if ($PU_API_RC -ne 0) {
$retry++
$first = ($resp -split "`n" | Select-Object -First 1)[0]; err ('API transport: ' + $first); if ($retry -ge 3) { return 1 }; SleepSec ($retry * 2); continue
}
if (-not $resp) {
$retry++
err ('Empty, retry ' + $retry + '/3'); SleepSec ($retry * 2); continue
}
$api_err = jp $resp 'error'; $em = jp $api_err 'message'; $lc = $em.ToLower(); $fatal = $false
if ($lc -match 'incorrect.*api.*key|invalid.*api.*key|unauthorized|authentication') {
err ('API: ' + $em); return 1
}
if ($lc -match 'invalid.*body|parse.*json') {
err ('API: ' + $em); return 1
}
if ($lc -match 'model.*not.*found|model.*does.*not.*exist|model.*not.*exist|access.*model') {
err ('API: ' + $em); err 'Try /model MODEL'; return 1
}
if ($lc -match 'context|token.*limit|too.*large') {
if ($ctx_retry -eq 0) {
$ctx_retry = 1; err 'Context full; compacting and retrying'; $global:MSGS = trim_context $MSGS 'recover from context overflow'; continue
}
}
if ($api_err -and $api_err -ne 'null' -and $api_err -ne '') {
err ('API: ' + $em); $retry++
SleepSec ($retry * 3); continue
}
break
}
if (-not $resp) {
err 'API failed'; log $step error 'fail'; return 1
}
$fatal = jp $resp 'error'; if ($fatal -and $fatal -ne 'null') {
err ('API failed: ' + (jp $fatal 'message')); log $step error 'api'; return 1
}
track_tokens $resp; parse_response $resp; if ($global:TS -and $global:TS -ne 'null') { _think $global:TS; log $step reasoning $global:TS }
if ($global:TY -eq 'T' -and $global:TN) {
if ($global:TX -and $global:TX -ne 'null') { _say $global:TX }; $trs = ''; $trm = ''; $trc = ''; switch ($PROVIDER) {
'anthropic' { $src = $global:CB; $mark = '"type":"tool_use"' }; 'openai'    { $src = $global:TC; $mark = '"function_call"' }
}
$src = $src -replace "`n", ''; $tuList = $(if ($PROVIDER -eq 'openai') { oa_items $src } else { each_tool_use $src $mark }); foreach ($tu in $tuList) {
if (-not $tu) { continue }; $tuTn = ''; $tuTi = ''; $tuTinp = ''; if ($PROVIDER -eq 'anthropic') {
$tuTn = jp $tu 'name'; $tuTi = jp $tu 'id'; $tuTinp = jp $tu 'input'
} else {
if ((jp $tu 'type') -eq 'reasoning') {
$trc = $trc + $(if ($trc) { ',' } else { '' }) + $tu; continue
}
$tuTi = jp $tu 'call_id'; if (-not $tuTi) { $tuTi = jp $tu 'id' }; $tuTn = jp $tu 'name'; $tuTinp = jp $tu 'arguments'
}
if (-not $tuTi -or -not $tuTn) {
log $step error ('Bad tool call: ' + $tu); continue
}
if ($PROVIDER -eq 'openai') { $trc = $trc + $(if ($trc) { ',' } else { '' }) + $tu }; $logfmt = $tuTinp; if ($logfmt.Length -gt 200) { $logfmt = $logfmt.Substring(0, 200) }
log $step tool_call ($tuTn + ': ' + $logfmt); $tout = run_tool $tuTn $tuTinp; if ($_STATE -eq 'idle') { err '[interrupted]'; return 130 }; log $step tool_result $tout
_tool_out $tout; if ($tout -match '^(Error:|\[exit:|\[denied)') { if ($PIPE -eq 0) { err $tout } }; $tesc = JsonEscape $tout
$trs = $trs + $(if ($trs) { ',' } else { '' }) + '{"type":"tool_result","tool_use_id":"' + $tuTi + '","content":"' + $tesc + '"}'; if ($PROVIDER -eq 'openai') {
$trm = $trm + ',{"type":"function_call_output","call_id":"' + $tuTi + '","output":"' + $tesc + '"}'
} else {
$trm = $trm + ',{' + $RT + ',"tool_call_id":"' + $tuTi + '","content":"' + $tesc + '"}'
}
}
if (-not $trs) {
err 'No valid tool calls parsed'; dbg $resp; log $step error 'No valid tool calls parsed'; return 1
}
switch ($PROVIDER) {
'anthropic' {
if ($global:CB) {
append ('{' + $RA + ',"content":' + $global:CB + '},{' + $RU + ',"content":[' + $trs + ']}')
} else {
$ti0 = $global:TINP; if (-not $ti0) { $ti0 = '{}' }
append ('{' + $RA + ',"content":[{"type":"text","text":""},{"type":"tool_use","id":"' + $global:TI + '","name":"' + $global:TN + '","input":' + $ti0 + '}]},{' + $RU + ',"content":[' + $trs + ']}')
}
}
'openai' { append ($trc + $trm) }
}
save
} elseif ($global:TY -eq 'X') {
if (-not $global:TX -or $global:TX -eq 'null') {
if ($empty_final -eq 0) {
$empty_final = 1; if ("$PROVIDER`:$EFFORT_OK" -eq 'openai:1') { $global:EFFORT = 'low' }; append '{"role":"user","content":"Please summarize your findings and next steps."}'
continue
}
err 'Empty final response'; return 1
}
if ($PIPE -eq 0 -and $INTERACTIVE -eq 1) { _say $global:TX } else { Pu-SayFinal $global:TX }; log $step response $global:TX
append ('{"role":"assistant","content":"' + (JsonEscape $global:TX) + '"}'); info (('done ' + [char]0x00B7 + ' ') + (_status)); save; return 0
} else {
err 'Parse failed'; dbg $resp; log $step error 'Parse fail'; return 1
}
}
err ('Max steps (' + $MAX_STEPS + ')'); info (('stopped ' + [char]0x00B7 + ' ') + (_status)); log $step max_steps 'Limit'; return 1
}
function Global:load_context {
$ctx = New-Object System.Text.StringBuilder; $dir = (Get-Location).Path; $has = $false
while ($dir -and $dir.Length -gt 2) {
foreach ($fn in @('AGENTS.md', 'CLAUDE.md')) {
$p = Join-Path $dir $fn; if (Test-Path -LiteralPath $p -PathType Leaf) {
[void]$ctx.AppendLine(); [void]$ctx.Append([System.IO.File]::ReadAllText($p)); $has = $true
}
}
$parent = Split-Path -Parent $dir; if ($parent -eq $dir) { break }; $dir = $parent
}
while ($dir -and $dir.Length -eq 2) {
foreach ($fn in @('AGENTS.md', 'CLAUDE.md')) {
$p = Join-Path $dir $fn; if (Test-Path -LiteralPath $p -PathType Leaf) {
[void]$ctx.AppendLine(); [void]$ctx.Append([System.IO.File]::ReadAllText($p)); $has = $true
}
}
break
}
$pi = Join-Path (Pu-HomeDir) '.pi\agent\AGENTS.md'; if (Test-Path -LiteralPath $pi -PathType Leaf) {
$homeCtx = [System.IO.File]::ReadAllText($pi); $global:SYSTEM = $homeCtx + "`n" + $global:SYSTEM; $has = $true
}
if ($has) {
info 'Loaded context files'; $global:SYSTEM = $global:SYSTEM + "`n" + $ctx.ToString()
}
}
function Global:_tpl([string]$n) {
foreach ($d in @('.pi\prompts', (Join-Path (Pu-HomeDir) '.pi\agent\prompts'))) {
$p = Join-Path $d ($n + '.md'); if (Test-Path -LiteralPath $p -PathType Leaf) {
return ([System.IO.File]::ReadAllText($p))
}
}
return $n
}
function Global:_skill([string]$n) {
foreach ($d in @('.pi\skills', '.agents\skills', (Join-Path (Pu-HomeDir) '.pi\agent\skills'), (Join-Path (Pu-HomeDir) '.agents\skills'))) {
$p = Join-Path (Join-Path $d $n) 'SKILL.md'; if (Test-Path -LiteralPath $p -PathType Leaf) {
info ('Loaded skill: ' + $n); $global:SYSTEM = $global:SYSTEM + "`n" + ([System.IO.File]::ReadAllText($p)); return
}
}
err ('Skill not found: ' + $n)
}
function Global:_export([string]$out) {
if (-not $out) { $out = 'session.md' }; $b = New-Object System.Text.StringBuilder; [void]$b.AppendLine('# Session Export'); [void]$b.AppendLine()
if (Test-Path -LiteralPath $LOG -PathType Leaf) {
foreach ($line in [System.IO.File]::ReadAllLines($LOG)) {
$t = jp $line 't'; $c = jp $line 'c'; switch ($t) {
'start'      { [void]$b.AppendLine('## Task');       [void]$b.AppendLine($c); [void]$b.AppendLine() }; 'tool_call'  { [void]$b.AppendLine('### Tool: ' + $c) }
'tool_result'{ [void]$b.AppendLine('```');          [void]$b.AppendLine($c); [void]$b.AppendLine('```'); [void]$b.AppendLine() }
'response'   { [void]$b.AppendLine('## Response');   [void]$b.AppendLine($c); [void]$b.AppendLine() }
}
}
}
Pu-WriteAllText $out $b.ToString(); info ('Exported to ' + $out)
}
function Global:_sq([string]$s) {
return ("'" + ($s -replace "'", "'\''") + "'")
}
function Global:_have_key {
switch ($PROVIDER) {
'anthropic' { if ($env:ANTHROPIC_API_KEY) { return $true }; return $false }; 'openai'    { if ($env:OPENAI_API_KEY) { return $true }; return $false }; default     { return $false }
}
}
function Global:_ensure_key {
if (_have_key) { return $true }; if (-not [Console]::IsErrorRedirected) {
_setup; if (_have_key) { return $true }; return $false
}
err 'No API key. Set ANTHROPIC_API_KEY or OPENAI_API_KEY (https://console.anthropic.com/settings/keys | https://platform.openai.com/api-keys)'; return $false
}
function Global:_set_provider_model([string]$p, [string]$m) {
$global:PROVIDER = $p; $global:MODEL = $m; $global:EFFORT_OK = 0; if ("$p`:$m" -like 'openai:gpt-5.5*') {
if (-not $env:AGENT_CONTEXT_LIMIT) { $global:CTX_LIMIT = 400000 }; $global:EFFORT_OK = 1
}
elseif ("$p`:$m" -like 'anthropic:claude-opus-4-7*') {
if (-not $env:AGENT_CONTEXT_LIMIT) { $global:CTX_LIMIT = 272000 }; $global:EFFORT_OK = 1
}
elseif ("$p`:$m" -like 'anthropic:claude-opus-4-6*' -or
"$p`:$m" -like 'anthropic:claude-sonnet-4-6*' -or
"$p`:$m" -like 'anthropic:claude-opus-4-5*') { $global:EFFORT_OK = 1 }
}
function Global:_setup {
if (-not (_stdin_is_console)) { err 'No API key and no console for setup.; set ANTHROPIC_API_KEY or OPENAI_API_KEY'; exit 1 }
$p = Read-Host "`nWelcome to pu-unminified.ps1.`n`nProvider:`n  1) Anthropic (Claude)`n  2) OpenAI (GPT)`n> "; $km = ''; $u = ''; $dm = ''; switch ($p) {
{ $_ -eq '2' -or $_ -eq 'openai' -or $_ -eq 'OpenAI' } {
$global:PROVIDER = 'openai'; $km = 'OPENAI_API_KEY'; $u = 'https://platform.openai.com/api-keys'; $dm = 'gpt-5.5'
}
default {
$global:PROVIDER = 'anthropic'; $km = 'ANTHROPIC_API_KEY'; $u = 'https://console.anthropic.com/settings/keys'; $dm = 'claude-opus-4-7'
}
}
try { Start-Process $u | Out-Null } catch { }; $k = ''; $sec = Read-Host ('Get a key at ' + $u + "`nPaste API key (hidden)") -AsSecureString; if ($sec) {
$bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
try { $k = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
}
$k = CleanKey $k; if (-not $k) { err 'No key entered'; exit 1 }; $m = Read-Host ('Model [' + $dm + ']'); if (-not $m) { $m = $dm }; _set_provider_model $PROVIDER $m
$e = Read-Host 'Effort [medium] (OpenAI: none/minimal/low/medium/high/xhigh; Claude: low/medium/high/max, xhigh on Opus 4.7)'; if (-not $e) { $e = 'medium' }; switch ($e) {
'n' { $e = 'none' }; 'min' { $e = 'minimal' }; 'l' { $e = 'low' }; 'm' { $e = 'medium' }; 'h' { $e = 'high' }
{ $_ -eq 'x' -or $_ -eq 'xh' } { $e = 'xhigh' }
}
$global:EFFORT = $e; $ep = ''; if ($env:AGENT_ENDPOINT) { $ep = $env:AGENT_ENDPOINT }; $ep1 = Read-Host ('Custom API endpoint base URL, blank for default [' + $ep + ']')
if ($ep1) { $ep = $ep1.TrimEnd('/') }; if ($km -eq 'OPENAI_API_KEY') { $env:OPENAI_API_KEY = $k } else { $env:ANTHROPIC_API_KEY = $k }; $env:AGENT_PROVIDER = $PROVIDER
$env:AGENT_MODEL = $MODEL; $env:AGENT_EFFORT = $EFFORT; if ($ep) { $env:AGENT_ENDPOINT = $ep } else { Remove-Item Env:AGENT_ENDPOINT -ErrorAction SilentlyContinue }
$s = Read-Host 'Save to ~/.pu.env so next time is automatic? [Y/n]'; switch ($s) {
{ $_ -eq 'n' -or $_ -eq 'N' -or $_ -eq 'no' -or $_ -eq 'NO' } {
info 'Not saved (set in this session only)'
}
default {
$ef = [System.IO.File]::Create((Join-Path (Pu-HomeDir) '.pu.env')); $ef.Close()
$lines = @(($km + '=' + (& _sq $k)), ('AGENT_PROVIDER=' + (& _sq $PROVIDER)), ('AGENT_MODEL=' + (& _sq $MODEL)), ('AGENT_EFFORT=' + (& _sq $EFFORT)), ('AGENT_REASONING_SUMMARY=' + (& _sq $REASONING_SUMMARY)))
if ($ep) { $lines += 'AGENT_ENDPOINT=' + (& _sq $ep) }; Pu-WriteAllText (Join-Path (Pu-HomeDir) '.pu.env') ($lines -join "`n"); info 'Saved ~/.pu.env'
}
}
}
function Global:handle_cmd([string]$c1) {
$c1 = $c1.Trim(); switch -regex ($c1) {
'^/model(\s+|$)' {
$nm = $c1 -replace '^/model *', ''; if ($nm) {
if ($nm -match '^(gpt-|o1|o3|o4)') { _set_provider_model 'openai' $nm }
elseif ($nm -like 'claude-*') { _set_provider_model 'anthropic' $nm }
else { $global:MODEL = $nm }; info ('Model: ' + $MODEL + ' (' + $PROVIDER + ')')
} else {
info ('Current: ' + $MODEL + ' (' + $PROVIDER + ')')
}
return $true
}
'^/effort(\s+|$)' {
$ef = $c1 -replace '^/effort *', ''; if ($ef) {
switch ($ef) {
'n' { $ef = 'none' }; 'min' { $ef = 'minimal' }; 'l' { $ef = 'low' }; 'm' { $ef = 'medium' }; 'h' { $ef = 'high' }
{ $_ -eq 'x' -or $_ -eq 'xh' } { $ef = 'xhigh' }
}
$global:EFFORT = $ef
}
info ('Effort: ' + $EFFORT); return $true
}
'^/reasoning(\s+|$)' {
$rs0 = $c1 -replace '^/reasoning *', ''; if ($rs0) {
switch ($rs0) {
{ $_ -eq 'off' -or $_ -eq 'none' -or $_ -eq '0' -or $_ -eq 'false' } { $rs0 = 'off' }; 'c' { $rs0 = 'concise' }; 'd' { $rs0 = 'detailed' }; 'a' { $rs0 = 'auto' }
}
switch ($rs0) {
{ $_ -eq 'off' -or $_ -eq 'concise' -or $_ -eq 'detailed' -or $_ -eq 'auto' } { $global:REASONING_SUMMARY = $rs0 }
default { err 'Usage: /reasoning [auto|concise|detailed|off]'; return $true }
}
}
info ('Reasoning summaries: ' + $REASONING_SUMMARY); return $true
}
'^/endpoint(\s+|$)' {
$ep = $c1 -replace '^/endpoint *', ''; if ($ep) {
$env:AGENT_ENDPOINT = $ep.TrimEnd('/'); info ('Endpoint: ' + $env:AGENT_ENDPOINT)
} else {
if ($env:AGENT_ENDPOINT) { info ('Endpoint: ' + $env:AGENT_ENDPOINT) } else { info 'Endpoint: default (provider API)' }
}
return $true
}
'^/flush$' {
$global:MSGS = ''; if ($HISTORY) {
$dir = Split-Path -Parent $HISTORY; if ($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
Pu-WriteAllText $HISTORY '[]'; Remove-Item -LiteralPath ($HISTORY + '.meta') -ErrorAction SilentlyContinue
}
if ($LOG) {
$dir = Split-Path -Parent $LOG; if ($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
Pu-WriteAllText $LOG ''
}
info 'Flushed conversation memory and event log'; return $true
}
'^/quit$|^/exit$' { exit 0 }; '^/login$' { _setup; return $true }; '^/logout$' {
$ep0 = Join-Path (Pu-HomeDir) '.pu.env'; if (Test-Path -LiteralPath $ep0) { Remove-Item -LiteralPath $ep0; info 'Removed ~/.pu.env' }
else { info 'No ~/.pu.env to remove' }; Remove-Item Env:ANTHROPIC_API_KEY -ErrorAction SilentlyContinue; Remove-Item Env:OPENAI_API_KEY -ErrorAction SilentlyContinue
info 'Logged out. /login or set env vars to continue.'; return $true
}
'^/compact(\s+|$)' {
$foc = $c1 -replace '^/compact *', ''; $global:MSGS = trim_context $MSGS $foc; save; info ('Compacted (' + $MSGS.Length + 'b)'); return $true
}
'^/export(\s+|$)' {
_export ($c1 -replace '^/export *', ''); return $true
}
'^/skill:' {
_skill ($c1 -replace '^/skill:', ''); return $true
}
'^/session$' {
info ('Log: ' + $LOG + ' | Model: ' + $MODEL + ' (' + $PROVIDER + ') | Max steps: ' + $MAX_STEPS); return $true
}
'^/' {
$cn = ($c1.Substring(1) -split ' ')[0]; $tp = _tpl $cn; if ($tp -ne $cn) {
info ('Template: ' + $cn); run_task $tp; return $true
}
err ('Unknown command: ' + $c1); return $true
}
default { return $false }
}
}
function Global:_prompt_redraw([string]$s) {
Pu-ErrWrite ("`r$ESC[K$ESC[36m> $ESC[0m" + $s)
}
function Global:_read_line {
try { return $host.UI.ReadLine() } catch { return [Console]::In.ReadLine() }
}
function Global:_prompt_read {
Pu-ErrWrite ("$ESC[36m> $ESC[0m"); if (_stdin_is_console) {
$line = _read_line
} else {
$line = _raw_nextline
}
if ($null -eq $line) { return $false }; $global:UPIN = $line.Trim(); return $true
}
if ($MyInvocation.InvocationName -and $MyInvocation.InvocationName -ne '.') {
$script:ARGS = @($args); $script:TA = @(); $si = 0
while ($si -lt $script:ARGS.Count) {
$a = [string]$script:ARGS[$si]; if ($a -eq '-h') {
Write-Output 'pu-unminified.ps1: readable educational build of pu.sh / pu.ps1 (pure PowerShell 5.1, no deps)'; Write-Output 'Usage: .\pu-unminified.ps1 "task" | .\pu-unminified.ps1 (interactive) | --pipe | --cost | -v'; Write-Output 'Env: ANTHROPIC_API_KEY OPENAI_API_KEY AGENT_MODEL AGENT_PROVIDER AGENT_ENDPOINT AGENT_SYSTEM AGENT_MAX_STEPS AGENT_MAX_TOKENS AGENT_LOG AGENT_CONFIRM AGENT_VERBOSE AGENT_REASONING_SUMMARY AGENT_CONTEXT_LIMIT AGENT_RESERVE AGENT_TOOL_TRUNC AGENT_READ_MAX AGENT_LOG_TRUNC AGENT_HISTORY AGENT_THINKING/AGENT_EFFORT AGENT_PRICE_* ~/.pu.env'; Write-Output '7 tools, multi-turn, retries, JSONL logging, pipe mode, !command; auto-compaction summarizes older turns; /compact [focus] runs it manually.'
exit 0
} elseif ($a -eq '-v') {
Write-Output ($(Split-Path -Leaf $MyInvocation.MyCommand.Path) + ' 0.1.0'); exit 0
} elseif ($a -eq '--pipe' -or $a -eq '-p') {
$global:PIPE = 1
} elseif ($a -eq '--cost') {
$global:COST = 1
} elseif ($a -eq '-i') {
$global:INTERACTIVE = 1
} elseif ($a -eq '-n' -or $a -eq '--no-interactive') {
$global:INTERACTIVE = -1
} else {
$script:TA += $a
}
$si++
}
$script:ARGS = @($script:TA); $global:RUNSH = (Get-Process -Id $PID).Path; if (-not ('PuStdIn' -as [type])) {
Add-Type -TypeDefinition 'using System; using System.Runtime.InteropServices; public static class PuStdIn { [DllImport("kernel32.dll", SetLastError=true)] public static extern IntPtr GetStdHandle(int n); [DllImport("kernel32.dll")] public static extern int GetFileType(IntPtr h); [DllImport("kernel32.dll", SetLastError=true)] public static extern bool SetFilePointerEx(IntPtr h, long d, out long n, int m); [DllImport("kernel32.dll", SetLastError=true)] public static extern bool PeekNamedPipe(IntPtr h, byte[] buf, uint n, out uint r, out uint avail, out uint left); [DllImport("kernel32.dll", SetLastError=true)] public static extern bool ReadFile(IntPtr h, [Out] byte[] buf, uint n, out uint r, IntPtr o); [DllImport("kernel32.dll")] public static extern bool GetConsoleMode(IntPtr h, out uint mode); }' -ErrorAction Stop
}
function Global:_stdin_is_console {
try { $md = [uint32]0; [PuStdIn]::GetConsoleMode([PuStdIn]::GetStdHandle(-10), [ref]$md) } catch { $false }
}
function Global:_read_stdin {
try {
if (_stdin_is_console) { return '' }; $h = [PuStdIn]::GetStdHandle(-10); $t = [PuStdIn]::GetFileType($h)
if ($t -eq 1) { $np = 0L; [void][PuStdIn]::SetFilePointerEx($h, 0, [ref]$np, 0) }
$fs = New-Object System.IO.FileStream((New-Object Microsoft.Win32.SafeHandles.SafeFileHandle($h, $false)), [System.IO.FileAccess]::Read)
$sr = New-Object System.IO.StreamReader($fs); return $sr.ReadToEnd()
} catch { return '' }
}
function Global:_read_pending {
try {
$sb = New-Object System.Text.StringBuilder; for ($i = 0; $i -lt 12; $i++) {
$hp = [PuStdIn]::GetStdHandle(-10); $rpd = [uint32]0; $apd = [uint32]0; $lpd = [uint32]0
if (-not [PuStdIn]::PeekNamedPipe($hp, $null, 0, [ref]$rpd, [ref]$apd, [ref]$lpd)) { break }; if ($apd -le 0) { break }; $bb = New-Object byte[] $apd; $nr = [uint32]0
if (-not [PuStdIn]::ReadFile($hp, $bb, $apd, [ref]$nr, [IntPtr]::Zero)) { break }
if ($script:RAW_DEC -eq $null) { $script:RAW_DEC = (New-Object System.Text.UTF8Encoding($false, $false)).GetDecoder() }
$null = $sb.Append($script:RAW_DEC.GetString($bb, 0, [int]$nr)); Start-Sleep -Milliseconds 40
}
return $sb.ToString()
} catch { return '' }
}
function Global:_raw_nextline {
if ($script:RAW_NOPEEK) {
$cl = _read_line; if ($null -eq $cl) { return $null }; return $cl.Trim()
}
if ($script:RAW_BUF -and $script:RAW_BUF.Contains("`n")) {
$i = $script:RAW_BUF.IndexOf("`n"); $ln = $script:RAW_BUF.Substring(0, $i).Replace("`r", ''); $script:RAW_BUF = $script:RAW_BUF.Substring($i + 1); return $ln
}
for ($tries = 0; $tries -lt 400; $tries++) {
try {
$hn = [PuStdIn]::GetStdHandle(-10); $rn = [uint32]0; $an = [uint32]0; $ln = [uint32]0
if (-not [PuStdIn]::PeekNamedPipe($hn, $null, 0, [ref]$rn, [ref]$an, [ref]$ln)) { return $null }; if ($an -gt 0) {
$bb = New-Object byte[] $an; $nr = [uint32]0; if (-not [PuStdIn]::ReadFile($hn, $bb, $an, [ref]$nr, [IntPtr]::Zero)) { return $null }
if ($script:RAW_DEC -eq $null) { $script:RAW_DEC = (New-Object System.Text.UTF8Encoding($false, $false)).GetDecoder() }
$script:RAW_BUF += $script:RAW_DEC.GetString($bb, 0, [int]$nr); if ($script:RAW_BUF.Contains("`n")) {
$i = $script:RAW_BUF.IndexOf("`n"); $ln2 = $script:RAW_BUF.Substring(0, $i).Replace("`r", ''); $script:RAW_BUF = $script:RAW_BUF.Substring($i + 1); return $ln2
}
continue
}
Start-Sleep -Milliseconds 25
} catch {
$script:RAW_NOPEEK = $true; $cl = [Console]::In.ReadLine(); if ($null -eq $cl) { return $null }; return $cl.Trim()
}
}
return $null
}
$global:TASK = ''; $stdinTty = _stdin_is_console; if ($global:PIPE -eq 1 -and -not $stdinTty) {
$global:IN = _read_stdin; if ($script:ARGS.Count -gt 0) {
$global:TASK = $(if ($IN) { $IN + "`n" + ($script:ARGS -join ' ') } else { $script:ARGS -join ' ' })
} else {
$global:TASK = $IN
}
} elseif ($script:ARGS.Count -gt 0) {
$global:TASK = $script:ARGS -join ' '
} elseif (-not $stdinTty) {
$ft = 2; $h0 = [IntPtr]::Zero; try { $h0 = [PuStdIn]::GetStdHandle(-10); $ft = [PuStdIn]::GetFileType($h0) } catch { $script:RAW_NOPEEK = $true }; if ($ft -eq 3) {
$rd = [uint32]0; $av = [uint32]0; $lf = [uint32]0; $pk = $false
try { $pk = [PuStdIn]::PeekNamedPipe($h0, $null, 0, [ref]$rd, [ref]$av, [ref]$lf) } catch { $script:RAW_NOPEEK = $true }; if ($pk -and $av -eq 0) {
if ($global:INTERACTIVE -ne -1) { $global:INTERACTIVE = 1 }
} else {
$pending = _read_pending; if ($pending -ne '') {
$nonEmpty = @($pending.Split("`n") | Where-Object { $_.Trim() -ne '' }); $allCmd = $nonEmpty.Count -gt 0
foreach ($pc in $nonEmpty) { if ($pc -notmatch '^/') { $allCmd = $false; break } }
if ($allCmd) { $script:RAW_BUF = $pending; if ($global:INTERACTIVE -ne -1) { $global:INTERACTIVE = 1 } }
else { $global:TASK = $pending }
} elseif ($global:INTERACTIVE -ne -1) { $global:INTERACTIVE = 1 }
}
} elseif ($ft -eq 2) {
if ($global:INTERACTIVE -ne -1) { $global:INTERACTIVE = 1 }
} else {
$inStd = _read_stdin; if ($inStd -ne '') {
$nonEmpty = @($inStd.Split("`n") | Where-Object { $_.Trim() -ne '' }); $allCmd = $nonEmpty.Count -gt 0
foreach ($pc in $nonEmpty) { if ($pc -notmatch '^/') { $allCmd = $false; break } }
if ($allCmd) { $script:RAW_BUF = $inStd; if ($global:INTERACTIVE -ne -1) { $global:INTERACTIVE = 1 } }
else { $global:TASK = $inStd }
} elseif ($global:INTERACTIVE -ne -1) { $global:INTERACTIVE = 1 }
}
}
if (-not $TASK -and $stdinTty -and $INTERACTIVE -ne -1) { $global:INTERACTIVE = 1 }; if (-not $TASK -and $INTERACTIVE -ne 1) {
err 'No task. Usage: .\pu-unminified.ps1 "task" or .\pu-unminified.ps1 -i'; exit 1
}
$null = _ensure_key; if (-not (Test-Path Env:ANTHROPIC_API_KEY) -and -not (Test-Path Env:OPENAI_API_KEY)) {
if ($PROVIDER -eq 'anthropic' -and -not $env:ANTHROPIC_API_KEY) { exit 1 }; if ($PROVIDER -eq 'openai' -and -not $env:OPENAI_API_KEY) { exit 1 }
}
load_context; if (-not $MSGS) {
$r = load; if ($r) { _replay; info ('Resumed memory: ' + $HISTORY + ' (/flush to clear)') }
}
if ($TASK) {
info $TASK; info ($MODEL + ' (' + $PROVIDER + ') max steps: ' + $MAX_STEPS); $global:PROMPT_LAST_INPUT = $TASK; $rrc = run_task $TASK; if ($INTERACTIVE -ne 1) { exit $rrc }
}
info ($MODEL + ' (' + $PROVIDER + ') | /model /effort /reasoning /login /logout /flush /compact /export /skill:name /quit | !cmd')
while ($true) {
$global:_STATE = 'idle'; if (-not (_prompt_read)) { break }; if ($UPIN -eq 'quit' -or $UPIN -eq 'exit' -or $UPIN -eq 'q') { break }
if ($UPIN -eq '' -or $UPIN -eq ' ') { continue }; if (handle_cmd $UPIN) { continue }; $global:PROMPT_LAST_INPUT = $UPIN; run_task $UPIN
}
}
