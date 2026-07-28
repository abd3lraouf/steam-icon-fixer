# Steam Shortcut Fixer - bootstrap launcher
# One-liner:  irm https://raw.githubusercontent.com/abd3lraouf/steam-icon-fixer/main/ssf.ps1 | iex
$f = Join-Path $env:TEMP "ssf.cmd"
iwr "https://raw.githubusercontent.com/abd3lraouf/steam-icon-fixer/main/Create%20Steam%20Shortcuts.cmd" -OutFile $f
Start-Process -FilePath $f -Wait
Remove-Item $f -Force -EA SilentlyContinue
