param(
	[Parameter(Mandatory = $true)]
	[string]$Godot
)

$ErrorActionPreference = "Stop"
$godotPath = (Resolve-Path -LiteralPath $Godot).Path
$projectPath = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$testOutput = & $godotPath --headless --path $projectPath --script res://tests/settings_runtime_smoke.gd 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) {
	throw "Runtime settings smoke test failed:`n$testOutput"
}
$testOutput
