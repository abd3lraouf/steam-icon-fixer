<# : batch script
@echo off
chcp 65001 >nul 2>&1
title abd3lraouf - Steam Shortcut Fixer v1.1.0
set "TMPFILE=%TEMP%\SteamShortcutFixer.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$c=Get-Content -LiteralPath '%~f0' -Raw -Encoding UTF8; $ps=$c -replace '(?s)^.*?#>\r?\n',''; [IO.File]::WriteAllText('%TMPFILE%',$ps,(New-Object Text.UTF8Encoding $false))"
set SSF_PHASE=SCAN
powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-Content -LiteralPath '%TMPFILE%' -Raw -Encoding UTF8 | powershell -NoProfile -ExecutionPolicy Bypass -Command -"
echo.
powershell -NoProfile -ExecutionPolicy Bypass -Command "Write-Host \"  Select games: 1,3 or A [A]: \" -NoNewline -ForegroundColor White"
set /p "SSF_GAMES="
if "%SSF_GAMES%"=="" set "SSF_GAMES=A"
echo.
powershell -NoProfile -ExecutionPolicy Bypass -Command "Write-Host \"  CDN: 0=Fastly 1=Cloudflare [0]: \" -NoNewline -ForegroundColor White"
set /p "SSF_CDN="
if "%SSF_CDN%"=="" set "SSF_CDN=0"
set SSF_PHASE=RUN
powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-Content -LiteralPath '%TMPFILE%' -Raw -Encoding UTF8 | powershell -NoProfile -ExecutionPolicy Bypass -Command -"
del "%TMPFILE%" 2>nul
pause
exit /b
#>

