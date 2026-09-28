# Renders the legacy launcher PNGs (Android 7.x; Android 8+ uses the adaptive icon) from the
# Cinematheque mark — the same geometry as res/drawable/ic_launcher_foreground.xml.
#   powershell -ExecutionPolicy Bypass -File tool/render_legacy_icons.ps1
Add-Type -AssemblyName System.Drawing
$res = Join-Path $PSScriptRoot '..\android\app\src\main\res'
$sizes = @{ 'mdpi' = 48; 'hdpi' = 72; 'xhdpi' = 96; 'xxhdpi' = 144; 'xxxhdpi' = 192 }
$ink = [System.Drawing.ColorTranslator]::FromHtml('#141219')
$gold = [System.Drawing.ColorTranslator]::FromHtml('#EBBC00')
$paper = [System.Drawing.ColorTranslator]::FromHtml('#FAF9F7')

function RoundRect([float]$x, [float]$y, [float]$w, [float]$h, [float]$r) {
  $p = New-Object System.Drawing.Drawing2D.GraphicsPath
  $d = 2 * $r
  $p.AddArc($x, $y, $d, $d, 180, 90); $p.AddArc($x + $w - $d, $y, $d, $d, 270, 90)
  $p.AddArc($x + $w - $d, $y + $h - $d, $d, $d, 0, 90); $p.AddArc($x, $y + $h - $d, $d, $d, 90, 90)
  $p.CloseFigure(); return $p
}

foreach ($density in $sizes.Keys) {
  $n = $sizes[$density]
  $bmp = New-Object System.Drawing.Bitmap $n, $n
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.SmoothingMode = 'AntiAlias'; $g.PixelOffsetMode = 'HighQuality'; $g.Clear([System.Drawing.Color]::Transparent)

  # Ink rounded square with a small margin, as launchers expect of legacy icons.
  $m = $n / 24
  $g.FillPath((New-Object System.Drawing.SolidBrush $ink), (RoundRect $m $m ($n - 2 * $m) ($n - 2 * $m) ($n * 0.2)))

  # The mark: 40-unit box, frame 58% of the icon width.
  $s = ($n * 0.58) / 36; $o = $n / 2 - 20 * $s
  $g.TranslateTransform($o, $o); $g.ScaleTransform($s, $s)
  $pen = New-Object System.Drawing.Pen $gold, 2.8
  $g.DrawPath($pen, (RoundRect 2 4 36 32 6))
  $goldBrush = New-Object System.Drawing.SolidBrush $gold
  foreach ($x in 6, 31) { foreach ($y in 8, 18.5, 29) { $g.FillPath($goldBrush, (RoundRect $x $y 3 3 1)) } }
  $ridge = [System.Drawing.PointF[]]@(
    (New-Object System.Drawing.PointF 11, 28), (New-Object System.Drawing.PointF 16.5, 19),
    (New-Object System.Drawing.PointF 19.5, 23), (New-Object System.Drawing.PointF 23, 15),
    (New-Object System.Drawing.PointF 29, 28))
  $g.FillPolygon((New-Object System.Drawing.SolidBrush $paper), $ridge)
  $edge = New-Object System.Drawing.Pen $gold, 1.2; $edge.LineJoin = 'Round'
  $g.DrawPolygon($edge, $ridge)

  $out = Join-Path $res "mipmap-$density\ic_launcher.png"
  $bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
  $g.Dispose(); $bmp.Dispose()
  "$density ${n}px -> $out"
}
