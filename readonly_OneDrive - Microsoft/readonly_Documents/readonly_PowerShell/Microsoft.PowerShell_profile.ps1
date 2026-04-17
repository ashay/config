$configProfile = Join-Path $HOME '.config/powershell/Microsoft.PowerShell_profile.ps1'
if (Test-Path $configProfile) { . $configProfile }
