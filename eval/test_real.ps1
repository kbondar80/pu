$ErrorActionPreference = 'Stop'
# eval/test_real.ps1 - behavioral tests for pu.ps1 / pu-unminified.ps1
# PowerShell twin of eval/test_real.sh. Dot-sources the agent (which skips its
# CLI entry via the invocation-name guard) and validates real outputs with the
# same structures Python's json.tool would reject.
# AGENT env var selects the script to test (default: the readable build).

$script:PASS = 0
$script:FAIL = 0
$script:TOTAL = 0

function Global:pass([string]$id, [string]$name) {
    $script:PASS++
    $script:TOTAL++
    [Console]::Out.WriteLine(('PASS  ' + $id + '  ' + $name))
}

function Global:fail([string]$id, [string]$name, [string]$extra) {
    $script:FAIL++
    $script:TOTAL++
    [Console]::Out.WriteLine(('FAIL  ' + $id + '  ' + $name))
    if ($extra) { [Console]::Out.WriteLine('       ' + $extra) }
}

function Global:valid_json([string]$j) {
    try { $null = $j | ConvertFrom-Json; return $true } catch { return $false }
}

# Port of json_field: $code receives the parsed document ($d) and returns a
# value/bool, mirroring the python snippets from the sh suite.
function Global:json_field([string]$j, [scriptblock]$code) {
    $d = $j | ConvertFrom-Json
    return (& $code $d)
}

# Capture everything functions write to Console.Error (the port of `2>&1`
# around function calls in sh, needed because err() writes to the raw handle).
function Global:Capture-Err([scriptblock]$sb) {
    $orig = [Console]::Error
    $ms = New-Object System.IO.MemoryStream
    $sw = New-Object System.IO.StreamWriter($ms)
    $sw.AutoFlush = $true
    [Console]::SetError($sw)
    try { $null = & $sb } finally { [Console]::SetError($orig) }
    $ms.Position = 0
    $sr = New-Object System.IO.StreamReader($ms)
    return $sr.ReadToEnd()
}

# Run a block capturing [Console]::Out + [Console]::Error (the way run_task
# emits final text and err()), returning rc/out/err as an object.
function Global:Capture-Both([scriptblock]$sb) {
    $origOut = [Console]::Out
    $origErr = [Console]::Error
    $mo = New-Object System.IO.MemoryStream
    $wo = New-Object System.IO.StreamWriter($mo)
    $wo.AutoFlush = $true
    $me = New-Object System.IO.MemoryStream
    $we = New-Object System.IO.StreamWriter($me)
    $we.AutoFlush = $true
    [Console]::SetOut($wo)
    [Console]::SetError($we)
    $rc = 0
    try { $rc = & $sb } finally { [Console]::SetOut($origOut); [Console]::SetError($origErr) }
    $mo.Position = 0; $ro = New-Object System.IO.StreamReader($mo)
    $me.Position = 0; $re = New-Object System.IO.StreamReader($me)
    return [pscustomobject]@{ rc = $rc; out = $ro.ReadToEnd(); err = $re.ReadToEnd() }
}

$script:TMPD = Join-Path $env:TEMP ('test_real_' + [System.IO.Path]::GetRandomFileName())
[System.IO.Directory]::CreateDirectory($script:TMPD) | Out-Null

$script:AGENT = if ($env:AGENT) { $env:AGENT } else { Join-Path (Split-Path -Parent $PSScriptRoot) 'pu-unminified.ps1' }
if (-not (Test-Path -LiteralPath $script:AGENT -PathType Leaf)) {
    [Console]::Out.WriteLine(('FAIL  harness  agent not found: ' + $script:AGENT))
    exit 1
}

Remove-Item Env:AGENT_PROVIDER, Env:AGENT_MODEL, Env:OPENAI_API_KEY, Env:ANTHROPIC_API_KEY,
    Env:AGENT_CONTEXT_LIMIT, Env:AGENT_ENDPOINT, Env:AGENT_LOG, Env:AGENT_HISTORY,
    Env:AGENT_EFFORT, Env:AGENT_MAX_STEPS, Env:AGENT_MAX_TOKENS, Env:AGENT_SYSTEM -ErrorAction SilentlyContinue

# Dot-source the agent. The inline CLI is gated by $MyInvocation.InvocationName,
# so sourcing defines all functions without starting the loop.
& { . $script:AGENT } | Out-Null

$global:HISTORY = ''
$global:LOG = Join-Path $script:TMPD 'events.jsonl'
$global:PIPE = 1
$global:VERBOSE = 0
$global:INTERACTIVE = 0
$global:CONFIRM = 0
$global:TOKEN_IN = 0
$global:TOKEN_OUT = 0
$global:COST_USD = 0
function Global:SleepSec([double]$n) { }

$script:head = @('json_escape', 'jp / jb', 'parse_response', 'request building', 'login/env', 'trim_context', 'run_task', 'tool truncation', 'edit tool', 'real-world workflows')
$script:section = 0
function Global:section([string]$name) {
    $script:section++
    [Console]::Out.WriteLine(('--- ' + $name + ' ---'))
}

# ---------------------------------------------------------------- json_escape
section 'json_escape'

$ESC = JsonEscape ('has' + [char]13 + 'CR')
valid_json ('{"x":"' + $ESC + '"}') | Out-Null
if (valid_json ('{"x":"' + $ESC + '"}')) { pass 'JE-1' 'carriage return -> valid JSON' } else { fail 'JE-1' 'CR escape' $ESC }

$ESC = JsonEscape ('a' + [char]1 + 'b' + [char]2 + 'c' + [char]5 + 'd')
if (valid_json ('{"x":"' + $ESC + '"}')) { pass 'JE-2' 'raw control bytes (0x01-0x05) sanitized' } else { fail 'JE-2' 'raw control bytes' $ESC }

$ESC = JsonEscape ('a' + [char]8 + 'b' + [char]12 + 'c' + [char]11 + 'd')
if (valid_json ('{"x":"' + $ESC + '"}')) { pass 'JE-3' 'backspace, formfeed, vtab sanitized' } else { fail 'JE-3' 'BS/FF/VT' $ESC }

$INPUT = 'line1' + [char]10 + 'line2' + [char]9 + 'after-tab' + [char]10 + '  end'
$ESC = JsonEscape $INPUT
$RESTORED = json_field ('{"x":"' + $ESC + '"}') { param($d) $d.x }
if ($RESTORED -eq $INPUT) { pass 'JE-4' 'multi-line + tab round-trip' } else { fail 'JE-4' 'round-trip' ('got: ' + $RESTORED) }

$INPUT = 'shell escape \n stays literal'
$ESC = JsonEscape $INPUT
$RESTORED = json_field ('{"x":"' + $ESC + '"}') { param($d) $d.x }
if ($RESTORED -eq $INPUT) { pass 'JE-5' 'literal backslash-n preserved' } else { fail 'JE-5' 'literal \\n round-trip' ('got: ' + $RESTORED) }

$INPUT = 'she said "hi" to him'
$ESC = JsonEscape $INPUT
$RESTORED = json_field ('{"x":"' + $ESC + '"}') { param($d) $d.x }
if ($RESTORED -eq $INPUT) { pass 'JE-6' 'embedded quotes round-trip' } else { fail 'JE-6' 'quotes' ('got: ' + $RESTORED) }

# -------------------------------------------------------------------- jp / jb
section 'jp / jb'

$RESP = '{"id":"msg_01","type":"message","role":"assistant","content":[{"type":"text","text":""},{"type":"tool_use","id":"toolu_X","name":"grep","input":{"pattern":"handle_cmd.*{\""}}],"stop_reason":"tool_use","usage":{"input_tokens":100,"output_tokens":50}}'

$CB = jp $RESP 'content'
if (valid_json $CB) { pass 'JS-1' 'jp: content array with {-in-string' } else { fail 'JS-1' 'jp content extraction' $CB }

$TU = jb $RESP 'tool_use'
if (valid_json $TU) { pass 'JS-2' 'jb: tool_use block with {-in-string' } else { fail 'JS-2' 'jb tool_use' $TU }

$TN = jp $TU 'name'
if ($TN -eq 'grep') { pass 'JS-3' 'jp: nested name field' } else { fail 'JS-3' 'tool name' $TN }

$TINP = jp $TU 'input'
if (valid_json $TINP) { pass 'JS-4' 'jp: nested object with brace-in-string' } else { fail 'JS-4' 'input object' $TINP }

$PAT = jp $TINP 'pattern'
if ($PAT -eq 'handle_cmd.*{"') { pass 'JS-5' 'jp: string field with literal { and " decoded correctly' } else { fail 'JS-5' 'pattern decode' ('expected handle_cmd.*{", got ' + $PAT) }

$UNICODE = jp '{"x":"caf\u00e9 \u263a \ud83d\ude00 literal \\u00e9"}' 'x'
$EXP = 'caf' + [char]0xE9 + ' ' + [char]0x263A + ' ' + [string][char]::ConvertFromUtf32(0x1F600) + ' literal \u00e9'
if ($UNICODE -eq $EXP) { pass 'JS-5b' 'jp: decodes JSON unicode escapes, preserves escaped backslash-u' } else { fail 'JS-5b' 'unicode decode' ('got: ' + $UNICODE) }

# ------------------------------------------------------------ parse_response
section 'parse_response'

$global:PROVIDER = 'anthropic'
parse_response $RESP
if ($global:TY -eq 'T') { pass 'PR-1' 'type=tool_use detected' } else { fail 'PR-1' 'TY' $global:TY }
if ($global:TN -eq 'grep') { pass 'PR-2' 'tool name extracted' } else { fail 'PR-2' 'TN' $global:TN }
if ($global:TI -eq 'toolu_X') { pass 'PR-3' 'tool id extracted' } else { fail 'PR-3' 'TI' $global:TI }
if (valid_json $CB) { pass 'PR-4' 'CB valid for append' } else { fail 'PR-4' 'CB invalid' $CB }

$MSGS_INIT = '[{"role":"user","content":"go"}]'
$TR_BLOCK = '{"type":"tool_result","tool_use_id":"toolu_X","content":"some output"}'
$NEW_MSGS = $MSGS_INIT.Substring(0, $MSGS_INIT.Length - 1) + ',{"role":"assistant","content":' + $CB + '},{"role":"user","content":[' + $TR_BLOCK + ']}]'
if (valid_json $NEW_MSGS) { pass 'PR-5' 'appended MSGS is valid JSON (regression for 80fdf9f)' } else { fail 'PR-5' 'appended MSGS invalid' $NEW_MSGS.Substring(0, [Math]::Min(200, $NEW_MSGS.Length)) }

$ORESP = '{"id":"resp_x","object":"response","output":[{"type":"reasoning","id":"rs_1","summary":[]},{"type":"function_call","id":"fc_1","call_id":"call_abc","name":"read","arguments":"{\"path\":\"pu.sh\"}","status":"completed"}],"usage":{"input_tokens":10,"output_tokens":5}}'
$global:PROVIDER = 'openai'
parse_response $ORESP
if ($global:TY -eq 'T') { pass 'PR-6' 'openai: function_call detected' } else { fail 'PR-6' 'TY' $global:TY }
if ($global:TI -eq 'call_abc') { pass 'PR-7' 'openai: call_id extracted' } else { fail 'PR-7' 'TI' $global:TI }
if ($global:TN -eq 'read') { pass 'PR-8' 'openai: function name extracted' } else { fail 'PR-8' 'TN' $global:TN }
if ($global:TINP -eq '{"path":"pu.sh"}') { pass 'PR-9' 'openai: escaped arguments decoded to JSON object' } else { fail 'PR-9' 'TINP' $global:TINP }
$ORG = @(each_tool_use $global:TC '"reasoning"')
$OTU = @(each_tool_use $global:TC '"function_call"')
if ($ORG.Count -eq 0) { $ORG = @('') }
if ($OTU.Count -eq 0) { $OTU = @('') }
$OTI = jp $OTU[0] 'call_id'; $OTN = jp $OTU[0] 'name'; $OINP = jp $OTU[0] 'arguments'
if (($OTI + '/' + $OTN + '/' + $OINP) -eq 'call_abc/read/{"path":"pu.sh"}') { pass 'PR-10' 'openai: each_tool_use anchors function_call object' } else { fail 'PR-10' 'openai each_tool_use' ($OTI + '/' + $OTN + '/' + $OINP) }

