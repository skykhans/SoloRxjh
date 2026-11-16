param(
	[Parameter(Mandatory = $true)]
	[string]$Godot
)

$ErrorActionPreference = "Stop"
$godotPath = (Resolve-Path -LiteralPath $Godot).Path
$projectPath = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
$versionOutput = & $godotPath --headless --version 2>&1 | Out-String
if ($LASTEXITCODE -ne 0 -or $versionOutput.Trim() -ne "4.7.2.stable.official.ed1daf0bf") {
	throw "Unexpected Godot version: $versionOutput"
}
$testRoot = Join-Path $env:TEMP ("SoloRxjh-save-dir-" + [guid]::NewGuid().ToString("N"))
$overrideRoot = Join-Path $testRoot "override"
$defaultRoot = Join-Path $testRoot "default-local-app-data"
$relativeOverrideRoot = [System.IO.Path]::GetRelativePath($projectPath, $overrideRoot)
New-Item -ItemType Directory -Path $testRoot | Out-Null
$originalLocalAppData = $env:LOCALAPPDATA

Push-Location -LiteralPath $projectPath
try {
	$argumentOutput = & $godotPath --headless --path $projectPath --script res://tests/save_dir_arguments_smoke.gd 2>&1 | Out-String
	if ($LASTEXITCODE -ne 0 -or $argumentOutput -notmatch "SAVE_DIR_ARGUMENTS_SMOKE=passed") {
		throw "Save directory argument checks failed:`n$argumentOutput"
	}

	$env:LOCALAPPDATA = $defaultRoot
	$runtimeOutput = & $godotPath --headless --path $projectPath --quit-after 2 -- --save-dir $relativeOverrideRoot 2>&1 | Out-String
	if ($LASTEXITCODE -ne 0) {
		throw "Isolated --save-dir startup failed:`n$runtimeOutput"
	}
	$overrideProfiles = Join-Path $overrideRoot "profiles"
	$defaultProfiles = Join-Path $defaultRoot "SoloRxjh\profiles"
	if (-not (Test-Path -LiteralPath $overrideProfiles -PathType Container)) {
		throw "The override profiles directory was not created:`n$runtimeOutput"
	}
	if (Test-Path -LiteralPath $defaultProfiles) {
		throw "The LOCALAPPDATA default directory was used despite --save-dir."
	}

	$missingPathOutput = & $godotPath --headless --path $projectPath -- --save-dir 2>&1 | Out-String
	if ($LASTEXITCODE -eq 0 -or $missingPathOutput -notmatch "--save-dir 缺少") {
		throw "A missing --save-dir value was not rejected:`n$missingPathOutput"
	}

	$duplicateOutput = & $godotPath --headless --path $projectPath -- --save-dir $overrideRoot --save-dir $defaultRoot 2>&1 | Out-String
	if ($LASTEXITCODE -eq 0 -or $duplicateOutput -notmatch "启动参数重复") {
		throw "A duplicate --save-dir was not rejected:`n$duplicateOutput"
	}

	$unknownOutput = & $godotPath --headless --path $projectPath -- --unsupported 2>&1 | Out-String
	if ($LASTEXITCODE -eq 0 -or $unknownOutput -notmatch "不支持的启动参数") {
		throw "An unknown startup argument was not rejected:`n$unknownOutput"
	}

	"Godot $($versionOutput.Trim()) --save-dir checks passed."
}
finally {
	if ($null -eq $originalLocalAppData) {
		Remove-Item Env:LOCALAPPDATA -ErrorAction SilentlyContinue
	}
	else {
		$env:LOCALAPPDATA = $originalLocalAppData
	}
	Pop-Location
	if (Test-Path -LiteralPath $testRoot) {
		$resolvedRoot = (Resolve-Path -LiteralPath $testRoot).Path
		$resolvedTemp = (Resolve-Path -LiteralPath $env:TEMP).Path.TrimEnd("\") + "\"
		if (-not $resolvedRoot.StartsWith($resolvedTemp, [StringComparison]::OrdinalIgnoreCase)) {
			throw "Refusing to remove a test directory outside TEMP: $resolvedRoot"
		}
		Remove-Item -LiteralPath $resolvedRoot -Recurse -Force
	}
}