function Main {
    $e = [char]27
    $G = "$e[92m"; $R = "$e[91m"; $Y = "$e[93m"; $B = "$e[94m"
    $C = "$e[96m"; $P = "$e[95m"; $W = "$e[97m"; $D = "$e[90m"; $N = "$e[0m"
    $BOLD = "$e[1m"; $DIM = "$e[2m"

    $steamPath = Find-SteamInstall
    if (-not $steamPath) { Write-Host "`n  ${R}[-]${N} Steam not found!"; return }
    $steamExe = Join-Path $steamPath "steam.exe"
    $gamesDir = Join-Path $steamPath "steam\games"
    if (-not (Test-Path $gamesDir)) { New-Item -Path $gamesDir -ItemType Directory -Force | Out-Null }
    $libraries = Get-SteamLibraries $steamPath
    $installed = Get-InstalledGames $libraries
    $installedIds = @($installed | ForEach-Object { $_.AppId })

    if ($env:SSF_PHASE -eq "SCAN") {
        [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
        Clear-Host
        Write-Host ""
        Write-Host "  ${R}---------------------------------------------------------------${N}"
        Write-Host "  ${W}${BOLD}  Steam Shortcut Fixer${N}  ${D}v1.1.0${N}"
        Write-Host "  ${D}  by abd3lraouf${N}"
        Write-Host "  ${R}---------------------------------------------------------------${N}"
        Write-Host ""
        Write-Host "  ${C}${BOLD}[Step 1/3]${N} ${W}${BOLD}Discovering Steam...${N}"
        Write-Host ""
        Write-Host "  ${G}  [+]${N} Steam:       ${C}${steamPath}${N}"
        Write-Host "  ${G}  [+]${N} Libraries:   ${C}$($libraries.Count) found${N}"
        foreach ($lib in $libraries) { Write-Host "  ${D}                ${lib}${N}" }
        Write-Host ""
        Write-Host "  ${C}${BOLD}[Step 2/3]${N} ${W}${BOLD}Installed games${N}"
        Write-Host ""
        $gameColors = @($G, $C, $P, $B, $Y)
        for ($i = 0; $i -lt $installed.Count; $i++) {
            $color = $gameColors[$i % $gameColors.Count]
            $num = $i + 1
            $pad = if ($num -lt 10) { " " } else { "" }
            Write-Host "    ${color}${BOLD}[$num]${N}  ${W}$($installed[$i].Name)${N}  ${D}($($installed[$i].AppId))${N}"
        }
        Write-Host ""
        Write-Host "    ${G}${BOLD}[A]${N}  ${W}All games${N}  ${D}(default)${N}"
        Write-Host "    ${R}${BOLD}[N]${N}  ${W}None - skip${N}"
        Write-Host ""
        return
    }

    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    Clear-Host
    Write-Host ""
    Write-Host "  ${R}---------------------------------------------------------------${N}"
    Write-Host "  ${W}${BOLD}  Steam Shortcut Fixer${N}  ${D}v1.1.0${N}"
    Write-Host "  ${D}  by abd3lraouf${N}"
    Write-Host "  ${R}---------------------------------------------------------------${N}"

    $gamesInput = $env:SSF_GAMES
    $cdnInput = $env:SSF_CDN

    $targetGames = @()
    if ($gamesInput -eq "N" -or $gamesInput -eq "n") {
        Write-Host "`n  ${Y}[!]${N} No games selected, exiting"; return
    } elseif ($gamesInput -eq "A" -or $gamesInput -eq "a" -or $gamesInput -eq "") {
        $targetGames = $installed
    } else {
        $nums = $gamesInput -split "[,\s]+" | Where-Object { $_ -match "^\d+$" } | ForEach-Object { [int]$_ }
        foreach ($n in $nums) {
            if ($n -ge 1 -and $n -le $installed.Count) { $targetGames += $installed[$n - 1] }
        }
    }
    if ($targetGames.Count -eq 0) { Write-Host "`n  ${R}[-]${N} No valid selection, exiting"; return }

    Write-Host ""
    Write-Host "  ${C}${BOLD}[Step 1/3]${N} ${W}${BOLD}Configuration${N}"
    Write-Host ""

    if ($cdnInput -eq "1") {
        $cdnBase = "https://cdn.cloudflare.steamstatic.com/steamcommunity/public/images/apps"
        $cdnName = "Cloudflare"
    } else {
        $cdnBase = "https://shared.fastly.steamstatic.com/community_assets/images/apps"
        $cdnName = "Fastly"
    }
    Write-Host "  ${G}  [+]${N} CDN:          ${C}${cdnName}${N}"
    Write-Host "  ${G}  [+]${N} Games:        ${W}${BOLD}$($targetGames.Count)${N} selected"
    foreach ($tg in $targetGames) { Write-Host "  ${D}                $($tg.Name)${N}" }
    Write-Host ""

    Write-Host "  ${C}${BOLD}[Step 2/3]${N} ${W}${BOLD}Processing shortcuts...${N}"
    Write-Host ""

    $desktop = [Environment]::GetFolderPath("Desktop")
    $startMenu = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\Steam"
    $scanPaths = @($desktop)
    if (Test-Path $startMenu) { $scanPaths += $startMenu }
    $existing = Find-SteamShortcuts $scanPaths

    $desktopShortcuts = $existing | Where-Object { $_.Dir -eq $desktop }
    $startMenuShortcuts = $existing | Where-Object { $_.Dir -eq $startMenu }
    $targetIds = @($targetGames | ForEach-Object { $_.AppId })

    $needsIcon = @{}
    $needsNew = @()
    foreach ($game in $targetGames) {
        $ds = $desktopShortcuts | Where-Object { $_.AppId -eq $game.AppId }
        $sm = $startMenuShortcuts | Where-Object { $_.AppId -eq $game.AppId }
        if (($null -eq $ds) -or ($null -eq $sm)) { $needsNew += $game }
        elseif ($ds.NeedsRealIcon) { $needsIcon[$game.AppId] = $ds }
    }
    $orphaned = $existing | Where-Object { $targetIds -notcontains $_.AppId -and $installedIds -contains $_.AppId }

    $totalWork = $needsIcon.Count + $needsNew.Count
    $okCount = 0
    $failCount = 0
    $cleanedCount = 0
    $iconMap = @{}

    if ($totalWork -eq 0 -and $orphaned.Count -eq 0) {
        Write-Host "  ${C}  [*]${N} ${D}All shortcuts are up to date${N}"
    } else {
        foreach ($appId in $needsIcon.Keys) {
            $info = Get-SteamAppInfo $appId
            $gName = if ($info.Name) { Sanitize-Name $info.Name } else { $appId }
            Write-Host "  ${Y}  [~]${N} ${W}Fixing${N} ${P}${gName}${N}"
            if ($info -and $info.Hash) {
                $iconPath = Download-Icon $appId $info.Hash $gamesDir $cdnBase
                if ($iconPath) {
                    $iconMap[$appId] = $iconPath
                    $sc = $needsIcon[$appId]
                    $scName = if ($info.Name) { Sanitize-Name $info.Name } else { [System.IO.Path]::GetFileNameWithoutExtension($sc.Path) }
                    $newPath = Join-Path (Split-Path $sc.Path) "${scName}.url"
                    if ($sc.Path -ne $newPath) { Move-Item $sc.Path $newPath -Force -EA SilentlyContinue; $sc.Path = $newPath }
                    Write-UrlShortcut -Path $sc.Path -AppId $appId -IconPath $iconPath -SteamExe $steamExe
                    $okCount++
                    Write-Host "  ${G}  [+]${N} Icon fixed: ${D}$([System.IO.Path]::GetFileName($iconPath))${N}"
                } else { $failCount++; Write-Host "  ${R}  [-]${N} No icon available" }
            } else { $failCount++; Write-Host "  ${R}  [-]${N} API lookup failed" }
        }

        foreach ($game in $needsNew) {
            $appId = $game.AppId
            $name = Sanitize-Name $game.Name
            $iconPath = $null
            $info = Get-SteamAppInfo $appId
            if ($info) {
                if ($info.Name) { $name = Sanitize-Name $info.Name }
                if ($info.Hash -and -not $iconMap[$appId]) { $iconPath = Download-Icon $appId $info.Hash $gamesDir $cdnBase }
            }
            if (-not $iconPath -and $iconMap[$appId]) { $iconPath = $iconMap[$appId] }
            if ($iconPath) { $okCount++ } else { $failCount++ }

            $oldShortcuts = $existing | Where-Object { $_.AppId -eq $appId }
            foreach ($old in $oldShortcuts) {
                $oldName = [System.IO.Path]::GetFileNameWithoutExtension($old.Path)
                if ($oldName -ne $name) { Remove-Item $old.Path -Force -EA SilentlyContinue }
            }

            Write-Host ""
            $statusIcon = if ($iconPath) { "${G}  [+]${N}" } else { "${Y}  [!]${N}" }
            $iconNote = if ($iconPath) { "${D}$([System.IO.Path]::GetFileName($iconPath))${N}" } else { "${R}no icon${N}" }
            Write-Host "  ${statusIcon} ${W}${BOLD}${name}${N}  ${iconNote}"

            Write-UrlShortcut -Path (Join-Path $desktop "${name}.url") -AppId $appId -IconPath $iconPath -SteamExe $steamExe
            Write-Host "       ${G}Desktop${N}  ${D}${desktop}\${name}.url${N}"

            if (-not (Test-Path $startMenu)) { New-Item -Path $startMenu -ItemType Directory -Force | Out-Null }
            Write-UrlShortcut -Path (Join-Path $startMenu "${name}.url") -AppId $appId -IconPath $iconPath -SteamExe $steamExe
            Write-Host "       ${C}Menu${N}     ${D}${startMenu}\${name}.url${N}"
        }

        foreach ($sc in $orphaned) {
            if ($targetIds -contains $sc.AppId) { continue }
            Remove-Item $sc.Path -Force -EA SilentlyContinue
            $cleanedCount++
            Write-Host "  ${Y}  [!]${N} Removed orphan: ${D}$([System.IO.Path]::GetFileName($sc.Path))${N}"
        }
    }

    Write-Host ""
    Write-Host "  ${C}${BOLD}[Step 3/3]${N} ${W}${BOLD}Refreshing icons...${N}"
    Write-Host ""
    & ie4uinit.exe -show 2>$null
    Write-Host "  ${G}  [+]${N} Icons refreshed"

    Write-Host ""
    Write-Host "  ${C}---------------------------------------------------------------${N}"
    Write-Host "  ${W}${BOLD}  SUMMARY${N}"
    Write-Host "  ${C}---------------------------------------------------------------${N}"
    if ($okCount -gt 0)      { Write-Host "  ${G}  [+]+${N} Icons downloaded:   ${W}${BOLD}${okCount}${N}" }
    if ($needsIcon.Count -gt 0) { Write-Host "  ${G}  [+]+${N} Shortcuts fixed:    ${W}${BOLD}$($needsIcon.Count)${N}" }
    if ($cleanedCount -gt 0) { Write-Host "  ${Y}  [!]-${N} Orphans removed:    ${W}${BOLD}${cleanedCount}${N}" }
    if ($failCount -gt 0)    { Write-Host "  ${R}  [-]-${N} Failed/No icon:     ${W}${BOLD}${failCount}${N}" }
    if ($okCount -eq 0 -and $failCount -eq 0 -and $cleanedCount -eq 0) { Write-Host "  ${D}  No changes needed${N}" }
    Write-Host "  ${C}---------------------------------------------------------------${N}"
    Write-Host ""
    Write-Host "  ${D}  Done! Press any key to exit...${N}"
}

function Find-SteamInstall {
    foreach ($r in @("HKLM:\SOFTWARE\WOW6432Node\Valve\Steam","HKLM:\SOFTWARE\Valve\Steam","HKCU:\SOFTWARE\Valve\Steam")) {
        $p = (Get-ItemProperty $r -Name "InstallPath" -EA SilentlyContinue).InstallPath
        if ($p -and (Test-Path (Join-Path $p "steam.exe"))) { return $p }
    }
    return $null
}

function Get-SteamLibraries {
    param([string]$SteamPath)
    $libs = @($SteamPath)
    $vdfPath = Join-Path $SteamPath "steamapps\libraryfolders.vdf"
    if (-not (Test-Path $vdfPath)) { return $libs }
    $content = [System.IO.File]::ReadAllText($vdfPath, [System.Text.Encoding]::UTF8)
    foreach ($m in [regex]::Matches($content, '"path"\s+"([^"]+)"')) {
        $p = $m.Groups[1].Value -replace '\\\\', '\'
        if ($p -ne $SteamPath -and (Test-Path $p)) { $libs += $p }
    }
    return $libs | Select-Object -Unique
}

function Get-InstalledGames {
    param([string[]]$Libraries)
    $games = @()
    foreach ($lib in $Libraries) {
        $sa = Join-Path $lib "steamapps"
        if (-not (Test-Path $sa)) { continue }
        Get-ChildItem $sa -Filter "appmanifest_*.acf" -EA SilentlyContinue | ForEach-Object {
            $c = [System.IO.File]::ReadAllText($_.FullName, [System.Text.Encoding]::UTF8)
            if (-not $c) { return }
            $appId = if ($c -match '"appid"\s+"(\d+)"') { $matches[1] } else { $null }
            $name = if ($c -match '"name"\s+"([^"]+)"') { $matches[1] } else { $null }
            $dir = if ($c -match '"installdir"\s+"([^"]+)"') { $matches[1] } else { $null }
            if ($appId -and $name -and $dir -and $name -ne "Steamworks Common Redistributables") {
                $gamePath = Join-Path (Join-Path $lib "steamapps\common") $dir
                if (Test-Path $gamePath) { $games += @{ AppId = $appId; Name = $name } }
            }
        }
    }
    return $games
}

function Read-UrlShortcut {
    param([string]$Path)
    $content = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::ASCII)
    $url = ""; $iconFile = ""
    if ($content -match 'URL=(steam://rungameid/(\d+))') { $url = $matches[1] }
    if ($content -match 'IconFile=(.+?)[\r\n]') { $iconFile = $matches[1].Trim() }
    $appId = if ($url -match '(\d+)$') { $matches[1] } else { $null }
    $usesFallback = ($iconFile -match 'steam\.exe$')
    $iconMissing = ($iconFile -and -not (Test-Path $iconFile))
    return @{ AppId = $appId; IconFile = $iconFile; IconMissing = $iconMissing; NeedsRealIcon = ($iconMissing -or $usesFallback -or -not $iconFile) }
}