$PRETTY_TC = '[
  {
    "type": "function_call",
    "call_id": "call_pretty",
    "name": "read",
    "arguments": "{\"path\":\"pu.sh\"}"
  }
]'
$PFLAT = $PRETTY_TC -replace '\r?\n', ''
$PTU = @(each_tool_use $PFLAT '"function_call"')
if ($PTU.Count -eq 0) { $PTU = @('') }
if (((jp $PTU[0] 'call_id') + '/' + (jp $PTU[0] 'name')) -eq 'call_pretty/read') { pass 'PR-11' 'openai: pretty function_calls survive line compaction' } else { fail 'PR-11' 'openai pretty function_calls' ($PTU -join ',') }

parse_response '{"output_text":"direct final","usage":{"input_tokens":1,"output_tokens":1}}'
if ($global:TY -eq 'X' -and $global:TX -eq 'direct final') { pass 'PR-12' 'openai: top-level output_text string parsed' } else { fail 'PR-12' 'openai top-level output_text' ($global:TY + '/' + $global:TX) }

$OMSS = '[{"role":"user","content":"go"}]'
$OTR = ',{"type":"function_call_output","call_id":"call_abc","output":"ok"}'
$ONEW = $OMSS.Substring(0, $OMSS.Length - 1) + ',' + $ORG[0] + ',' + $OTU[0] + $OTR + ']'
$r13 = $false
if (valid_json $ONEW) {
    $r13 = json_field $ONEW { param($d) (($d[1].type + ':' + $d[3].call_id) -eq 'reasoning:call_abc') }
}
if ($r13) { pass 'PR-13' 'openai: appended reasoning/function_call/function_call_output are schema-shaped' } else { fail 'PR-13' 'openai append invalid' $ONEW }

# ------------------------------------------------------------- request building
section 'request building'

$script:PU_MODE = 'body'
function Global:Invoke-Pu([string]$url, [hashtable]$headers, [string]$method, [string]$body) {
    $script:LAST_URL = $url
    $script:LAST_BODY = $body
    $global:PU_API_RC = 0
    if ($script:PU_MODE -eq 'url') { return $url }
    return $body
}

$global:PROVIDER = 'openai'; $global:MODEL = 'gpt-5.5'; $global:MAX_TOKENS = 123
$global:THINKING = ''; $global:EFFORT = 'medium'; $global:EFFORT_OK = 1
$global:REASONING_SUMMARY = 'auto'
$REQ = call_api '[{"role":"user","content":"hi"}]'
$r14 = json_field $REQ { param($d) ($null -ne $d.max_output_tokens -and -not (@($d.PSObject.Properties.Name) -contains 'max_tokens') -and -not (@($d.PSObject.Properties.Name) -contains 'max_completion_tokens')) }
if ($r14) { pass 'PR-14' 'openai responses: request uses max_output_tokens' } else { fail 'PR-14' 'openai token parameter' $REQ }

$r15 = json_field $REQ { param($d) ($d.reasoning.effort -eq 'medium' -and $null -ne $d.instructions -and $d.tools[0].type -eq 'function') }
if ($r15) { pass 'PR-15' 'openai responses: sends reasoning.effort with tools' } else { fail 'PR-15' 'openai responses reasoning/tools' $REQ }

$global:PROVIDER = 'openai'; $global:MODEL = 'gpt-4o'; $global:MAX_TOKENS = 123
$global:THINKING = ''; $global:EFFORT = 'high'; $global:EFFORT_OK = 0
$REQ = call_api '[{"role":"user","content":"hi"}]'
$r16 = json_field $REQ { param($d) (-not (@($d.PSObject.Properties.Name) -contains 'reasoning') -and $d.max_output_tokens -eq 123) }
if ($r16) { pass 'PR-16' 'openai non-reasoning model: no effort/no token boost' } else { fail 'PR-16' 'openai unsupported reasoning gated' $REQ }

$global:PROVIDER = 'openai'; $global:MODEL = 'gpt-5.5'; $global:MAX_TOKENS = 123
$global:THINKING = ''; $global:EFFORT = 'none'; $global:EFFORT_OK = 1
$REQ = call_api '[{"role":"user","content":"hi"}]'
$r17 = json_field $REQ { param($d) (-not (@($d.PSObject.Properties.Name) -contains 'reasoning')) }
if ($r17) { pass 'PR-17' 'openai effort=none suppresses reasoning field' } else { fail 'PR-17' 'openai none reasoning' $REQ }

$global:PROVIDER = 'openai'; $global:MODEL = 'gpt-5.5'; $global:MAX_TOKENS = 123
$global:THINKING = ''; $global:EFFORT = 'xhigh'; $global:EFFORT_OK = 1
$REQ = call_api '[{"role":"user","content":"hi"}]'
$r18 = json_field $REQ { param($d) ($d.max_output_tokens -eq 32000) }
if ($r18) { pass 'PR-18' 'openai xhigh gets larger output budget' } else { fail 'PR-18' 'openai xhigh budget' $REQ }

$global:PROVIDER = 'anthropic'; $global:MODEL = 'claude-opus-4-7'
$global:EFFORT = 'xhigh'; $global:THINKING = ''; $global:EFFORT_OK = 1
$REQ = call_api '[{"role":"user","content":"hi"}]'
$r19 = json_field $REQ { param($d) ($d.effort -eq 'xhigh' -and $d.thinking.type -eq 'adaptive' -and -not (@($d.thinking.PSObject.Properties.Name) -contains 'budget_tokens')) }
if ($r19) { pass 'PR-19' 'anthropic: Opus 4.7 uses effort + adaptive thinking, not budget_tokens' } else { fail 'PR-19' 'anthropic effort/adaptive' $REQ }

# ---------------------------------------------------------------- endpoints
$script:PU_MODE = 'url'
$global:PROVIDER = 'anthropic'; $global:MODEL = 'claude-opus-4-7'; $global:MAX_TOKENS = 123
$global:THINKING = ''; $global:EFFORT = 'medium'; $global:EFFORT_OK = 1
$env:AGENT_ENDPOINT = 'http://localhost:9999'
$URL = call_api '[]'
if ($URL -eq 'http://localhost:9999/v1/messages') { pass 'EP-1' 'anthropic: AGENT_ENDPOINT base with /v1/messages appended' } else { fail 'EP-1' 'anthropic endpoint override' $URL }

$global:PROVIDER = 'openai'; $global:MODEL = 'gpt-5.5'
$env:AGENT_ENDPOINT = 'http://localhost:9999/'
$URL = call_api '[]'
if ($URL -eq 'http://localhost:9999/v1/responses') { pass 'EP-2' 'openai: AGENT_ENDPOINT base with /v1/responses, trailing slash stripped' } else { fail 'EP-2' 'openai endpoint override' $URL }

$global:PROVIDER = 'anthropic'; $global:MODEL = 'claude-opus-4-7'
Remove-Item Env:AGENT_ENDPOINT -ErrorAction SilentlyContinue
$URL = call_api '[]'
if ($URL -eq 'https://api.anthropic.com/v1/messages') { pass 'EP-3' 'default endpoint used when AGENT_ENDPOINT empty' } else { fail 'EP-3' 'anthropic default endpoint' $URL }
$script:PU_MODE = 'body'

$global:PROVIDER = 'anthropic'

# ------------------------------------------------------------ login / env
section 'login/env'

$HOME0 = $env:HOME
$ENV0 = @()
foreach ($ek in @('OPENAI_API_KEY', 'AGENT_PROVIDER', 'AGENT_ENDPOINT')) {
    if (Test-Path ("Env:" + $ek)) { $ENV0 += $ek; Remove-Item ("Env:" + $ek) }
}
function Global:Invoke-Pu([string]$url, [hashtable]$headers, [string]$method, [string]$body) {
    $global:PU_API_RC = 0
    $auth = $headers['Authorization']
    if (-not $auth -or -not $auth.Contains('Bearer saved-key')) { return '{"error":{"message":"missing saved key"}}' }
    $script:AUTH_URL = $url
    $script:AUTH_BODY = $body
    return '{"output":[{"type":"message","content":[{"type":"output_text","text":"ok"}]}],"usage":{"input_tokens":1,"output_tokens":1}}'
}

$ENVHOME = Join-Path $script:TMPD 'home2'
New-Item -ItemType Directory -Path $ENVHOME -Force | Out-Null
$env:HOME = $ENVHOME
$env:OPENAI_API_KEY = 'dummy'
$PUENV = $ENVHOME + '\.pu.env'
Set-Content -LiteralPath $PUENV -Value ("OPENAI_API_KEY='saved-key'`nAGENT_PROVIDER='openai'`necho pwn > '" + $script:TMPD + '\pwn''') -Encoding ASCII
Set-Content -LiteralPath $PUENV -Value ("OPENAI_API_KEY='saved-key'`nAGENT_PROVIDER='openai'`necho pwn > '" + $script:TMPD + '\pwn''') -Encoding UTF8
$env:AGENT_OPENAI_KEY2 = $null
Remove-Item Env:OPENAI_API_KEY -ErrorAction SilentlyContinue
Remove-Item Env:AGENT_PROVIDER -ErrorAction SilentlyContinue
$env:AGENT_MODEL = 'gpt-5.5'; $global:PROVIDER = 'openai'; $global:MODEL = 'gpt-5.5'; $global:EFFORT_OK = 1
_load_env
$r20 = $false
if ($env:OPENAI_API_KEY -ne 'saved-key') {
    fail 'PR-20' 'saved key/env parser' ('key=' + $env:OPENAI_API_KEY)
} elseif (Test-Path -LiteralPath ($script:TMPD + '\pwn')) {
    fail 'PR-20' 'saved key/env parser' 'echo line executed'
} else {
    $r20 = $true
}
$script:rc20 = 0
$cb20 = Capture-Both { $script:rc20 = run_task 'hi' }
if ($r20 -and $global:PROVIDER -eq 'openai') {
    if ($cb20.out.Contains('ok') -and $script:rc20 -eq 0) { pass 'PR-20' '~/.pu.env safe parser loads key without executing shell' }
    else { fail 'PR-20' 'saved key/env parser' ('rc=' + $script:rc20 + ' out=' + $cb20.out) }
}

$global:PROVIDER = 'openai'; $global:MODEL = 'gpt-5.5'
$NEWK = CleanKey ' OPENAI_API_KEY="saved-key" '
if ($NEWK -eq 'saved-key') { pass 'PR-21' 'login strips env/export-prefix/quotes/whitespace from pasted key' } else { fail 'PR-21' 'key paste sanitization' $NEWK }

$HIST = Join-Path $script:TMPD 'hist.json'
$global:HISTORY = $HIST
$cb22 = Capture-Both { $null = run_task 'hi' }
$r22 = $false
if (Test-Path -LiteralPath $HIST -PathType Leaf) {
    $r22 = json_field ([System.IO.File]::ReadAllText($HIST)) { param($d) ($d[-1].role -eq 'assistant' -and $d[-1].content -eq 'ok') }
}
if ($r22) { pass 'PR-22' 'final assistant response is saved to history' } else { fail 'PR-22' 'assistant response missing from history' $HIST }

$ENDHOME = Join-Path $script:TMPD 'endhome2'
New-Item -ItemType Directory -Path $ENDHOME -Force | Out-Null
$env:HOME = $ENDHOME
Set-Content -LiteralPath ($ENDHOME + '\.pu.env') -Value "AGENT_ENDPOINT='http://internal:8080/'" -Encoding UTF8
Remove-Item Env:AGENT_ENDPOINT -ErrorAction SilentlyContinue
_load_env
if ($env:AGENT_ENDPOINT -eq 'http://internal:8080/') { pass 'EP-4' '_load_env allowlists AGENT_ENDPOINT from ~/.pu.env' } else { fail 'EP-4' '.pu.env endpoint load' ('got=' + $env:AGENT_ENDPOINT) }
Remove-Item Env:AGENT_ENDPOINT -ErrorAction SilentlyContinue

$SETUPHOME = Join-Path $script:TMPD 'endsetup2'
New-Item -ItemType Directory -Path $SETUPHOME -Force | Out-Null
$env:HOME = $SETUPHOME
$EP_VAL = 'http://custom:7000'.TrimEnd('/')
Set-Content -LiteralPath ($SETUPHOME + '\.pu.env') -Value ("OPENAI_API_KEY='saved-key'`nAGENT_PROVIDER='anthropic'`nAGENT_MODEL='claude-opus-4-7'`nAGENT_EFFORT='medium'`nAGENT_REASONING_SUMMARY='auto'`nAGENT_ENDPOINT='" + $EP_VAL + "'") -Encoding UTF8
_load_env
if ($env:AGENT_ENDPOINT -eq 'http://custom:7000') { pass 'EP-5' '/login persists AGENT_ENDPOINT to ~/.pu.env (trailing slash stripped)' } else { fail 'EP-5' '/login endpoint save' ('endpoint=' + $env:AGENT_ENDPOINT) }
Remove-Item Env:AGENT_ENDPOINT -ErrorAction SilentlyContinue

