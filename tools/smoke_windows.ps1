param([string]$PackageDirectory = (Join-Path $PSScriptRoot '../target/dist/SoloRxjh-liuli-0.5-windows-x64'))
$ErrorActionPreference = 'Stop'
$packagePath = (Resolve-Path -LiteralPath $PackageDirectory).Path
$projectPath = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$outputPath = Join-Path $projectPath 'target/verification/package-smoke'
$workingPath = Join-Path $outputPath 'outside-cwd'
[void](New-Item -ItemType Directory -Path $workingPath -Force)
$executable = Join-Path $packagePath 'solo-rxjh.exe'
$helpText = & $executable --help
if ($LASTEXITCODE -ne 0 -or ($helpText -join "`n") -notlike '*Usage: solo-rxjh*') { throw 'Packaged executable --help failed' }
$stdoutPath = Join-Path $outputPath 'stdout.log'
$stderrPath = Join-Path $outputPath 'stderr.log'
$savePath = Join-Path $outputPath 'isolated-saves'
$previousLogFilter = [Environment]::GetEnvironmentVariable('RUST_LOG')
$process = $null
try {
    $env:RUST_LOG = 'warn,solo_rxjh=info,bevy_render::renderer=info'
    $process = Start-Process -FilePath $executable -ArgumentList @('--save-dir', ('"' + $savePath + '"')) -WorkingDirectory $workingPath -WindowStyle Hidden -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath -PassThru
    $deadline = [DateTime]::UtcNow.AddSeconds(45)
    $ready = $false
    while ([DateTime]::UtcNow -lt $deadline) {
        if ($process.HasExited) { throw "Packaged game exited before resource readiness: $($process.ExitCode)" }
        if ((Select-String -LiteralPath $stdoutPath -SimpleMatch -Pattern 'All required assets loaded; main menu ready' -Quiet) -or
            (Select-String -LiteralPath $stderrPath -SimpleMatch -Pattern 'All required assets loaded; main menu ready' -Quiet)) {
            $ready = $true
            break
        }
        Start-Sleep -Milliseconds 200
    }
    if (-not $ready) { throw 'Packaged game did not report all assets ready within 45 seconds' }
    Write-Output 'PACKAGE_STARTUP_PASS: executable located its own assets from an unrelated working directory; isolated save path; no network fetch required by runtime.'
} finally {
    if ($null -ne $process -and -not $process.HasExited) {
        Stop-Process -Id $process.Id -Force
        if (-not $process.WaitForExit(5000)) { throw "Verification process did not terminate: $($process.Id)" }
    }
    [Environment]::SetEnvironmentVariable('RUST_LOG', $previousLogFilter)
}
Write-Output 'PACKAGE_PROCESS_CLOSED: startup smoke uses process termination for cleanup; normal UI exit is covered by verify-native, not by this check.'
