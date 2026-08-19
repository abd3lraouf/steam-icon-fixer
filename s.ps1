# Steam Shortcut Fixer - bootstrap launcher
# One-liner:  irm github.com/abd3lraouf/steam-icon-fixer/raw/main/s.ps1|iex
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor 3072
$f = Join-Path $env:TEMP 'ssf-gui.ps1'
iwr 'https://github.com/abd3lraouf/steam-icon-fixer/raw/main/Steam-Shortcut-Fixer.ps1' -OutFile $f -UseBasicParsing

# Always run the GUI on Windows PowerShell 5.1 in an STA: the embedded C# toolkit
# is compiled against the desktop WinForms/GDI+ assemblies, which PowerShell 7
# resolves differently. Works from pwsh, powershell.exe or Windows Terminal alike.
#
# -WindowStyle Hidden is passed to powershell.exe, NOT to Start-Process: as a
# Start-Process switch it sets SW_HIDE in the child's STARTUPINFO, which WinForms
# then applies to the first window it shows - the app would run with no window.
$ps51 = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
if (-not (Test-Path -LiteralPath $ps51)) { $ps51 = 'powershell.exe' }
Start-Process -Wait $ps51 -ArgumentList "-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File `"$f`""

Remove-Item $f -Force -EA SilentlyContinue
