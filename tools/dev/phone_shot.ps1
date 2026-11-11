# Takes a screenshot of the connected phone and saves a small copy for review.
#
# Usage: powershell -File tools\dev\phone_shot.ps1 -Name profile
# Output: build\device_shots\<Name>.png and <Name>_small.jpg

param(
    [Parameter(Mandatory = $true)][string]$Name,
    [int]$Width = 420
)

$adb = Join-Path $env:LOCALAPPDATA "Android\sdk\platform-tools\adb.exe"
$projectRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$folder = Join-Path $projectRoot "build\device_shots"
New-Item -ItemType Directory -Force $folder | Out-Null
$png = Join-Path $folder "$Name.png"

& $adb shell screencap -p /data/local/tmp/bu_shot.png | Out-Null
cmd /c "`"$adb`" pull /data/local/tmp/bu_shot.png `"$png`" >nul 2>&1"
& $adb shell rm /data/local/tmp/bu_shot.png | Out-Null

Add-Type -AssemblyName System.Drawing
$image = [System.Drawing.Image]::FromFile($png)
$height = [int]($image.Height * $Width / $image.Width)
$small = New-Object System.Drawing.Bitmap($Width, $height)
$graphics = [System.Drawing.Graphics]::FromImage($small)
$graphics.InterpolationMode = 'HighQualityBicubic'
$graphics.DrawImage($image, 0, 0, $Width, $height)
$small.Save((Join-Path $folder "${Name}_small.jpg"), [System.Drawing.Imaging.ImageFormat]::Jpeg)
Write-Output "$Name $($image.Width)x$($image.Height)"
$graphics.Dispose(); $small.Dispose(); $image.Dispose()
