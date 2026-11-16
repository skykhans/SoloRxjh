param(
	[Parameter(Mandatory = $true)]
	[string]$Godot
)

$ErrorActionPreference = "Stop"
$godotPath = (Resolve-Path -LiteralPath $Godot).Path
$projectPath = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$versionOutput = & $godotPath --version
if ($LASTEXITCODE -ne 0 -or $versionOutput.Trim() -ne "4.7.2.stable.official.ed1daf0bf") {
	throw "Unexpected Godot version: $versionOutput"
}

$importOutput = & $godotPath --headless --editor --path $projectPath --quit 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) {
	throw "Godot editor import check failed:`n$importOutput"
}

$probeOutput = & $godotPath --headless --path $projectPath --script res://tests/p1_smoke.gd 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) {
	throw "P1 runtime probe failed:`n$probeOutput"
}

$rulesOutput = & $godotPath --headless --path $projectPath --script res://tests/random_stream.gd 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) {
	throw "Random stream rule tests failed:`n$rulesOutput"
}

if ($probeOutput -match "P1_CONFIG_STATUS=missing") {
	$runtimeOutput = & $godotPath --headless --path $projectPath --quit-after 2 2>&1 | Out-String
	if ($LASTEXITCODE -eq 0 -or $runtimeOutput -notmatch "没有正式 JSON 配置文件") {
		throw "Missing JSON configuration did not fail startup clearly:`n$runtimeOutput"
	}
}
else {
	$runtimeOutput = & $godotPath --headless --path $projectPath --quit-after 2 2>&1 | Out-String
	if ($LASTEXITCODE -ne 0) {
		throw "Godot startup/exit check failed:`n$runtimeOutput"
	}
}

"Godot $($versionOutput.Trim()) P1 checks passed."
