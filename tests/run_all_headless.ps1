param(
	[Parameter(Mandatory = $true)]
	[string]$Godot
)

$ErrorActionPreference = "Stop"
$godotPath = (Resolve-Path -LiteralPath $Godot).Path
$projectPath = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$testRoot = Join-Path $env:TEMP ("SoloRxjh-headless-" + [guid]::NewGuid().ToString("N"))
$originalLocalAppData = $env:LOCALAPPDATA
$originalTemp = $env:TEMP
$profileTests = @(
	"archive_file_lease_smoke.gd",
	"archive_capacity_smoke.gd",
	"p2_archive_profile_smoke.gd",
	"p2_archive_profile_settings_smoke.gd",
	"quit_menu_smoke.gd",
	"settings_menu_smoke.gd"
)
$scriptTests = @(
	"p1_smoke.gd",
	"canonical_json.gd",
	"character_creation_command.gd",
	"character_identity_validator.gd",
	"character_initial_components_smoke.gd",
	"character_template_catalog.gd",
	"level_award_history.gd",
	"random_stream.gd",
	"recommendation_delivery_transaction.gd",
	"recommendation_experience_award.gd",
	"recommendation_material_aggregation.gd",
	"settings_runtime_smoke.gd",
	"strict_json.gd",
	"training_yard_smoke.gd",
	"xuanbo_city_smoke.gd"
)

New-Item -ItemType Directory -Path $testRoot | Out-Null
try {
	$env:TEMP = $testRoot
	$versionOutput = & $godotPath --headless --version 2>&1 | Out-String
	if ($LASTEXITCODE -ne 0 -or $versionOutput.Trim() -ne "4.7.2.stable.official.ed1daf0bf") {
		throw "Unexpected Godot version: $versionOutput"
	}

	$importOutput = & $godotPath --headless --editor --path $projectPath --import 2>&1 | Out-String
	if ($LASTEXITCODE -ne 0 -or $importOutput -match '(?m)^ERROR:|SCRIPT ERROR:') {
		throw "Godot editor import check failed:`n$importOutput"
	}

	foreach ($testName in $scriptTests) {
		$testOutput = & $godotPath --headless --path $projectPath --script "res://tests/$testName" 2>&1 | Out-String
		if ($LASTEXITCODE -ne 0 -or $testOutput -match '(?m)^ERROR:|SCRIPT ERROR:') {
			throw "Headless test failed: $testName`n$testOutput"
		}
		"PASS $testName"
	}

	foreach ($testName in $profileTests) {
		$saveRoot = Join-Path $testRoot ([guid]::NewGuid().ToString("N"))
		if ($testName -eq "settings_menu_smoke.gd") {
			$testOutput = & $godotPath --headless --path $projectPath --script "res://tests/$testName" -- --save-dir $saveRoot 2>&1 | Out-String
		}
		else {
			$testOutput = & $godotPath --headless --path $projectPath --script "res://tests/$testName" -- $saveRoot 2>&1 | Out-String
		}
		if ($LASTEXITCODE -ne 0 -or $testOutput -match '(?m)^ERROR:|SCRIPT ERROR:') {
			throw "Headless test failed: $testName`n$testOutput"
		}
		"PASS $testName"
	}

	$saveDirOutput = & $godotPath --headless --path $projectPath --script res://tests/save_dir_arguments_smoke.gd 2>&1 | Out-String
	if ($LASTEXITCODE -ne 0 -or $saveDirOutput -match '(?m)^ERROR:|SCRIPT ERROR:') {
		throw "Save directory argument checks failed:`n$saveDirOutput"
	}
	"PASS save_dir_arguments_smoke.gd"

	$saveDirOutput = & (Join-Path $PSScriptRoot "save_dir_smoke.ps1") -Godot $godotPath 2>&1 | Out-String
	if ($saveDirOutput -match '(?m)^ERROR:|SCRIPT ERROR:') {
		throw "Save directory isolation smoke test failed:`n$saveDirOutput"
	}
	"PASS save_dir_smoke.ps1"

	$trainingOutput = & (Join-Path $PSScriptRoot "p3_training_yard_smoke.ps1") -Godot $godotPath 2>&1 | Out-String
	if ($trainingOutput -match '(?m)^ERROR:|SCRIPT ERROR:') {
		throw "Training yard integration smoke test failed:`n$trainingOutput"
	}
	"PASS p3_training_yard_smoke.ps1"
	"Godot $($versionOutput.Trim()) full headless regression passed."
}
finally {
	if ($null -eq $originalLocalAppData) {
		Remove-Item Env:LOCALAPPDATA -ErrorAction SilentlyContinue
	}
	else {
		$env:LOCALAPPDATA = $originalLocalAppData
	}
	$env:TEMP = $originalTemp
	if (Test-Path -LiteralPath $testRoot) {
		$resolvedRoot = (Resolve-Path -LiteralPath $testRoot).Path
		$resolvedTemp = (Resolve-Path -LiteralPath $env:TEMP).Path.TrimEnd("\") + "\"
		if (-not $resolvedRoot.StartsWith($resolvedTemp, [StringComparison]::OrdinalIgnoreCase)) {
			throw "Refusing to remove a test directory outside TEMP: $resolvedRoot"
		}
		Remove-Item -LiteralPath $resolvedRoot -Recurse -Force
	}
}
