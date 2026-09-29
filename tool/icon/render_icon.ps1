# Renders the launcher icon PNGs from tool/icon/ccd_mark.svg.html with headless Chrome.
#   powershell -ExecutionPolicy Bypass -File tool/icon/render_icon.ps1
# Output:
#   android/app/src/main/res/mipmap-*/ic_launcher_{background,foreground,monochrome}.png  (adaptive, Android 8+)
#   android/app/src/main/res/mipmap-*/ic_launcher.png                                    (legacy, Android 7)
#   tool/icon/store_icon_512.png                                                         (store listing)
#   android/app/src/main/res/drawable-*/splash_mark.png                                  (native splash)
$ErrorActionPreference = 'Stop'
$chrome = "${env:ProgramFiles}\Google\Chrome\Application\chrome.exe"
if (-not (Test-Path $chrome)) { $chrome = "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe" }
$src = (Resolve-Path (Join-Path $PSScriptRoot 'ccd_mark.svg.html')).Path
$url = 'file:///' + $src.Replace([char]92, [char]47)
$res = Resolve-Path (Join-Path $PSScriptRoot '..\..\android\app\src\main\res')

function Render($layer, [int]$size, $out) {
  if (Test-Path $out) { Remove-Item $out }
  # Chrome reports progress on stderr, which PowerShell 5.1 would treat as an error.
  $log = [IO.Path]::GetTempFileName()
  Start-Process -FilePath $chrome -Wait -NoNewWindow -RedirectStandardError $log -ArgumentList @(
    '--headless=new', '--disable-gpu', '--allow-file-access-from-files', '--hide-scrollbars',
    '--force-device-scale-factor=1', '--default-background-color=00000000', '--virtual-time-budget=3000',
    "--window-size=$size,$size", "`"--screenshot=$out`"", "`"$url#layer=$layer&size=$size`"")
  Remove-Item $log
  if (-not (Test-Path $out)) { throw "Render failed: $out" }
  "  $layer ${size}px -> $out"
}

# Adaptive layers are 108dp; legacy icons are 48dp.
$densities = [ordered]@{ mdpi = 1; hdpi = 1.5; xhdpi = 2; xxhdpi = 3; xxxhdpi = 4 }
foreach ($d in $densities.Keys) {
  $dir = Join-Path $res "mipmap-$d"
  $adaptive = [int](108 * $densities[$d]); $legacy = [int](48 * $densities[$d])
  foreach ($layer in 'background', 'foreground', 'monochrome') { Render $layer $adaptive (Join-Path $dir "ic_launcher_$layer.png") }
  Render 'legacy' $legacy (Join-Path $dir 'ic_launcher.png')
}
Render 'legacy' 512 (Join-Path $PSScriptRoot 'store_icon_512.png')

# Splash: the mark small on the 288dp Android 12+ splash-icon canvas; the Flutter intro
# picks it up at exactly this size and enlarges it (it draws the mark itself, as vectors).
foreach ($d in $densities.Keys) {
  $dir = Join-Path $res "drawable-$d"
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory $dir | Out-Null }
  Render 'splash' ([int](288 * $densities[$d])) (Join-Path $dir 'splash_mark.png')
}
