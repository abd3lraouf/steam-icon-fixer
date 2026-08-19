# Steam Shortcut Fixer - bootstrap launcher
# One-liner:  irm github.com/abd3lraouf/steam-icon-fixer/raw/main/s.ps1|iex
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor 3072
$f = Join-Path $env:TEMP 'ssf-gui.ps1'
iwr 'https://github.com/abd3lraouf/steam-icon-fixer/raw/main/Steam-Shortcut-Fixer.ps1' -OutFile $f -UseBasicParsing
if ([Threading.Thread]::CurrentThread.GetApartmentState() -eq [Threading.ApartmentState]::STA) {
    & $f   # blocks until the GUI window closes
} else {
    # WinForms needs a single-threaded apartment; PowerShell 7 and some hosts are MTA
    Start-Process -Wait powershell.exe -WindowStyle Hidden -ArgumentList "-NoProfile -ExecutionPolicy Bypass -STA -File `"$f`""
}
Remove-Item $f -Force -EA SilentlyContinue
