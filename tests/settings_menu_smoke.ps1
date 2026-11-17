param(
	[Parameter(Mandatory = $true)]
	[string]$Godot
)

$ErrorActionPreference = "Stop"
$godotPath = (Resolve-Path -LiteralPath $Godot).Path
$projectPath = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$testRoot = Join-Path $env:TEMP ("SoloRxjh-settings-menu-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $testRoot | Out-Null

try {
	$testOutput = & $godotPath --headless --path $projectPath --script res://tests/settings_menu_smoke.gd -- --save-dir $testRoot 2>&1 | Out-String
	if ($LASTEXITCODE -ne 0) {
		throw "Settings menu smoke test failed:`n$testOutput"
	}
	$testOutput
}
finally {
	if (Test-Path -LiteralPath $testRoot) {
		$resolvedRoot = (Resolve-Path -LiteralPath $testRoot).Path
		$resolvedTemp = (Resolve-Path -LiteralPath $env:TEMP).Path.TrimEnd("\") + "\"
		if (-not $resolvedRoot.StartsWith($resolvedTemp, [StringComparison]::OrdinalIgnoreCase)) {
			throw "Refusing to remove a test directory outside TEMP: $resolvedRoot"
		}
		Remove-Item -LiteralPath $resolvedRoot -Recurse -Force
	}
}
