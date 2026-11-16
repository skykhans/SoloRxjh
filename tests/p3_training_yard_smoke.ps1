param(
	[Parameter(Mandatory = $true)]
	[string]$Godot
)

$ErrorActionPreference = "Stop"
$godotPath = (Resolve-Path -LiteralPath $Godot).Path
$projectPath = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$testRoot = Join-Path $env:TEMP ("SoloRxjh-training-yard-" + [guid]::NewGuid().ToString("N"))
$previousLocalAppData = $env:LOCALAPPDATA
New-Item -ItemType Directory -Path $testRoot | Out-Null

try {
	$env:LOCALAPPDATA = $testRoot
	$testOutput = & $godotPath --headless --path $projectPath --script res://tests/training_yard_smoke.gd 2>&1 | Out-String
	if ($LASTEXITCODE -ne 0 -or $testOutput -match '(?m)^ERROR:|^SCRIPT ERROR:') {
		throw "Godot training yard smoke test failed:`n$testOutput"
	}
	$testOutput
}
finally {
	$env:LOCALAPPDATA = $previousLocalAppData
	if (Test-Path -LiteralPath $testRoot) {
		$resolvedRoot = (Resolve-Path -LiteralPath $testRoot).Path
		$resolvedTemp = (Resolve-Path -LiteralPath $env:TEMP).Path.TrimEnd("\") + "\"
		if (-not $resolvedRoot.StartsWith($resolvedTemp, [StringComparison]::OrdinalIgnoreCase)) {
			throw "Refusing to remove a test directory outside TEMP: $resolvedRoot"
		}
		Remove-Item -LiteralPath $resolvedRoot -Recurse -Force
	}
}