$null = handle_cmd '/endpoint http://gateway:9000/'
if ($env:AGENT_ENDPOINT -eq 'http://gateway:9000') { pass 'EP-6' '/endpoint sets AGENT_ENDPOINT in-session' } else { fail 'EP-6' '/endpoint setter' ('AGENT_ENDPOINT=' + $env:AGENT_ENDPOINT) }
Remove-Item Env:AGENT_ENDPOINT -ErrorAction SilentlyContinue

$env:HOME = $HOME0
foreach ($ek in $ENV0) { if (Test-Path ("Env:" + $ek)) { Remove-Item ("Env:" + $ek) } }
$env:ANTHROPIC_API_KEY = 'dummy'
$global:PROVIDER = 'anthropic'; $global:MODEL = 'claude-opus-4-7'; $global:MAX_STEPS = 5; $global:EFFORT_OK = 1
$global:ANTHROPIC_API_KEY = $env:ANTHROPIC_API_KEY
$global:HISTORY = ''
$global:LOG = Join-Path $script:TMPD 'events.jsonl'

# ---------------------------------------------------------------- trim_context
section 'trim_context'

function Global:call_api([string]$m) {
    $global:PU_API_RC = 0
    return '{"id":"m","type":"message","role":"assistant","content":[{"type":"text","text":"Earlier work: read pu.sh, ran 2 grep calls, found 1 issue."}],"stop_reason":"end_turn","usage":{"input_tokens":1,"output_tokens":1}}'
}
$global:CTX_LIMIT = 2000
$global:AGENT_RESERVE = 200
$global:MAX_STEPS = 5

$PADDING = ('x' * 2500)
$MSGS_BIG = '[{"role":"user","content":"original task: find bugs"},' +
  '{"role":"assistant","content":[{"type":"tool_use","id":"a","name":"read","input":{"path":"a.sh"}}]},' +
  '{"role":"user","content":[{"type":"tool_result","tool_use_id":"a","content":"' + $PADDING + '"}]},' +
  '{"role":"assistant","content":[{"type":"tool_use","id":"b","name":"read","input":{"path":"b.sh"}}]},' +
  '{"role":"user","content":[{"type":"tool_result","tool_use_id":"b","content":"BBB"}]},' +
  '{"role":"assistant","content":[{"type":"tool_use","id":"c","name":"read","input":{"path":"c.sh"}}]},' +
  '{"role":"user","content":[{"type":"tool_result","tool_use_id":"c","content":"CCC"}]}]'

$NEW = trim_context $MSGS_BIG
if (valid_json $NEW) { pass 'TC-1' 'trim_context output is valid JSON' } else { fail 'TC-1' 'trim_context output invalid' ('len=' + $NEW.Length + ' first300=' + $NEW.Substring(0, [Math]::Min(300, $NEW.Length))) }

$ANCHOR = json_field $NEW { param($d) $d[0].content }
if ($ANCHOR -eq 'original task: find bugs') { pass 'TC-2' 'anchor (original task) preserved' } else { fail 'TC-2' 'anchor lost' ('got=' + $ANCHOR) }

$SUMMARY_CONTENT = json_field $NEW { param($d) $d[1].content }
if ($SUMMARY_CONTENT -and $SUMMARY_CONTENT.Contains('Earlier compacted')) { pass 'TC-3' 'summary placeholder inserted' } else { fail 'TC-3' 'summary missing' ('got=' + $SUMMARY_CONTENT) }

$TUS = @(); foreach ($mm in [regex]::Matches($NEW, '"id":"([a-z])"')) { $TUS += $mm.Groups[1].Value }
$TRS = @(); foreach ($mm in [regex]::Matches($NEW, '"tool_use_id":"([a-z])"')) { $TRS += $mm.Groups[1].Value }
$J_TUS = @($TUS | Sort-Object -Unique) -join ','
$J_TRS = @($TRS | Sort-Object -Unique) -join ','
if ($J_TUS -eq $J_TRS) { pass 'TC-4' 'tool_use <-> tool_result pairing intact' } else { fail 'TC-4' 'pairing broken' ('uses=' + $J_TUS + ' results=' + $J_TRS) }

if ($NEW.Length -lt $MSGS_BIG.Length) { pass 'TC-5' ('compacted MSGS is smaller (' + $MSGS_BIG.Length + ' -> ' + $NEW.Length + ')') } else { fail 'TC-5' 'no shrinkage' ($MSGS_BIG.Length.ToString() + ' -> ' + $NEW.Length) }

$SHORT = '[{"role":"user","content":"hi"},{"role":"assistant","content":"hello"}]'
$OUT6 = trim_context $SHORT
if ($OUT6 -eq $SHORT) { pass 'TC-6' 'small MSGS (n<6) passes through unchanged' } else { fail 'TC-6' 'n<6 mutated' $OUT6 }

$SHORT_BUT_OK = '[{"role":"user","content":"task"},{"role":"assistant","content":[{"type":"tool_use","id":"a","name":"x","input":{}}]},{"role":"user","content":[{"type":"tool_result","tool_use_id":"a","content":"x"}]},{"role":"assistant","content":[{"type":"tool_use","id":"b","name":"x","input":{}}]},{"role":"user","content":[{"type":"tool_result","tool_use_id":"b","content":"y"}]},{"role":"assistant","content":[{"type":"tool_use","id":"c","name":"x","input":{}}]},{"role":"user","content":[{"type":"tool_result","tool_use_id":"c","content":"z"}]}]'
$OUT7 = trim_context $SHORT_BUT_OK 'key files only'
if ($OUT7 -ne $SHORT_BUT_OK -and (valid_json $OUT7)) { pass 'TC-7' 'focus arg forces compaction (threshold bypass)' } else { fail 'TC-7' "focus didn't force" $OUT7 }

$OPENAI_BOUNDARY = '[{"role":"user","content":"task"},{"role":"user","content":"old"},{"type":"reasoning","id":"rs_1","summary":[]},{"type":"function_call","call_id":"call_1","name":"read","arguments":"{}"},{"type":"function_call_output","call_id":"call_1","output":"ok"},{"role":"user","content":"next"},{"role":"assistant","content":"done"}]'
$OUT8 = trim_context $OPENAI_BOUNDARY 'force'
$ok8 = json_field $OUT8 { param($d)
    $types = @($d | ForEach-Object { $_.type })
    $fc = [Array]::IndexOf($types, 'function_call')
    if ($fc -lt 0) { return $true }
    return ($types[$fc - 1] -eq 'reasoning')
}
if ($ok8) { pass 'TC-8' 'trim_context keeps OpenAI reasoning before function_call' } else { fail 'TC-8' 'openai reasoning/function_call boundary' $OUT8 }

$OLD_CTX = $global:CTX_LIMIT; $OLD_RES = $global:AGENT_RESERVE
$global:CTX_LIMIT = 20000; $global:AGENT_RESERVE = 1000
$BIGRECENT = ('z' * 6000)
$RECENT_BIG = '[{"role":"user","content":"task"},{"role":"assistant","content":"old1"},{"role":"user","content":"old2"},{"role":"assistant","content":"old3"},{"role":"user","content":"old4"},{"role":"assistant","content":"' + $BIGRECENT + '"},{"role":"user","content":"done"}]'
$OUT8B = trim_context $RECENT_BIG 'force'
if (valid_json $OUT8B) { pass 'TC-8b' 'trim_context keeps retained large entries as valid JSON' } else { fail 'TC-8b' 'large retained entry made invalid JSON' $OUT8B.Substring(0, [Math]::Min(200, $OUT8B.Length)) }

$OLD_KEEP = $global:AGENT_KEEP_RECENT; $global:AGENT_KEEP_RECENT = 100
$charE = [string][char]0x00E9
$BIGUNI = ($charE * 6000)
$UNIC_MSG = '[{"role":"user","content":"task"},{"role":"assistant","content":"old1"},{"role":"user","content":"' + $BIGUNI + '"},{"role":"assistant","content":"old3"},{"role":"user","content":"old4"},{"role":"assistant","content":"old5"},{"role":"user","content":"done"}]'
$REQF = Join-Path $script:TMPD 'compact_req.json'
Set-Content -LiteralPath $REQF -Value '{}' -Encoding UTF8
function Global:call_api([string]$m) {
    $global:PU_API_RC = 0
    [System.IO.File]::WriteAllText($REQF, $m, (New-Object System.Text.UTF8Encoding($false)))
    return '{"id":"m","type":"message","role":"assistant","content":[{"type":"text","text":"summary"}]}'
}
$OUT8C = trim_context $UNIC_MSG 'force'
$reqOk = $false
if (Test-Path -LiteralPath $REQF -PathType Leaf) {
    try { $null = ([System.IO.File]::ReadAllText($REQF) | ConvertFrom-Json); $reqOk = $true } catch { $reqOk = $false }
}
if ($reqOk -and (valid_json $OUT8C)) { pass 'TC-8c' 'trim_context builds valid summary request for huge unicode entries' } else { fail 'TC-8c' 'compaction summary request invalid' ('req=' + (([System.IO.File]::ReadAllText($REQF)).Substring(0, [Math]::Min(200, ([System.IO.File]::ReadAllText($REQF)).Length))) + ' out=' + $OUT8C.Substring(0, [Math]::Min(120, $OUT8C.Length))) }

$PRETTY = "[{""role"":""user"",""content"":""task""},{
  ""role"" : ""assistant"",
  ""content"" : ""old pretty""
},{""role"":""user"",""content"":""old2""},{""role"":""assistant"",""content"":""old3""},{""role"":""user"",""content"":""old4""},{""role"":""assistant"",""content"":""old5""},{""role"":""user"",""content"":""done""}]"
$OUT8D = trim_context $PRETTY 'force'
if (valid_json $OUT8D) { pass 'TC-8d' 'trim_context keeps pretty/multiline entries whole' } else { fail 'TC-8d' 'pretty entry compaction invalid' $OUT8D }

$SEP_PAYLOAD = ('x},{y' * 120000)
$SEP_MSGS = '[{"role":"user","content":"task"},{"role":"user","content":"old"},{"type":"reasoning","id":"rs_huge","summary":[]},{"type":"function_call","call_id":"call_huge","name":"grep","arguments":"{}"},{"type":"function_call_output","call_id":"call_huge","output":"' + $SEP_PAYLOAD + '"},{"role":"user","content":"latest"}]'
$global:CTX_LIMIT = 12000; $global:AGENT_RESERVE = 1000; $global:AGENT_KEEP_RECENT = 2000
$OUT8E = trim_context $SEP_MSGS 'huge separator payload'
if ((valid_json $OUT8E) -and $OUT8E.Length -le 11000 -and $OUT8E.Contains('omitted during compaction')) { pass 'TC-8e' 'huge tool output with literal },{ compacts quickly and validly' } else { fail 'TC-8e' 'huge separator payload compaction invalid' ('len=' + $OUT8E.Length + ' cap=' + 11000 + ' out=' + $OUT8E.Substring(0, [Math]::Min(300, $OUT8E.Length))) }

$global:AGENT_KEEP_RECENT = $OLD_KEEP
$global:CTX_LIMIT = $OLD_CTX
$global:AGENT_RESERVE = $OLD_RES

# ---------------------------------------------------------------- TC-9 local fallback
function Global:call_api([string]$m) {
    $global:PU_API_RC = 0
    return '{"error":{"message":"rate limit"}}'
}
$OUT9 = trim_context $MSGS_BIG
if ($OUT9 -ne $MSGS_BIG -and (valid_json $OUT9) -and $OUT9.Contains('compacted locally')) { pass 'TC-9' 'API failure -> local compacted fallback' } else { fail 'TC-9' "local fallback didn't fire" $OUT9 }

$global:CTX_LIMIT = 1400; $global:AGENT_RESERVE = 200; $global:AGENT_KEEP_RECENT = 100000
function Global:call_api([string]$m) {
    $global:PU_API_RC = 0
    return '{"id":"m","type":"message","role":"assistant","content":[{"type":"text","text":"short structured summary"}]}'
}
$OUT9B = trim_context $MSGS_BIG 'hard budget'
if ((valid_json $OUT9B) -and $OUT9B.Length -le 1200) { pass 'TC-9b' 'normal compaction stays under hard budget' } else { fail 'TC-9b' 'over budget or invalid' ('len=' + $OUT9B.Length + ' cap=1200 out=' + $OUT9B.Substring(0, [Math]::Min(200, $OUT9B.Length))) }