function Find-SteamShortcuts {
    param([string[]]$Paths)
    $shortcuts = @()
    foreach ($p in $paths) {
        if (-not (Test-Path $p)) { continue }
        Get-ChildItem $p -Filter "*.url" -EA SilentlyContinue | ForEach-Object {
            $info = Read-UrlShortcut $_.FullName
            if ($info.AppId) {
                $shortcuts += @{
                    AppId = $info.AppId; Path = $_.FullName
                    IconFile = $info.IconFile; IconMissing = $info.IconMissing; NeedsRealIcon = $info.NeedsRealIcon; Dir = $p
                }
            }
        }
    }
    return $shortcuts
}

function Get-SteamAppInfo {
    param([string]$AppId)
    $tmpFile = Join-Path $env:TEMP "steam_api_${AppId}.json"
    $null = & curl.exe -s -o $tmpFile --connect-timeout 5 --max-time 15 "https://api.steamcmd.net/v1/info/${AppId}" 2>$null
    if (-not (Test-Path $tmpFile)) { return $null }
    $json = [System.IO.File]::ReadAllText($tmpFile, [System.Text.Encoding]::UTF8)
    Remove-Item $tmpFile -Force -EA SilentlyContinue
    if (-not $json) { return $null }
    $hash = if ($json -match '"clienticon"\s*:\s*"([0-9a-f]{40})"') { $matches[1] } else { $null }
    $name = $null
    $allNames = [regex]::Matches($json, '"name"\s*:\s*"([^"]+)"')
    foreach ($m in $allNames) {
        $endPos = $m.Index + $m.Length
        $afterLen = [Math]::Min(30, $json.Length - $endPos)
        $after = $json.Substring($endPos, $afterLen)
        if ($after -match '"(osarch|name_localized)"') { $name = $m.Groups[1].Value; break }
    }
    return @{ Hash = $hash; Name = $name }
}

