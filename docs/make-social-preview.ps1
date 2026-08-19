# Builds docs/social-preview.png - the 1280x640 GitHub social card, drawn in the
# app's own theme around docs/screenshot.png. Run it after refreshing the shot:
#   powershell -NoProfile -ExecutionPolicy Bypass -STA -File docs\make-social-preview.ps1
Add-Type -AssemblyName System.Drawing, System.Windows.Forms

$W = 1280; $H = 640; $SAFE = 60

$Bg        = [System.Drawing.Color]::FromArgb( 11,  16,  24)
$Surface   = [System.Drawing.Color]::FromArgb( 20,  28,  40)
$Elevated  = [System.Drawing.Color]::FromArgb( 27,  40,  56)
$Field     = [System.Drawing.Color]::FromArgb( 14,  20,  30)
$Border    = [System.Drawing.Color]::FromArgb( 42,  71,  94)
$Text      = [System.Drawing.Color]::FromArgb(206, 219, 230)
$Dim       = [System.Drawing.Color]::FromArgb(143, 163, 184)
$Faint     = [System.Drawing.Color]::FromArgb(106, 126, 147)
$Accent    = [System.Drawing.Color]::FromArgb(102, 192, 244)
$AccentHot = [System.Drawing.Color]::FromArgb(158, 220, 255)
$AccentDp  = [System.Drawing.Color]::FromArgb( 23, 105, 170)
$Accent2   = [System.Drawing.Color]::FromArgb( 55, 198, 214)
$Ok        = [System.Drawing.Color]::FromArgb(124, 195,  68)

function Round([System.Drawing.Rectangle]$r, [int]$rad) {
    $p = New-Object System.Drawing.Drawing2D.GraphicsPath
    $d = $rad * 2
    $p.AddArc($r.X, $r.Y, $d, $d, 180, 90)
    $p.AddArc(($r.Right - $d), $r.Y, $d, $d, 270, 90)
    $p.AddArc(($r.Right - $d), ($r.Bottom - $d), $d, $d, 0, 90)
    $p.AddArc($r.X, ($r.Bottom - $d), $d, $d, 90, 90)
    $p.CloseFigure()
    return $p
}
function Fill($g, $r, $rad, $c) { $p = Round $r $rad; $b = New-Object System.Drawing.SolidBrush($c); $g.FillPath($b, $p); $b.Dispose(); $p.Dispose() }
function Stroke($g, $r, $rad, $c, $w) { $p = Round $r $rad; $pen = New-Object System.Drawing.Pen($c, $w); $g.DrawPath($pen, $p); $pen.Dispose(); $p.Dispose() }
function Text2($g, $s, $font, $x, $y, $w, $h, $c, $flags) {
    $r = New-Object System.Drawing.Rectangle($x, $y, $w, $h)
    [System.Windows.Forms.TextRenderer]::DrawText($g, $s, $font, $r, $c, $flags)
}

$TL = [System.Windows.Forms.TextFormatFlags]::Left -bor [System.Windows.Forms.TextFormatFlags]::VerticalCenter -bor [System.Windows.Forms.TextFormatFlags]::NoPadding
$TC = [System.Windows.Forms.TextFormatFlags]::HorizontalCenter -bor [System.Windows.Forms.TextFormatFlags]::VerticalCenter -bor [System.Windows.Forms.TextFormatFlags]::NoPadding

$fTitle = New-Object System.Drawing.Font('Segoe UI Semibold', 46, [System.Drawing.GraphicsUnit]::Pixel)
$fSub   = New-Object System.Drawing.Font('Segoe UI', 21, [System.Drawing.GraphicsUnit]::Pixel)
$fChip  = New-Object System.Drawing.Font('Segoe UI Semibold', 15, [System.Drawing.GraphicsUnit]::Pixel)
$fMono  = New-Object System.Drawing.Font('Consolas', 16, [System.Drawing.GraphicsUnit]::Pixel)
$fTag   = New-Object System.Drawing.Font('Segoe UI Semibold', 13, [System.Drawing.GraphicsUnit]::Pixel)

$bmp = New-Object System.Drawing.Bitmap($W, $H)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode = 'AntiAlias'
$g.InterpolationMode = 'HighQualityBicubic'
$g.PixelOffsetMode = 'HighQuality'
$g.TextRenderingHint = 'ClearTypeGridFit'

# ---- ground: navy gradient + two light pools ------------------------------
$full = New-Object System.Drawing.Rectangle(0, 0, $W, $H)
$lg = New-Object System.Drawing.Drawing2D.LinearGradientBrush($full,
        [System.Drawing.Color]::FromArgb(19, 33, 50), $Bg, 20.0)
$g.FillRectangle($lg, $full); $lg.Dispose()

function Pool($cx, $cy, $rw, $rh, $col, $alpha) {
    $p = New-Object System.Drawing.Drawing2D.GraphicsPath
    $p.AddEllipse(($cx - $rw), ($cy - $rh), ($rw * 2), ($rh * 2))
    $pg = New-Object System.Drawing.Drawing2D.PathGradientBrush($p)
    $pg.CenterColor = [System.Drawing.Color]::FromArgb($alpha, $col)
    $pg.SurroundColors = @([System.Drawing.Color]::FromArgb(0, $col))
    $g.FillPath($pg, $p)
    $pg.Dispose(); $p.Dispose()
}
Pool 120 60 460 340 $Accent 70
Pool 1160 620 500 360 $Accent2 44
Pool 720 -60 420 260 $AccentDp 50