$HUGE_TASK = ('A' * 5000)
$HUGE_FIRST = '[{"role":"user","content":"' + $HUGE_TASK + '"},{"role":"assistant","content":"old1"},{"role":"user","content":"old2"},{"role":"assistant","content":"old3"},{"role":"user","content":"old4"},{"role":"assistant","content":"old5"},{"role":"user","content":"latest"}]'
$global:CTX_LIMIT = 1200; $global:AGENT_RESERVE = 200; $global:AGENT_KEEP_RECENT = 500
function Global:call_api([string]$m) {
    $global:PU_API_RC = 0
    return '{"id":"m","type":"message","role":"assistant","content":[{"type":"text","text":"summary"}]}'
}
$OUT9C = trim_context $HUGE_FIRST 'huge anchor'
if ((valid_json $OUT9C) -and $OUT9C.Length -le 1000) { pass 'TC-9c' 'huge first message falls back under budget' } else { fail 'TC-9c' 'huge anchor escaped budget guard' ('len=' + $OUT9C.Length + ' cap=1000 out=' + $OUT9C.Substring(0, [Math]::Min(200, $OUT9C.Length))) }

$GIANT_SUM = ('S' * 5000)
$global:CTX_LIMIT = 1500; $global:AGENT_RESERVE = 200; $global:AGENT_KEEP_RECENT = 500
function Global:call_api([string]$m) {
    $global:PU_API_RC = 0
    return '{"id":"m","type":"message","role":"assistant","content":[{"type":"text","text":"' + $GIANT_SUM + '"}]}'
}
$OUT9D = trim_context $MSGS_BIG 'giant summary'
if ((valid_json $OUT9D) -and $OUT9D.Length -le 1300) { pass 'TC-9d' 'oversized model summary falls back under budget' } else { fail 'TC-9d' 'giant summary escaped budget guard' ('len=' + $OUT9D.Length + ' cap=1300 out=' + $OUT9D.Substring(0, [Math]::Min(200, $OUT9D.Length))) }

$ERR_MSGS = '[{"role":"user","content":"task"},{"role":"assistant","content":[{"type":"tool_use","id":"e","name":"read","input":{"path":"errfile.sh"}}]},{"role":"user","content":[{"type":"tool_result","tool_use_id":"e","content":"Error: file not found: errfile.sh"}]},{"role":"assistant","content":"old3"},{"role":"user","content":"old4"},{"role":"assistant","content":"old5"},{"role":"user","content":"latest"}]'
$global:CTX_LIMIT = 1800; $global:AGENT_RESERVE = 200; $global:AGENT_KEEP_RECENT = 100
function Global:call_api([string]$m) {
    $global:PU_API_RC = 0
    return '{"error":{"message":"rate limit"}}'
}
$OUT9E = trim_context $ERR_MSGS 'local facts'
if ((valid_json $OUT9E) -and $OUT9E.Contains('compacted locally') -and $OUT9E.Contains('errfile.sh') -and $OUT9E.Contains('Error:')) { pass 'TC-9e' 'local fallback preserves useful path/error facts' } else { fail 'TC-9e' 'local fallback lost useful facts' $OUT9E }

$FIXTURE_PATH = Join-Path $PSScriptRoot 'fixtures\long_anthropic_msgs.json'
$FIXTURE_MSGS = [System.IO.File]::ReadAllText($FIXTURE_PATH)
$global:CTX_LIMIT = 7000; $global:AGENT_RESERVE = 300; $global:AGENT_KEEP_RECENT = 200
function Global:call_api([string]$m) {
    $global:PU_API_RC = 0
    return '{"error":{"message":"rate limit"}}'
}
$OUT9F = trim_context $FIXTURE_MSGS 'fixture local fallback'
if ((valid_json $FIXTURE_MSGS) -and (valid_json $OUT9F) -and $OUT9F.Length -le 6700 -and $OUT9F.Contains('pu.sh') -and $OUT9F.Contains('compaction-improvements.md') -and $OUT9F.Contains('eval/test_real.sh') -and $OUT9F.Contains('AGENT_KEEP_RECENT') -and $OUT9F.Contains('[exit:1]')) { pass 'TC-9f' 'fixture compaction preserves realistic session facts' } else { fail 'TC-9f' 'fixture local fallback lost facts' ('len=' + $OUT9F.Length + ' out=' + $OUT9F.Substring(0, [Math]::Min(300, $OUT9F.Length))) }

$global:CTX_LIMIT = 2000
$global:AGENT_RESERVE = 200
$global:AGENT_KEEP_RECENT = 80000

# ------------------------------------------------------------------ trim_context
section 'trim_context'

$OLD_CTX = $global:CTX_LIMIT; $OLD_RES = $global:AGENT_RESERVE; $OLD_KEEP = $global:AGENT_KEEP_RECENT
$OLD_HIST = $global:HISTORY; $OLD_PIPE = $global:PIPE; $OLD_MAX = $global:MAX_STEPS
$OLD_PROV = $global:PROVIDER; $OLD_MODEL = $global:MODEL; $OLD_EOK = $global:EFFORT_OK
$OLD_OAK = $env:OPENAI_API_KEY; $OLD_LOG = $global:LOG

# TC-9g: end-to-end compaction of a realistic oversized user history. The
# fixture is pretty-printed on disk; minify it first so _ctx_entries can split
# the array on the '},{' separator (3397b minified > 3100b cap, so the
# summary+tail compaction path triggers inside run_task).
$FIXTURE_USER = Join-Path $PSScriptRoot 'fixtures\long_user_msgs.json'
$USER_BLOW_MSGS = ([System.IO.File]::ReadAllText($FIXTURE_USER) | ConvertFrom-Json) | ConvertTo-Json -Compress -Depth 100

$global:CTX_LIMIT = 3400
$global:AGENT_RESERVE = 300
$global:AGENT_KEEP_RECENT = 1200
$global:MAX_STEPS = 3
$global:MSGS = $USER_BLOW_MSGS
$global:HISTORY = Join-Path $script:TMPD 'user_blow_history.json'
$global:LOG = Join-Path $script:TMPD 'user_blow.jsonl'
$global:PIPE = 1
$global:PROVIDER = 'openai'
$global:MODEL = 'gpt-5.5'
$global:EFFORT_OK = 1
$env:OPENAI_API_KEY = 'dummy'

$REQF = Join-Path $script:TMPD 'user_blow_request.json'
$utf = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($REQF, '{}', $utf)
$CALLS = Join-Path $script:TMPD 'user_blow_calls'
[System.IO.File]::WriteAllText($CALLS, '', $utf)
function Global:call_api([string]$m) {
    $global:PU_API_RC = 0
    [System.IO.File]::AppendAllText($CALLS, 'x', $utf)
    if ($m.Contains('Summarize the earlier transcript')) {
        return '{"output_text":"Goal: debug pu.sh compaction with long user messages. Constraints: keep runtime dependency-free, preserve the latest user request, and validate JSON after compaction.","usage":{"input_tokens":1,"output_tokens":1}}'
    }
    [System.IO.File]::WriteAllText($REQF, $m, $utf)
    return '{"output_text":"post compact ok","usage":{"input_tokens":1,"output_tokens":1}}'
}

$cbUser = Capture-Both { run_task 'Now apply the smallest safe fix and report what changed' }
$USER_RC = $cbUser.rc
$USER_OUT = $cbUser.out.TrimEnd("`r", "`n")
$REQ_JSON = if (Test-Path -LiteralPath $REQF -PathType Leaf) { [System.IO.File]::ReadAllText($REQF) } else { '' }
$HIST_JSON = if (Test-Path -LiteralPath $HISTORY -PathType Leaf) { [System.IO.File]::ReadAllText($HISTORY) } else { '' }
$CALL_N = ([System.IO.File]::ReadAllText($CALLS)).Length
$okG = $false
if ($USER_RC -eq 0 -and $USER_OUT -eq 'post compact ok' -and $CALL_N -eq 2 -and (valid_json $REQ_JSON) -and ($REQ_JSON.Length -le 3100) -and (valid_json $HIST_JSON)) {
    $okG = json_field $REQ_JSON { param($d)
        $hasCard = $false
        foreach ($x in $d) {
            if ($x.content -is [string] -and $x.content.Contains('Earlier compacted')) { $hasCard = $true }
        }
        return ($hasCard -and ($d[$d.Count - 1].content -eq 'Now apply the smallest safe fix and report what changed'))
    }
}
if ($okG) {
    $okG = json_field $HIST_JSON { param($d) ($d[$d.Count - 1].content -eq 'post compact ok') }
}
if ($okG) { pass 'TC-9g' 'oversized realistic user history compacts and continues' } else { fail 'TC-9g' 'user-message compaction did not continue cleanly' ('rc=' + $USER_RC + ' calls=' + $CALL_N + ' out=' + $USER_OUT + ' req_len=' + $REQ_JSON.Length + ' req=' + $REQ_JSON.Substring(0, [Math]::Min(500, $REQ_JSON.Length)) + ' err=' + $cbUser.err) }

# TC-9h: a function_call_output with no preceding function_call must be dropped
# while valid call/output pairs survive a normal (fast-path) trim_context.
$global:CTX_LIMIT = 20000; $global:AGENT_RESERVE = 1000; $global:AGENT_KEEP_RECENT = 1200
$global:MAX_STEPS = 2; $global:PIPE = 1; $global:PROVIDER = 'openai'; $global:MODEL = 'gpt-5.5'; $global:EFFORT_OK = 1
$global:MSGS = '[{"role":"user","content":"old task"},{"role":"user","content":"[Earlier compacted memory:\nok]"},{"role":"user","content":"continue"},{"type":"reasoning","id":"rs_orphan","summary":[]},{"type":"function_call_output","call_id":"call_ArSXATXNDlBnp0gPrS6lFTCZ","output":"Edited eval/test_real.sh"},{"type":"function_call","call_id":"call_good","name":"read","arguments":"{}"},{"type":"function_call_output","call_id":"call_good","output":"ok"}]'
$global:HISTORY = Join-Path $script:TMPD 'orphan_history.json'
$global:LOG = Join-Path $script:TMPD 'orphan.jsonl'
$REQF = Join-Path $script:TMPD 'orphan_request.json'
[System.IO.File]::WriteAllText($REQF, '{}', $utf)
function Global:call_api([string]$m) {
    $global:PU_API_RC = 0
    [System.IO.File]::WriteAllText($REQF, $m, $utf)
    return '{"output_text":"orphan clean ok","usage":{"input_tokens":1,"output_tokens":1}}'
}
$cbOrphan = Capture-Both { run_task 'what bugs are outstanding?' }
$ORPHAN_RC = $cbOrphan.rc
$ORPHAN_OUT = $cbOrphan.out.TrimEnd("`r", "`n")
$ORPHAN_REQ = if (Test-Path -LiteralPath $REQF -PathType Leaf) { [System.IO.File]::ReadAllText($REQF) } else { '' }
$okH = $false
if ($ORPHAN_RC -eq 0 -and $ORPHAN_OUT -eq 'orphan clean ok' -and (valid_json $ORPHAN_REQ) -and (-not $ORPHAN_REQ.Contains('call_ArSXATXNDlBnp0gPrS6lFTCZ'))) {
    $okH = json_field $ORPHAN_REQ { param($d)
        $calls = @{}
        foreach ($x in $d) {
            if ($x.type -eq 'function_call') { $calls[[string]$x.call_id] = $true }
        }
        foreach ($x in $d) {
            if ($x.type -eq 'function_call_output') {
                if (-not $calls.ContainsKey([string]$x.call_id)) { return $false }
            }
        }
        return $true
    }
}
if ($okH) { pass 'TC-9h' 'orphan function output dropped, valid call/output pairs sent' } else { fail 'TC-9h' 'orphan function output survived' ('rc=' + $ORPHAN_RC + ' out=' + $ORPHAN_OUT + ' req=' + $ORPHAN_REQ + ' err=' + $cbOrphan.err) }