function Download-Icon {
    param([string]$AppId,[string]$Hash,[string]$GamesDir,[string]$CdnBase)
    $icoPath = Join-Path $GamesDir "${Hash}.ico"
    if (Test-Path $icoPath) { return $icoPath }
    $url = "${CdnBase}/${AppId}/${Hash}.ico"
    & curl.exe -s -o $icoPath --connect-timeout 5 --max-time 30 $url 2>$null | Out-Null
    if (Test-Path $icoPath) {
        if ((Get-Item $icoPath -EA SilentlyContinue).Length -gt 500) { return $icoPath }
        Remove-Item $icoPath -Force -EA SilentlyContinue
    }
    return $null
}

function Write-UrlShortcut {
    param([string]$Path,[string]$AppId,[string]$IconPath,[string]$SteamExe)
    $iconLine = if ($IconPath) { "IconFile=$IconPath" } else { "IconFile=$SteamExe" }
    $content = "[{000214A0-0000-0000-C000-000000000046}]`r`nProp3=19,2`r`n[InternetShortcut]`r`nIDList=`r`nIconIndex=0`r`nURL=steam://rungameid/${AppId}`r`n${iconLine}`r`n"
    [System.IO.File]::WriteAllText($Path, $content, (New-Object System.Text.UTF8Encoding $false))
}

function Sanitize-Name {
    param([string]$Name)
    $s = [regex]::Replace($Name, '\\u([0-9a-fA-F]{4})', { [char][Convert]::ToInt32($args[0].Groups[1].Value, 16) })
    $s = ($s -replace '[<>:"/\\|?*]', '').Trim()
    $s = ($s -replace '\s{2,}', ' ').Trim()
    return $s
}

Main
