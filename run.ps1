param(
	[Parameter(Mandatory = $true)]
	[string]$Godot
)

$ErrorActionPreference = "Stop"
$godotPath = (Resolve-Path -LiteralPath $Godot).Path
$projectPath = (Resolve-Path -LiteralPath $PSScriptRoot).Path
$version = (& $godotPath --version 2>&1 | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $version -notmatch '^4\.7\.2\.stable\.official\.[0-9a-f]{9}$') {
	throw "需要 Godot 4.7.2 stable；当前引擎报告版本：$version"
}

$quotedProjectPath = '"' + $projectPath + '"'
Start-Process `
	-FilePath $godotPath `
	-ArgumentList @("--path", $quotedProjectPath) `
	-WorkingDirectory $projectPath