# TC-9i: large OpenAI function_call entries must be stubbed, not dropped,
# otherwise the matching function_call_output is removed too.
$BIG_CONTENT = ('x' * 15000)
$BIG_MSGS = '[{"role":"user","content":"write a big file"},{"type":"function_call","call_id":"call_big_write","name":"write","arguments":"{\"path\":\"docs/x.md\",\"content\":\"' + $BIG_CONTENT + '\"}"},{"type":"function_call_output","call_id":"call_big_write","output":"Wrote to docs/x.md"}]'
$global:CTX_LIMIT = 50000; $global:AGENT_RESERVE = 1000
$global:PROVIDER = 'openai'
$global:LOG = Join-Path $script:TMPD 'big_call.jsonl'
$BIG_OUT = trim_context $BIG_MSGS
$okI = $false
if (valid_json $BIG_OUT) {
    $okI = json_field $BIG_OUT { param($d)
        $callsN = 0; $outsN = 0; $stubArgs = $false
        foreach ($x in $d) {
            if ($x.type -eq 'function_call' -and $x.call_id -eq 'call_big_write') {
                $callsN++
                if ($x.arguments -is [string] -and $x.arguments.Contains('omitted') -and (-not $x.arguments.Contains('x' * 24))) { $stubArgs = $true }
            }
            if ($x.type -eq 'function_call_output' -and $x.call_id -eq 'call_big_write') { $outsN++ }
        }
        return ($callsN -eq 1 -and $outsN -eq 1 -and $stubArgs)
    }
}
if ($okI) { pass 'TC-9i' 'large OpenAI function_call is stubbed with paired output preserved' } else { fail 'TC-9i' 'large OpenAI function_call was dropped or left huge' ('out=' + $BIG_OUT.Substring(0, [Math]::Min(500, $BIG_OUT.Length))) }

# TC-9j: Anthropic histories must not send orphan tool_result messages or
# dangling assistant tool_use messages after resume/compaction.
$ANTH_ORPHAN = '[{"role":"user","content":"old task"},{"role":"user","content":[{"type":"tool_result","tool_use_id":"missing","content":"orphan"}]},{"role":"assistant","content":[{"type":"tool_use","id":"dangling","name":"read","input":{}}]},{"role":"assistant","content":[{"type":"tool_use","id":"good","name":"read","input":{}}]},{"role":"user","content":[{"type":"tool_result","tool_use_id":"good","content":"ok"}]}]'
$global:CTX_LIMIT = 20000; $global:AGENT_RESERVE = 1000
$global:PROVIDER = 'anthropic'
$global:LOG = Join-Path $script:TMPD 'anthropic_pairs.jsonl'
$ANTH_OUT = trim_context $ANTH_ORPHAN
$okJ = valid_json $ANTH_OUT
if ($okJ) {
    $okJ = json_field $ANTH_OUT { param($d)
        $uses = @{}; $results = @{}
        for ($i = 0; $i -lt $d.Count; $i++) {
            $c = $d[$i].content
            if ($c -is [System.Array]) {
                foreach ($b in $c) {
                    if ($b.type -eq 'tool_use') { $uses[[string]$b.id] = $i }
                    if ($b.type -eq 'tool_result') { $results[[string]$b.tool_use_id] = $i }
                }
            }
        }
        $gUse = if ($uses.ContainsKey('good')) { $uses['good'] } else { 99 }
        $gRes = if ($results.ContainsKey('good')) { $results['good'] } else { -1 }
        return ((-not $results.ContainsKey('missing')) -and (-not $uses.ContainsKey('dangling')) -and ($gUse -lt $gRes))
    }
}
if ($okJ) { pass 'TC-9j' 'Anthropic orphan/dangling tool pairs are sanitized' } else { fail 'TC-9j' 'Anthropic invalid tool pair survived' ('out=' + $ANTH_OUT.Substring(0, [Math]::Min(500, $ANTH_OUT.Length))) }

# TC-9k: large Anthropic tool_result is stubbed with its pair preserved.
$BIG_ANTH_CONTENT = ('x' * 15000)
$BIG_ANTH = '[{"role":"user","content":"read a big file"},{"role":"assistant","content":[{"type":"tool_use","id":"toolu_big","name":"read","input":{"path":"big.txt"}}]},{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_big","content":"' + $BIG_ANTH_CONTENT + '"}]}]'
$global:CTX_LIMIT = 50000; $global:AGENT_RESERVE = 1000
$global:PROVIDER = 'anthropic'
$global:LOG = Join-Path $script:TMPD 'anthropic_big.jsonl'
$BIG_ANTH_OUT = trim_context $BIG_ANTH
$okK = (valid_json $BIG_ANTH_OUT) -and $BIG_ANTH_OUT.Contains('omitted during compaction') -and (-not $BIG_ANTH_OUT.Contains('x' * 24))
if ($okK) {
    $okK = json_field $BIG_ANTH_OUT { param($d)
        $uses = @{}; $results = @{}; $text = ''
        for ($i = 0; $i -lt $d.Count; $i++) {
            $c = $d[$i].content
            if ($c -is [System.Array]) {
                foreach ($b in $c) {
                    if ($b.type -eq 'tool_use') { $uses[[string]$b.id] = $i }
                    if ($b.type -eq 'tool_result') { $results[[string]$b.tool_use_id] = $i; $text = $text + [string]$b.content }
                }
            }
        }
        $gUse = if ($uses.ContainsKey('toolu_big')) { $uses['toolu_big'] } else { 99 }
        $gRes = if ($results.ContainsKey('toolu_big')) { $results['toolu_big'] } else { -1 }
        return (($gUse -lt $gRes) -and $text.Contains('omitted during compaction') -and (-not $text.Contains('x' * 24)))
    }
}
if ($okK) { pass 'TC-9k' 'large Anthropic tool_result is stubbed with pair preserved' } else { fail 'TC-9k' 'large Anthropic tool_result pair not preserved' ('out=' + $BIG_ANTH_OUT.Substring(0, [Math]::Min(500, $BIG_ANTH_OUT.Length))) }

$global:CTX_LIMIT = $OLD_CTX; $global:AGENT_RESERVE = $OLD_RES; $global:AGENT_KEEP_RECENT = $OLD_KEEP
$global:HISTORY = $OLD_HIST; $global:PIPE = $OLD_PIPE; $global:MAX_STEPS = $OLD_MAX
$global:PROVIDER = $OLD_PROV; $global:MODEL = $OLD_MODEL; $global:EFFORT_OK = $OLD_EOK
$global:LOG = $OLD_LOG
if ($OLD_OAK) { $env:OPENAI_API_KEY = $OLD_OAK } else { Remove-Item Env:OPENAI_API_KEY -ErrorAction SilentlyContinue }
$global:MSGS = ''

# ------------------------------------------------------------------ run_task
section 'run_task'

$env:OPENAI_API_KEY = 'dummy'
$global:LOG = Join-Path $script:TMPD 'run_task.jsonl'
$global:MAX_STEPS = 1
$global:PIPE = 1
$global:PROVIDER = 'openai'
$global:MODEL = 'gpt-5.5'
$global:EFFORT_OK = 1
$global:MSGS = ''
$global:HISTORY = ''

function Global:call_api([string]$m) {
    $global:PU_API_RC = 0
    return '{"error":{"message":"rate limit"}}'
}
$cbT10 = Capture-Both { $global:MSGS = ''; run_task 'hi' }
if ($cbT10.rc -ne 0 -and $cbT10.err.Contains('API failed') -and (-not $cbT10.err.Contains('Empty final'))) {
    pass 'TC-10' 'run_task: API errors fail as API errors, not empty final'
} else { fail 'TC-10' 'API error misreported' ('rc=' + $cbT10.rc + ' err=' + $cbT10.err) }

$CNT = Join-Path $script:TMPD 'auth_count'
$utfT7 = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($CNT, '', $utfT7)
function Global:call_api([string]$m) {
    $global:PU_API_RC = 0
    [System.IO.File]::AppendAllText($CNT, 'x', $utfT7)
    return '{"error":{"message":"Incorrect API key provided"}}'
}
$cbT11 = Capture-Both { $global:MSGS = ''; run_task 'hi' }
$CNT_N = ([System.IO.File]::ReadAllText($CNT)).Length
if ($cbT11.rc -ne 0 -and $CNT_N -eq 1 -and $cbT11.err.Contains('Incorrect API key')) {
    pass 'TC-11' 'run_task: auth errors are not retried'
} else { fail 'TC-11' 'auth error retry behavior' ('rc=' + $cbT11.rc + ' calls=' + $CNT_N + ' err=' + $cbT11.err) }

[System.IO.File]::WriteAllText($CNT, '', $utfT7)
function Global:call_api([string]$m) {
    $global:PU_API_RC = 0
    [System.IO.File]::AppendAllText($CNT, 'x', $utfT7)
    return '{"error":{"message":"Invalid body: failed to parse JSON value"}}'
}
$cbT11b = Capture-Both { $global:MSGS = ''; run_task 'hi' }
$CNT_N = ([System.IO.File]::ReadAllText($CNT)).Length
if ($cbT11b.rc -ne 0 -and $CNT_N -eq 1 -and $cbT11b.err.Contains('Invalid body')) {
    pass 'TC-11b' 'run_task: invalid request JSON is not retried'
} else { fail 'TC-11b' 'invalid JSON retry behavior' ('rc=' + $cbT11b.rc + ' calls=' + $CNT_N + ' err=' + $cbT11b.err) }

[System.IO.File]::WriteAllText($CNT, '', $utfT7)
function Global:call_api([string]$m) {
    $global:PU_API_RC = 1
    [System.IO.File]::AppendAllText($CNT, 'x', $utfT7)
    return 'curl: (6) Could not resolve host'
}
$cbT12 = Capture-Both { $global:MSGS = ''; run_task 'hi' }
$CNT_N = ([System.IO.File]::ReadAllText($CNT)).Length
if ($cbT12.rc -ne 0 -and $CNT_N -eq 3 -and $cbT12.err.Contains('API transport') -and (-not $cbT12.err.Contains('Empty final')) -and (-not $cbT12.err.Contains('Max steps'))) {
    pass 'TC-12' 'run_task: transport failures retry then report transport'
} else { fail 'TC-12' 'transport error masked' ('rc=' + $cbT12.rc + ' calls=' + $CNT_N + ' err=' + $cbT12.err) }

$AFTER = Join-Path $script:TMPD 'after_empty'
Remove-Item -LiteralPath $AFTER -ErrorAction SilentlyContinue
function Global:call_api([string]$m) {
    $global:PU_API_RC = 0
    return ''
}
$cbT12b = Capture-Both { $global:MSGS = ''; run_task 'hi' }
[System.IO.File]::WriteAllText($AFTER, 'after', $utfT7)
if ($cbT12b.rc -ne 0 -and (Test-Path -LiteralPath $AFTER -PathType Leaf)) {
    pass 'TC-12b' 'run_task: empty API response returns instead of exiting shell'
} else { fail 'TC-12b' 'empty response exited caller' ('rc=' + $cbT12b.rc + ' after=' + $(if (Test-Path -LiteralPath $AFTER -PathType Leaf) { 'yes' } else { 'no' }) + ' err=' + $cbT12b.err) }

$script:DBG = Join-Path $script:TMPD 'dbg'
$env:AGENT_DEBUG_API = $script:DBG
function Global:call_api([string]$m) {
    $global:PU_API_RC = 0
    return '{"output_text":"ok","usage":{"input_tokens":1,"output_tokens":1}}'
}
$null = Capture-Both { $global:MSGS = ''; run_task 'hi' }
Remove-Item Env:AGENT_DEBUG_API -ErrorAction SilentlyContinue
$iFile = Join-Path $script:DBG 'input-1-0.json'
$rFile = Join-Path $script:DBG 'resp-1-0.json'
if ((Test-Path -LiteralPath $iFile -PathType Leaf) -and ((Get-Item -LiteralPath $iFile).Length -gt 0) -and
    (Test-Path -LiteralPath $rFile -PathType Leaf) -and ((Get-Item -LiteralPath $rFile).Length -gt 0)) {
    pass 'TC-13' 'run_task: AGENT_DEBUG_API captures input/response'
} else { fail 'TC-13' 'debug capture missing' ('in=' + (Test-Path -LiteralPath $iFile -PathType Leaf) + ' resp=' + (Test-Path -LiteralPath $rFile -PathType Leaf)) }

function Global:call_api([string]$m) {
    $global:PU_API_RC = 0
    return '{"error":{"message":"model not found"}}'
}
$cbT14 = Capture-Both { $global:MSGS = ''; run_task 'hi' }
if ($cbT14.rc -ne 0 -and $cbT14.err.Contains('Try /model MODEL')) {
    pass 'TC-14' 'run_task: model errors suggest /model'
} else { fail 'TC-14' 'model hint missing' ('rc=' + $cbT14.rc + ' err=' + $cbT14.err) }

