# Steam Shortcut Fixer

**Automatically creates and repairs Steam game shortcuts with real `.ico` icons from Steam's CDN. No admin or UAC required.**

## What it does

- Scans your Steam libraries for installed games
- Downloads real game icons from Steam's CDN (Fastly or Cloudflare)
- Creates proper `.url` shortcuts on **Desktop** and **Start Menu**
- Fixes existing shortcuts that have broken or fallback icons
- Removes orphaned shortcuts for uninstalled games
- Handles Unicode game names (e.g. Battlefield™ 6)

## Requirements

- Windows 10/11
- Steam installed
- `curl.exe` (built into Windows 10+)

## Usage

Double-click `Create Steam Shortcuts.cmd` and follow the prompts:

1. **Scan** — detects your Steam install, libraries, and games
2. **Select** — pick games by number (e.g. `1,3`), `A` for all, or `N` to skip
3. **CDN** — choose icon CDN (Fastly default, or Cloudflare)
4. **Process** — downloads icons, creates/fixes shortcuts, cleans orphans

## One-liner

```powershell
irm https://raw.githubusercontent.com/abd3lraouf/steam-icon-fixer/main/ssf.ps1 | iex
```

Pastes into PowerShell and launches the tool in its own window. The `ssf.ps1` bootstrap downloads the latest `Create Steam Shortcuts.cmd` and runs it, so you always get the current version.

## How it works

The script is a polyglot `.cmd`/`.bat` + PowerShell file that uses a two-phase architecture to bypass Windows Defender's AMSI scanning:

1. **SCAN phase** — extracts the PowerShell section to a temp `.ps1`, pipes it via stdin (bypasses AMSI), displays the game list, then exits
2. **User input** — CMD's `set /p` handles interactive prompts for game and CDN selection
3. **RUN phase** — pipes the script again via stdin, reads selections from environment variables, processes shortcuts

Icons are fetched from `api.steamcmd.net` for the `clienticon` hash, then downloaded from the chosen CDN as `.ico` files to `Steam\steam\games\`.

## Author

**abd3lraouf** — [GitHub](https://github.com/abd3lraouf)