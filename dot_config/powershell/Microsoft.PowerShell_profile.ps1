# Dot-source all scripts in profile.d/ (loaded in alphabetical order)
$profileDir = Join-Path (Split-Path $PSCommandPath -Parent) 'profile.d'
if (Test-Path $profileDir) {
  Get-ChildItem -Path $profileDir -Filter '*.ps1' | Sort-Object Name | ForEach-Object { . $_.FullName }
}