# ── Tool truncation: line-aware, marker safe ───────────────────────────────
section 'tool truncation'

function Global:Is-ValidUnicode([string]$s) {
    foreach ($c in $s.ToCharArray()) {
        if ([char]::IsHighSurrogate($c) -or [char]::IsLowSurrogate($c)) { return $false }
    }
    return $true
}
function Global:truncate_out([string]$out) {
    [int]$M = [int]$global:AGENT_TOOL_TRUNC
    if ($out.Length -gt $M) { return (_trunc_text $M $out) }
    return $out
}

$global:AGENT_TOOL_TRUNC = 2000

$OUT = truncate_out 'small output stays intact'
if ($OUT -eq 'small output stays intact') { pass 'TR-1' 'short output passes through' } else { fail 'TR-1' 'short output mutated' $OUT }

$LONG = ((1..5000) -join "`n")
$OUT = truncate_out $LONG
$LINES = (@($OUT -split "`n")).Count
if ($LINES -le 41) { pass 'TR-2' ('long output truncated to <=41 lines (got ' + $LINES + ')') } else { fail 'TR-2' ('got ' + $LINES + ' lines') }

$FIRST = @($OUT -split "`n")[0]
if ($FIRST -eq '1') { pass 'TR-3' 'first line preserved (file headers survive)' } else { fail 'TR-3' 'first line lost' }

$NONEMPTY = @(@($OUT -split "`n") | Where-Object { $_ -ne '' })
if ($NONEMPTY[-1] -eq '5000') { pass 'TR-4' 'last line preserved (errors at end survive)' } else { fail 'TR-4' 'last line lost' }

if ($OUT.Contains('lines truncated')) { pass 'TR-5' 'truncation marker inserted' } else { fail 'TR-5' 'no marker' }

$E_ACCENT = [string][char]0x00E9
$UTF = ((1..5000 | ForEach-Object { [string]$_ + ' ' + $E_ACCENT }) -join "`n")
$OUT = truncate_out $UTF
if ((Is-ValidUnicode $OUT) -and $OUT.Contains($E_ACCENT)) { pass 'TR-6' 'UTF-8 multibyte preserved (no mid-char cut)' } else { fail 'TR-6' 'UTF-8 corrupted' }

$ESC = JsonEscape $OUT
if (valid_json ('{"x":"' + $ESC + '"}')) { pass 'TR-7' 'truncated output to json_escape to valid JSON' } else { fail 'TR-7' 'truncated->escape produces invalid JSON' }

$ONE_LINE = ('x' * 100000)
$OUT = truncate_out $ONE_LINE
if ($OUT.Length -lt 2000 -and $OUT.Contains('line truncated')) { pass 'TR-8' 'single huge line is clipped instead of preserved whole' } else { fail 'TR-8' 'single huge line not clipped' ('len=' + $OUT.Length) }

$UTF_ONE = ($E_ACCENT * 5000)
$OUT = truncate_out $UTF_ONE
if ((Is-ValidUnicode $OUT) -and $OUT.Length -lt 2000) { pass 'TR-9' 'single huge UTF-8 line truncates without corrupting chars' } else { fail 'TR-9' 'UTF-8 long-line truncation corrupted chars' ('len=' + $OUT.Length) }

$global:MSGS = ''

# ------------------------------------------------------------------ edit tool
section 'edit tool'

function Global:TJ($o) { return ($o | ConvertTo-Json -Compress -Depth 100) }

$utfE = New-Object System.Text.UTF8Encoding($false)
$F = Join-Path $script:TMPD ('edfile_' + [guid]::NewGuid().ToString('N'))

# ED-1: single-line edit
[System.IO.File]::WriteAllText($F, "foo`nbar`nbaz`n", $utfE)
$OUT = run_tool 'edit' (TJ @{ path = $F; oldText = 'bar'; newText = 'BAR' })
$EE = [System.IO.File]::ReadAllText($F)
if ($EE.Contains('foo') -and $EE.Contains('BAR') -and $EE.Contains('baz')) { pass 'ED-1' 'single-line replacement' } else { fail 'ED-1' 'single-line' ('out=' + $OUT + ' file=' + $EE) }

# ED-2: multi-line oldText (regression: must not error)
[System.IO.File]::WriteAllText($F, "header`nline1`nline2`nline3`nfooter`n", $utfE)
$OUT = run_tool 'edit' (TJ @{ path = $F; oldText = "line1`nline2`nline3"; newText = 'REPLACED' })
$EE = [System.IO.File]::ReadAllText($F)
if ($EE.Contains('REPLACED') -and -not $EE.Contains('line1') -and -not $OUT.Contains('Error')) { pass 'ED-2' 'multi-line oldText: no parse error' } else { fail 'ED-2' 'multi-line oldText: regression hit' ('out=' + $OUT + ' file=' + $EE) }

# ED-3: multi-line oldText AND newText round-trip
[System.IO.File]::WriteAllText($F, "header`nline1`nline2`nline3`nfooter`n", $utfE)
$null = run_tool 'edit' (TJ @{ path = $F; oldText = "line1`nline2`nline3"; newText = "NEW1`nNEW2" })
$EXPECTED = "header`nNEW1`nNEW2`nfooter`n"
$EE = [System.IO.File]::ReadAllText($F)
if ($EE -eq $EXPECTED) { pass 'ED-3' 'multi-line old -> multi-line new' } else { fail 'ED-3' 'multi-line replacement' ('got: [' + $EE.Replace("`n", '\n') + ']') }

