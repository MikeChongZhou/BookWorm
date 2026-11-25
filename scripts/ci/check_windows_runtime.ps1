$ErrorActionPreference = 'Stop'
$folder = Join-Path $PWD 'build/windows/x64/runner/Release'
foreach ($name in @('bookworm.exe', 'flutter_windows.dll', 'msvcp140.dll', 'vcruntime140.dll', 'data/flutter_assets')) {
  if (!(Test-Path (Join-Path $folder $name))) { throw "Release package missing $name" }
}
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
$vs = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (!$vs) { throw 'Visual C++ tools not found' }
$tools = Get-ChildItem (Join-Path $vs 'VC/Tools/MSVC') -Directory | Sort-Object Name -Descending | Select-Object -First 1
$dumpbin = Join-Path $tools.FullName 'bin/Hostx64/x64/dumpbin.exe'
$binaries = Get-ChildItem $folder -Recurse -File | Where-Object { $_.Extension -in '.exe', '.dll' }
foreach ($file in $binaries) {
  $imports = (& $dumpbin /nologo /dependents $file.FullName 2>&1) -join "`n"
  if ($LASTEXITCODE -ne 0) { throw "Cannot inspect $($file.Name)" }
  if ($imports -match '(?im)\b(?:MSVCP\d+(?:_\d+)?D|VCRUNTIME\d+(?:_\d+)?D|ucrtbased)\.dll\b') {
    throw "Debug runtime dependency in $($file.Name): $($Matches[0])"
  }
}
Write-Host "Verified $($binaries.Count) Release binaries: no Debug CRT dependencies."
# Launch the actual executable on the runner, not a Flutter simulator.
$process = Start-Process (Join-Path $folder 'bookworm.exe') -WorkingDirectory $folder -PassThru
try {
  Start-Sleep -Seconds 12
  $process.Refresh()
  if ($process.HasExited) { throw "Release app exited during startup: $($process.ExitCode)" }
  Write-Host 'Release executable remained running through the startup check.'
} finally {
  if (!$process.HasExited) { Stop-Process -Id $process.Id -Force }
}