# ---- grain ----------------------------------------------------------------
$noise = New-Object System.Drawing.Bitmap(192, 192, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$rnd = New-Object System.Random 20240517
for ($y = 0; $y -lt 192; $y++) {
    for ($x = 0; $x -lt 192; $x++) {
        $a = $rnd.Next(0, 7)
        $v = $(if ($rnd.Next(0, 3) -eq 0) { 0 } else { 255 })
        $noise.SetPixel($x, $y, [System.Drawing.Color]::FromArgb($a, $v, $v, $v))
    }
}
$tb = New-Object System.Drawing.TextureBrush($noise)
$tb.WrapMode = 'Tile'
$g.FillRectangle($tb, $full)

# ---- screenshot panel, right side ----------------------------------------
$shot = [System.Drawing.Image]::FromFile((Join-Path $PSScriptRoot 'screenshot.png'))
$sw = 520
$sh = [int]($sw * $shot.Height / $shot.Width)
$sx = 708; $sy = [int](($H - $sh) / 2)
$sr = New-Object System.Drawing.Rectangle($sx, $sy, $sw, $sh)
for ($i = 22; $i -ge 1; $i--) {
    $gr = New-Object System.Drawing.Rectangle(($sr.X - $i), ($sr.Y - $i), ($sr.Width + $i * 2), ($sr.Height + $i * 2))
    Stroke $g $gr (14 + $i) ([System.Drawing.Color]::FromArgb((1 + [int]((23 - $i) / 2)), $Accent)) 2
}
$clip = Round $sr 14
$save = $g.Clip
$g.SetClip($clip, [System.Drawing.Drawing2D.CombineMode]::Intersect)
$g.DrawImage($shot, $sr)
$g.Clip = $save
Stroke $g $sr 14 ([System.Drawing.Color]::FromArgb(150, $Border)) 1.5
$clip.Dispose(); $shot.Dispose()

# ---- left column ----------------------------------------------------------
$x0 = $SAFE + 12
$badge = New-Object System.Drawing.Rectangle($x0, 132, 76, 76)
for ($i = 10; $i -ge 1; $i--) {
    $gr = New-Object System.Drawing.Rectangle(($badge.X - $i), ($badge.Y - $i), ($badge.Width + $i * 2), ($badge.Height + $i * 2))
    Stroke $g $gr (20 + $i) ([System.Drawing.Color]::FromArgb((4 + (11 - $i) * 3), $Accent)) 2
}
$bb = New-Object System.Drawing.Drawing2D.LinearGradientBrush($badge, ([System.Drawing.Color]::FromArgb(18, 62, 100)), $Accent, 45.0)
$bp = Round $badge 20
$g.FillPath($bb, $bp)
$g.FillPath($tb, $bp)
$bb.Dispose()

$steamExe = @(
    (Join-Path ${env:ProgramFiles(x86)} 'Steam\steam.exe'),
    (Join-Path $env:ProgramFiles 'Steam\steam.exe')
) | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1
if (-not $steamExe) { 'WARN: steam.exe not found for the badge icon' }
if ($steamExe) {
    $ico = [System.Drawing.Icon]::ExtractAssociatedIcon($steamExe)
    $ib = $ico.ToBitmap()
    $g.DrawImage($ib, (New-Object System.Drawing.Rectangle(($badge.X + 16), ($badge.Y + 16), 44, 44)))
    $ib.Dispose(); $ico.Dispose()
}
Stroke $g $badge 20 ([System.Drawing.Color]::FromArgb(110, 255, 255, 255)) 1
$bp.Dispose()

# wordmark
$tr = New-Object System.Drawing.Rectangle($x0, 236, 600, 60)
$tbr = New-Object System.Drawing.Drawing2D.LinearGradientBrush($tr, $AccentHot, $Accent2, 12.0)
$g.TextRenderingHint = 'AntiAliasGridFit'
$g.DrawString('Steam Shortcut Fixer', $fTitle, $tbr, [float]($x0 - 3), 234.0)
$tbr.Dispose()
$g.TextRenderingHint = 'ClearTypeGridFit'

Text2 $g 'Real .ico icons for your Steam desktop and' $fSub $x0 300 600 28 $Dim $TL
Text2 $g 'Start Menu shortcuts - no admin, no installer' $fSub $x0 330 600 28 $Dim $TL

# tag chips
$tags = @(@('Windows 10/11', $Dim), @('PowerShell 5.1', $Dim), @('Zero dependencies', $Ok))
$cx = $x0
foreach ($t in $tags) {
    $tw = [System.Windows.Forms.TextRenderer]::MeasureText($t[0], $fTag).Width
    $cr = New-Object System.Drawing.Rectangle($cx, 376, ($tw + 28), 32)
    Fill $g $cr 16 $Surface
    Stroke $g $cr 16 ([System.Drawing.Color]::FromArgb(120, $Border)) 1
    Text2 $g $t[0] $fTag ($cx + 14) 376 $tw 32 $t[1] $TL
    $cx += $tw + 28 + 10
}

# one-liner field
$cmd = 'irm github.com/abd3lraouf/steam-icon-fixer/raw/main/s.ps1|iex'
$cw = [System.Windows.Forms.TextRenderer]::MeasureText($cmd, $fMono).Width
$cr = New-Object System.Drawing.Rectangle($x0, 434, ($cw + 60), 54)
Fill $g $cr 12 $Field
Stroke $g $cr 12 ([System.Drawing.Color]::FromArgb(160, $Accent)) 1.4
Text2 $g '>' $fMono ($x0 + 18) 434 20 54 $Accent $TL
Text2 $g $cmd $fMono ($x0 + 38) 434 ($cw + 4) 54 $Text $TL

Text2 $g 'github.com/abd3lraouf/steam-icon-fixer' $fTag $x0 506 600 22 $Faint $TL

$g.Dispose()
$out = Join-Path $PSScriptRoot 'social-preview.png'
$bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose(); $noise.Dispose(); $tb.Dispose()
"saved $out"