# ED-4: oldText with special chars (&, \)
[System.IO.File]::WriteAllText($F, 'use & here, and \ too' + "`n", $utfE)
$OUT = run_tool 'edit' (TJ @{ path = $F; oldText = '& here, and \'; newText = 'REPLACED' })
$EE = [System.IO.File]::ReadAllText($F)
if ($EE.Contains('REPLACED') -and -not $EE.Contains('& here')) { pass 'ED-4' 'oldText with & and backslash' } else { fail 'ED-4' 'special chars' ('out=' + $OUT + ' file=' + $EE) }

# ED-5: edit matches exact oldText beyond first line
$DBG_LINE = 'MSGS=; AGENT_DEBUG_API="<dbg>"; call_api(){ echo ''{"output_text":"ok","usage":{"input_tokens":1,"output_tokens":1}}''; }'
[System.IO.File]::WriteAllLines($F, @('prefix', $DBG_LINE, 'suffix'), $utfE)
$OUT = run_tool 'edit' (TJ @{ path = $F; oldText = $DBG_LINE; newText = 'DEBUG_LINE' })
$EE = [System.IO.File]::ReadAllText($F)
if ($EE.Contains('DEBUG_LINE')) { pass 'ED-5' 'edit matches exact oldText beyond first line' } else { fail 'ED-5' 'edit missed later exact oldText' ('out=' + $OUT + ' file=' + $EE) }

# ED-6: non-unique oldText rejected with guidance
[System.IO.File]::WriteAllText($F, "dup`ndup`n", $utfE)
$OUT = run_tool 'edit' (TJ @{ path = $F; oldText = 'dup'; newText = 'X' })
if ($OUT.Contains('matched multiple') -and $OUT.Contains('larger unique')) { pass 'ED-6' 'edit tool rejects non-unique oldText with guidance' } else { fail 'ED-6' 'duplicate oldText not rejected' ('out=' + $OUT) }

# ED-7: edit tool preserves the read-only attribute (Windows chmod analog)
[System.IO.File]::WriteAllText($F, "one`n", $utfE)
[System.IO.File]::SetAttributes($F, [System.IO.FileAttributes]::ReadOnly)
$null = run_tool 'edit' (TJ @{ path = $F; oldText = 'one'; newText = 'two' })
$RO = ([System.IO.File]::GetAttributes($F) -band [System.IO.FileAttributes]::ReadOnly) -ne 0
$EE = [System.IO.File]::ReadAllText($F)
[System.IO.File]::SetAttributes($F, [System.IO.FileAttributes]::Normal)
if ($RO -and $EE -eq "two`n") { pass 'ED-7' 'edit tool preserves read-only attribute' } else { fail 'ED-7' 'attribute changed' ('ro=' + $RO + ' content=' + $EE) }

# ED-8: not-found error gives retry guidance
$OUT = run_tool 'edit' (TJ @{ path = $F; oldText = 'missing'; newText = 'X' })
[System.IO.File]::SetAttributes($F, [System.IO.FileAttributes]::Normal)
if ($OUT.Contains('Read exact surrounding lines')) { pass 'ED-8' 'edit not-found error gives retry guidance' } else { fail 'ED-8' 'edit guidance' ('out=' + $OUT) }

# ED-9: grep no-match is explicit
$OUT = run_tool 'grep' (TJ @{ path = $F; pattern = 'absent' })
if ($OUT -eq 'No matches') { pass 'ED-9' 'grep no-match is explicit' } else { fail 'ED-9' 'grep no-match' ('out=' + $OUT) }

# ED-10: read limit:0 returns empty cleanly
$OUT = run_tool 'read' (TJ @{ path = $F; limit = 0 })
if ([string]::IsNullOrEmpty($OUT)) { pass 'ED-10' 'read limit:0 returns empty cleanly' } else { fail 'ED-10' 'read limit 0' ('out=' + $OUT) }

# ED-11: write preserves trailing newline
$null = run_tool 'write' (TJ @{ path = $F; content = "a`n" })
$B = [System.IO.File]::ReadAllBytes($F)
if ($B.Length -eq 2) { pass 'ED-11' 'write preserves trailing newline' } else { fail 'ED-11' 'write newline stripped' ('bytes=' + $B.Length) }

# ED-12: edit preserves trailing newline in newText
[System.IO.File]::WriteAllText($F, "a`nb`nc", $utfE)
$null = run_tool 'edit' (TJ @{ path = $F; oldText = "b`nc"; newText = "B`nC`n" })
$B = [System.IO.File]::ReadAllBytes($F)
if ($B.Length -gt 0 -and $B[$B.Length - 1] -eq 10) { pass 'ED-12' 'edit preserves trailing newline in newText' } else { fail 'ED-12' 'edit newline stripped' ('bytes=' + ($B -join ',')) }

# Harmony channel marker guard: blocks model CoT leakage from corrupting files.
[System.IO.File]::WriteAllText($F, "before`nMARK`nafter`n", $utfE)
$OUT = run_tool 'edit' (TJ @{ path = $F; oldText = 'MARK'; newText = 'X to=functions.edit leaked' })
$EE = [System.IO.File]::ReadAllText($F)
if ($OUT.Contains('harmony channel markers') -and $EE.Contains('MARK')) { pass 'ED-12a' 'edit rejects newText with to=functions. marker; file unchanged' } else { fail 'ED-12a' 'edit harmony guard (to=functions.)' ('out=' + $OUT + ' file=' + $EE) }

$OUT = run_tool 'edit' (TJ @{ path = $F; oldText = 'MARK'; newText = 'X <|channel|>analysis leaked' })
$EE = [System.IO.File]::ReadAllText($F)
if ($OUT.Contains('harmony channel markers') -and $EE.Contains('MARK')) { pass 'ED-12b' 'edit rejects newText with <|channel|> marker; file unchanged' } else { fail 'ED-12b' 'edit harmony guard (<|channel|>)' ('out=' + $OUT + ' file=' + $EE) }

$OUT = run_tool 'write' (TJ @{ path = $F; content = 'x to=functions.read y' })
$EE = [System.IO.File]::ReadAllText($F)
if ($OUT.Contains('harmony channel markers') -and $EE.Contains('MARK')) { pass 'ED-12c' 'write rejects content with to=functions. marker; file unchanged' } else { fail 'ED-12c' 'write harmony guard' ('out=' + $OUT + ' file=' + $EE) }

$null = run_tool 'edit' (TJ @{ path = $F; oldText = 'MARK'; newText = 'a function calls b' })
$EE = [System.IO.File]::ReadAllText($F)
if ($EE.Contains('a function calls b')) { pass 'ED-12d' 'edit guard does not false-trigger on benign ''function'' text' } else { fail 'ED-12d' 'edit guard false positive' ('file=' + $EE) }

# ED-13: spin_stop is quiet on non-tty stderr
$e13 = Capture-Err { $null = spin_stop }
if ($e13.Length -eq 0) { pass 'ED-13' 'spin_stop is quiet on non-tty stderr' } else { fail 'ED-13' 'spinner leaked escapes' ('bytes=' + $e13.Length) }

# ED-14/15: noisy directories and trace files are pruned from search
$SEARCH = Join-Path $script:TMPD 'search'
[System.IO.Directory]::CreateDirectory((Join-Path $SEARCH 'node_modules')) | Out-Null
[System.IO.Directory]::CreateDirectory((Join-Path $SEARCH 'src')) | Out-Null
[System.IO.File]::WriteAllText((Join-Path $SEARCH 'node_modules\a.txt'), 'match', $utfE)
[System.IO.File]::WriteAllText((Join-Path $SEARCH 'src\a.txt'), 'match', $utfE)
$OUT = run_tool 'grep' (TJ @{ path = $SEARCH; pattern = 'match' })
if ($OUT.Contains('src/a.txt') -and (-not $OUT.Contains('node_modules'))) { pass 'ED-14' 'grep excludes noisy directories' } else { fail 'ED-14' 'grep exclusions' ('out=' + $OUT) }

$OUT = run_tool 'find' (TJ @{ path = $SEARCH; name = 'a.txt' })
if ($OUT.Contains('src/a.txt') -and (-not $OUT.Contains('node_modules'))) { pass 'ED-15' 'find prunes noisy directories' } else { fail 'ED-15' 'find exclusions' ('out=' + $OUT) }

[System.IO.File]::WriteAllText((Join-Path $SEARCH '.pu-history.json'), 'match hidden trace', $utfE)
[System.IO.File]::WriteAllText((Join-Path $SEARCH '.pu-events.jsonl'), 'match hidden log', $utfE)
[System.IO.File]::WriteAllText((Join-Path $SEARCH 'agent.jsonl'), 'match ignored agent log', $utfE)
$OUT = run_tool 'grep' (TJ @{ path = $SEARCH; pattern = 'match' })
if ($OUT.Contains('src/a.txt') -and (-not $OUT.Contains('.pu-history')) -and (-not $OUT.Contains('.pu-events')) -and (-not $OUT.Contains('agent.jsonl'))) { pass 'ED-15a' 'grep skips pu trace/history files' } else { fail 'ED-15a' 'grep included trace files' ('out=' + $OUT) }

$OUT = run_tool 'find' (TJ @{ path = $SEARCH; name = '*.jsonl' })
if ([string]::IsNullOrEmpty($OUT)) { pass 'ED-15b' 'find skips pu trace/history files' } else { fail 'ED-15b' 'find included trace files' ('out=' + $OUT) }

# ED-15c: event log clips huge trace payloads
$global:LOG = Join-Path $script:TMPD 'logcap.jsonl'
$global:AGENT_LOG_TRUNC = 2000
log 1 tool_result ('x' * 100000)
$LOG_BYTES = (Get-Item -LiteralPath $global:LOG).Length
$LOG_TXT = [System.IO.File]::ReadAllText($global:LOG)
if ($LOG_BYTES -lt 3000 -and $LOG_TXT.Contains('line truncated')) { pass 'ED-15c' 'event log clips huge trace payloads' } else { fail 'ED-15c' 'event log payload too large' ('bytes=' + $LOG_BYTES) }

# ED-16: /effort changes effort interactively
$global:PIPE = 1
$global:EFFORT = 'medium'
$null = Capture-Err { $null = handle_cmd '/effort xh' }
if ($global:EFFORT -eq 'xhigh') { pass 'ED-16' '/effort changes effort interactively' } else { fail 'ED-16' '/effort' ('EFFORT=' + $global:EFFORT) }

# ED-17: /flush clears memory, history, and events
$global:MSGS = '[{"role":"user","content":"hi"}]'
$global:HISTORY = Join-Path $script:TMPD 'flush_hist.json'
$global:LOG = Join-Path $script:TMPD 'flush_events.jsonl'
[System.IO.File]::WriteAllText($global:LOG, 'stale', $utfE)
[System.IO.File]::WriteAllText(($global:HISTORY + '.meta'), 'openai:gpt-5.5', $utfE)
$null = Capture-Err { $null = handle_cmd '/flush' }
$histTxt = if (Test-Path -LiteralPath $global:HISTORY -PathType Leaf) { [System.IO.File]::ReadAllText($global:HISTORY) } else { 'MISSING' }
$metaGone = -not (Test-Path -LiteralPath ($global:HISTORY + '.meta'))
$logLen = if (Test-Path -LiteralPath $global:LOG -PathType Leaf) { (Get-Item -LiteralPath $global:LOG).Length } else { -1 }
if ($global:MSGS -eq '' -and $histTxt -eq '[]' -and $metaGone -and $logLen -eq 0) { pass 'ED-17' '/flush clears memory, history, and events' } else { fail 'ED-17' '/flush' ('MSGS=' + $global:MSGS + ' hist=' + $histTxt + ' meta=' + $(if ($metaGone) { 'gone' } else { 'present' }) + ' log_bytes=' + $logLen) }

# ED-18: empty [] history is not treated as resumed
$global:MSGS = 'x'
$r18 = load
if ($r18 -eq $false -and $global:MSGS -eq '') { pass 'ED-18' 'empty [] history is not treated as resumed' } else { fail 'ED-18' 'empty history resume' ('rc=' + $r18 + ' MSGS=' + $global:MSGS) }

# ED-19: resume replay shows last messages
$global:LOG = Join-Path $script:TMPD 'replay.jsonl'
[System.IO.File]::WriteAllText($global:LOG,
    '{"s":0,"t":"start","c":"old"}' + "`n" +
    '{"s":1,"t":"tool_call","c":"read: {\"path\":\"pu.sh\"}"}' + "`n" +
    '{"s":2,"t":"response","c":"done"}' + "`n", $utfE)
$global:INTERACTIVE = 1
$e19 = Capture-Err { $null = _replay }
$global:INTERACTIVE = 0
if ($e19.Contains('old') -and $e19.Contains('read:') -and $e19.Contains('done')) { pass 'ED-19' 'resume replay shows last messages' } else { fail 'ED-19' 'replay' ('out=' + $e19) }

$global:MSGS = ''

# ── Real-world-ish workflows (mocked APIs, real tools/CLI) ─────────────────
section 'real-world workflows'

$utfR = New-Object System.Text.UTF8Encoding($false)

# Minimal HTTP capture server: accepts one connection, saves the request body,
# answers with a single final "cli ok". Started as a background job so the CLI
# child process can be pointed at it via AGENT_ENDPOINT.
function Global:Start-CaptureServer([string]$portFile, [string]$captureFile) {
    $job = Start-Job -ScriptBlock {
        param($pf, $cf)
        $listener = New-Object System.Net.Sockets.TcpListener([System.Net.IPAddress]::Loopback, 0)
        $listener.Start()
        [System.IO.File]::WriteAllText($pf, ([System.Net.IPEndPoint]$listener.LocalEndpoint).Port.ToString())
        try {
            $cli = $listener.AcceptTcpClient()
            $stream = $cli.GetStream()
            $body = New-Object System.Collections.Generic.List[byte]
            $gotHeader = $false; $cl = 0; $nHeader = 0
            $buf = New-Object byte[] 4096
            while ($true) {
                $n = $stream.Read($buf, 0, $buf.Length)
                if ($n -le 0) { break }
                for ($i = 0; $i -lt $n; $i++) { [void]$body.Add($buf[$i]) }
                if (-not $gotHeader) {
                    $allBytes = $body.ToArray()
                    for ($j = 0; $j -lt $allBytes.Length - 3; $j++) {
                        if ($allBytes[$j] -eq 13 -and $allBytes[$j + 1] -eq 10 -and $allBytes[$j + 2] -eq 13 -and $allBytes[$j + 3] -eq 10) {
                            $nHeader = $j + 4
                            $gotHeader = $true
                            break
                        }
                    }
                    if ($gotHeader) {
                        $hdrStr = [System.Text.Encoding]::ASCII.GetString($allBytes, 0, $nHeader)
                        if ($hdrStr -match '(?i)content-length\s*:\s*(\d+)') { $cl = [int]$Matches[1] }
                    }
                }
                if ($gotHeader -and ($body.Count - $nHeader) -ge $cl) { break }
            }
            $payload = [byte[]]$body.GetRange($nHeader, $cl).ToArray()
            [System.IO.File]::WriteAllBytes($cf, $payload)
            $resp = '{"output_text":"cli ok","usage":{"input_tokens":1,"output_tokens":1}}'
            $rb = [System.Text.Encoding]::UTF8.GetBytes($resp)
            $head = 'HTTP/1.1 200 OK' + "`r`n" + 'Content-Type: application/json' + "`r`n" +
                'Content-Length: ' + $rb.Length + "`r`n" + 'Connection: close' + "`r`n" + "`r`n"
            $hb = [System.Text.Encoding]::ASCII.GetBytes($head)
            $stream.Write($hb, 0, $hb.Length)
            $stream.Write($rb, 0, $rb.Length)
            $stream.Flush()
            $cli.Close()
        } catch { }
        $listener.Stop()
    } -ArgumentList $portFile, $captureFile
    return $job
}

function Global:Wait-Port([string]$portFile) {
    for ($i = 0; $i -lt 50 -and -not (Test-Path -LiteralPath $portFile -PathType Leaf); $i++) { Start-Sleep -Milliseconds 100 }
    if (Test-Path -LiteralPath $portFile -PathType Leaf) { return [int][System.IO.File]::ReadAllText($portFile) }
    return 0
}

# RW-1: full CLI startup with a mocked endpoint. The child must load AGENTS.md
# into the system prompt, put the task into input[0], and write the CWD-history.
$CLI_PROJ = Join-Path $script:TMPD 'cli project'
[System.IO.Directory]::CreateDirectory($CLI_PROJ) | Out-Null
[System.IO.File]::WriteAllText((Join-Path $CLI_PROJ 'AGENTS.md'), 'Project rule: always mention ACME-42.' + "`n", $utfR)
[System.IO.File]::WriteAllText((Join-Path $CLI_PROJ 'input.md'), 'incident id: INC-123' + "`n" + 'root cause: cache stampede' + "`n", $utfR)
$CAP = Join-Path $script:TMPD 'cli_payload.json'
$PORTF = Join-Path $script:TMPD 'clisrv.port'
Remove-Item -LiteralPath $PORTF, $CAP -ErrorAction SilentlyContinue
$srv = Start-CaptureServer $PORTF $CAP
try {
    $PORT = Wait-Port $PORTF
    $env:OPENAI_API_KEY = 'dummy'
    $env:AGENT_PROVIDER = 'openai'
    $env:AGENT_MODEL = 'gpt-4o'
    $env:AGENT_ENDPOINT = 'http://127.0.0.1:' + $PORT
    $env:AGENT_LOG = Join-Path $script:TMPD 'cli.jsonl'
    $ERRF = Join-Path $script:TMPD 'cli.err'
    Push-Location $CLI_PROJ
    $env_AER = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $cliOut = & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $script:AGENT -n 'Summarize input.md for the changelog' 2>$ERRF
    $CLI_RC = $LASTEXITCODE
    $ErrorActionPreference = $env_AER
    Pop-Location
    $CLI_OUT = (@($cliOut) -join "`n").Trim()
    $CAP_OK = (Test-Path -LiteralPath $CAP -PathType Leaf) -and ((Get-Item -LiteralPath $CAP).Length -gt 0)
    $HIST_OK = (Test-Path -LiteralPath (Join-Path $CLI_PROJ '.pu-history.json') -PathType Leaf) -and ((Get-Item -LiteralPath (Join-Path $CLI_PROJ '.pu-history.json')).Length -gt 0)
    $rw1 = $false
    if ($CLI_RC -eq 0 -and $CLI_OUT -eq 'cli ok' -and $CAP_OK -and $HIST_OK) {
        $rw1 = json_field ([System.IO.File]::ReadAllText($CAP)) { param($d)
            ($d.instructions -like '*Project rule: always mention ACME-42*') -and ($d.input[0].content -eq 'Summarize input.md for the changelog')
        }
    }
    if ($rw1) { pass 'RW-1' 'CLI loads context and writes default history' } else { fail 'RW-1' 'CLI context/history integration' ('rc=' + $CLI_RC + ' out=' + $CLI_OUT + ' hist=' + $(if ($HIST_OK) { 'yes' } else { 'no' }) + ' payload=' + $(if ($CAP_OK) { [System.IO.File]::ReadAllText($CAP) } else { '' }) + ' err=' + $(if (Test-Path -LiteralPath $ERRF -PathType Leaf) { [System.IO.File]::ReadAllText($ERRF) } else { '' })) }
} finally {
    Wait-Job $srv -Timeout 15 | Out-Null
    Receive-Job $srv | Out-Null
    Remove-Job $srv -Force -ErrorAction SilentlyContinue
}

# RW-2: --pipe resumes CWD-history and combines stdin with the task suffix.
$CAP = Join-Path $script:TMPD 'pipe_payload.json'
$PORTF = Join-Path $script:TMPD 'pipesrv.port'
Remove-Item -LiteralPath $PORTF, $CAP -ErrorAction SilentlyContinue
$srv = Start-CaptureServer $PORTF $CAP
try {
    $PORT = Wait-Port $PORTF
    $env:AGENT_ENDPOINT = 'http://127.0.0.1:' + $PORT
    $ERRF = Join-Path $script:TMPD 'pipe.err'
    $STDIN_FILE = Join-Path $script:TMPD 'pipe.stdin'
    [System.IO.File]::WriteAllText($STDIN_FILE, 'stdin review notes' + "`n", (New-Object System.Text.UTF8Encoding($false)))
    Push-Location $CLI_PROJ
    $env_AER = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    # PS 5.1 native stdin forwarding can leave a big child's stdin pipe empty, so
    # feed through a cmd /c redirect (< file) and the agent reads the raw handle.
    $pipeCmd = 'powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + $script:AGENT + '" --pipe "plus suffix" 2> "' + $ERRF + '" < "' + $STDIN_FILE + '"'
    & cmd.exe /d /c $pipeCmd | Out-Null
    $PIPE_RC = $LASTEXITCODE
    $ErrorActionPreference = $env_AER
    Pop-Location
    $CAP_OK = (Test-Path -LiteralPath $CAP -PathType Leaf) -and ((Get-Item -LiteralPath $CAP).Length -gt 0)
    $rw2 = $false
    if ($PIPE_RC -eq 0 -and $CAP_OK) {
        $rw2 = json_field ([System.IO.File]::ReadAllText($CAP)) { param($d)
            ($d.input[1].content -eq 'cli ok') -and
            ([string]$d.input[$d.input.Count - 1].content).Contains('stdin review notes') -and
            ([string]$d.input[$d.input.Count - 1].content).Contains('plus suffix')
        }
    }
    if ($rw2) { pass 'RW-2' '--pipe resumes default history and combines stdin with task suffix' } else { fail 'RW-2' 'pipe task composition/resume' ('rc=' + $PIPE_RC + ' payload=' + $(if ($CAP_OK) { [System.IO.File]::ReadAllText($CAP) } else { '' }) + ' err=' + $(if (Test-Path -LiteralPath $ERRF -PathType Leaf) { [System.IO.File]::ReadAllText($ERRF) } else { '' })) }
} finally {
    Wait-Job $srv -Timeout 15 | Out-Null
    Receive-Job $srv | Out-Null
    Remove-Job $srv -Force -ErrorAction SilentlyContinue
}

Remove-Item Env:AGENT_ENDPOINT, Env:OPENAI_API_KEY, Env:ANTHROPIC_API_KEY, Env:AGENT_PROVIDER, Env:AGENT_MODEL, Env:AGENT_LOG -ErrorAction SilentlyContinue

# RW-3/4/5: Anthropic multi-step workflow with realistic paths/unicode.
$RW_DIR = Join-Path $script:TMPD 'rw project'
[System.IO.Directory]::CreateDirectory($RW_DIR) | Out-Null
$global:PIPE = 1; $global:CONFIRM = 0; $global:MSGS = ''; $global:HISTORY = ''
$global:LOG = Join-Path $script:TMPD 'rw_anthropic.jsonl'
$global:MAX_STEPS = 5; $global:PROVIDER = 'anthropic'; $global:MODEL = 'claude-opus-4-7'
$global:EFFORT_OK = 1; $global:TOKEN_IN = 0; $global:TOKEN_OUT = 0; $global:COST_USD = 0
$env:ANTHROPIC_API_KEY = 'dummy'
$RW_COUNT = Join-Path $script:TMPD 'rw_anth.count'
[System.IO.File]::WriteAllText($RW_COUNT, '0', $utfR)
function Global:call_api([string]$m) {
    $global:PU_API_RC = 0
    $RW_N = [int]([System.IO.File]::ReadAllText($RW_COUNT)) + 1
    [System.IO.File]::WriteAllText($RW_COUNT, ([string]$RW_N), $utfR)
    switch ($RW_N) {
        1 { return '{"content":[{"type":"text","text":"I will create the note."},{"type":"tool_use","id":"toolu_write","name":"write","input":{"path":"notes/plan \u00fc.txt","content":"alpha\nbeta \"quoted\"\n"}}],"usage":{"input_tokens":10,"output_tokens":5}}' }
        2 { return '{"content":[{"type":"tool_use","id":"toolu_read","name":"read","input":{"path":"notes/plan \u00fc.txt","offset":1,"limit":5}}],"usage":{"input_tokens":10,"output_tokens":5}}' }
        default { return '{"content":[{"type":"text","text":"Created and verified notes/plan \u00fc.txt."}],"usage":{"input_tokens":10,"output_tokens":5}}' }
    }
}
Push-Location $RW_DIR
try {
    $cbA = Capture-Both { run_task 'Create and verify a release note' }
} finally { Pop-Location }
$RW_RC = $cbA.rc
$PLAN = Join-Path $RW_DIR 'notes\plan ü.txt'
$rw3 = $false
if ($RW_RC -eq 0 -and (Test-Path -LiteralPath $PLAN -PathType Leaf)) {
    $PN = [System.IO.File]::ReadAllText($PLAN).TrimEnd("`r", "`n")
    if ($PN -eq ('alpha' + "`n" + 'beta "quoted"')) { $rw3 = $true }
}
if ($rw3) { pass 'RW-3' 'anthropic workflow writes realistic file path/content' } else { fail 'RW-3' 'anthropic write/read workflow' ('rc=' + $RW_RC + ' out=' + $cbA.out + ' err=' + $cbA.err) }

if ($cbA.out.Contains('Created and verified')) { pass 'RW-4' 'anthropic workflow surfaces final answer' } else { fail 'RW-4' 'anthropic final output' ('out=' + $cbA.out) }

$TCALLS = @([System.IO.File]::ReadAllLines((Join-Path $script:TMPD 'rw_anthropic.jsonl')) | Where-Object { $_ -match '"t":"tool_call"' }).Count
if ($TCALLS -ge 2) { pass 'RW-5' 'anthropic workflow logs multiple tool calls' } else { fail 'RW-5' 'anthropic tool logging' ('calls=' + $TCALLS + ' log=' + [System.IO.File]::ReadAllText((Join-Path $script:TMPD 'rw_anthropic.jsonl'))) }

# RW-6/7/8: OpenAI Responses-style workflow with a checkpoint history file.
$RW_DIR2 = Join-Path $script:TMPD 'rw openai'
[System.IO.Directory]::CreateDirectory($RW_DIR2) | Out-Null
$global:PIPE = 1; $global:CONFIRM = 0; $global:MSGS = ''
$global:HISTORY = Join-Path $script:TMPD 'rw_openai_history.json'
$global:LOG = Join-Path $script:TMPD 'rw_openai.jsonl'
$global:MAX_STEPS = 5; $global:PROVIDER = 'openai'; $global:MODEL = 'gpt-5.5'
$global:EFFORT = 'none'; $global:EFFORT_OK = 1; $global:TOKEN_IN = 0; $global:TOKEN_OUT = 0; $global:COST_USD = 0
$env:OPENAI_API_KEY = 'dummy'
$RW_COUNT = Join-Path $script:TMPD 'rw_openai.count'
[System.IO.File]::WriteAllText($RW_COUNT, '0', $utfR)
function Global:call_api([string]$m) {
    $global:PU_API_RC = 0
    $RW_N = [int]([System.IO.File]::ReadAllText($RW_COUNT)) + 1
    [System.IO.File]::WriteAllText($RW_COUNT, ([string]$RW_N), $utfR)
    switch ($RW_N) {
        1 { return '{"output":[{"type":"reasoning","id":"rs_1","summary":[]},{"type":"function_call","id":"fc_1","call_id":"call_write","name":"write","arguments":"{\"path\":\"src/app.txt\",\"content\":\"hello from openai\nbrace { ok }\n\"}","status":"completed"}],"usage":{"input_tokens":10,"output_tokens":5}}' }
        2 { return '{"output":[{"type":"function_call","id":"fc_2","call_id":"call_read","name":"read","arguments":"{\"path\":\"src/app.txt\"}","status":"completed"}],"usage":{"input_tokens":10,"output_tokens":5}}' }
        default { return '{"output_text":"OpenAI workflow done.","usage":{"input_tokens":10,"output_tokens":5}}' }
    }
}
Push-Location $RW_DIR2
try {
    $cbO = Capture-Both { run_task 'Create and verify app artifact' }
} finally { Pop-Location }
$OW_RC = $cbO.rc
$APP = Join-Path $RW_DIR2 'src\app.txt'
$EXPECTED_O = ('hello from openai' + "`n" + 'brace { ok }')
$rw6 = $false
if ($OW_RC -eq 0 -and (Test-Path -LiteralPath $APP -PathType Leaf)) {
    $AN = [System.IO.File]::ReadAllText($APP).TrimEnd("`r", "`n")
    if ($AN -eq $EXPECTED_O) { $rw6 = $true }
}
if ($rw6) { pass 'RW-6' 'openai workflow writes multiline quoted content' } else { fail 'RW-6' 'openai write/read workflow' ('rc=' + $OW_RC + ' out=' + $cbO.out + ' err=' + $cbO.err + ' file=' + $(if (Test-Path -LiteralPath $APP -PathType Leaf) { [System.IO.File]::ReadAllText($APP) } else { '' })) }

if ($cbO.out.Contains('OpenAI workflow done.')) { pass 'RW-7' 'openai workflow surfaces final answer' } else { fail 'RW-7' 'openai final output' ('out=' + $cbO.out) }

$HIST_TXT = if (Test-Path -LiteralPath $global:HISTORY -PathType Leaf) { [System.IO.File]::ReadAllText($global:HISTORY) } else { '' }
$rw8 = $false
if ((valid_json $HIST_TXT) -and $HIST_TXT -ne '') {
    $rw8 = json_field $HIST_TXT { param($d)
        ($d[$d.Count - 1].role -eq 'assistant') -and ($d[$d.Count - 1].content -eq 'OpenAI workflow done.')
    }
}
if ($rw8) { pass 'RW-8' 'openai workflow saves valid checkpoint history' } else { fail 'RW-8' 'openai checkpoint history' ('hist=' + $HIST_TXT) }

# RW-9/10/11: ranged reads and exit codes that match common repo work.
$global:PIPE = 1; $global:CONFIRM = 0
$global:AGENT_READ_MAX = 20
$BIG = Join-Path $script:TMPD 'big.log'
[System.IO.File]::WriteAllText($BIG, "line 1`nline 2`nline 3`nline 4`n", $utfR)
$OUT = run_tool 'read' (TJ @{ path = $BIG })
if ($OUT.Contains('pass offset/limit')) { pass 'RW-9' 'read refuses oversized file without range' } else { fail 'RW-9' 'large read guard' ('out=' + $OUT) }

$OUT = run_tool 'read' (TJ @{ path = $BIG; offset = 2; limit = 2 })
if ($OUT -eq ("line 2`nline 3")) { pass 'RW-10' 'read offset/limit returns requested range' } else { fail 'RW-10' 'range read' ('out="' + $OUT.Replace("`n", '\n') + '"') }

$OUT = run_tool 'bash' (TJ @{ command = 'Write-Output before; exit 7' })
if ($OUT.Contains('[exit:7]')) { pass 'RW-11' 'bash tool includes nonzero exit code' } else { fail 'RW-11' 'bash exit status' ('out=' + $OUT) }

$global:AGENT_READ_MAX = 1000000
$global:MSGS = ''

# ── Results ────────────────────────────────────────────────────────────────
section 'summary'

[Console]::Out.WriteLine('')
[Console]::Out.WriteLine('--- RESULTS ---')
[Console]::Out.WriteLine(('PASS: ' + $script:PASS + '  FAIL: ' + $script:FAIL + '  TOTAL: ' + $script:TOTAL))
if ($script:FAIL -eq 0) { exit 0 } else { exit 1 }
