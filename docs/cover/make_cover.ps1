# Renders docs/cover/cover.html to docs/assets/readme-cover.png (1600 x 760).
# Run from the project root:  powershell -File docs/cover/make_cover.ps1
$root = Resolve-Path "$PSScriptRoot\..\.."
$out = Join-Path $root "docs\assets\readme-cover.png"
New-Item -ItemType Directory -Force (Split-Path $out) | Out-Null
$src = "file:///" + ((Join-Path $root "docs\cover\cover.html") -replace '\\', '/' -replace ' ', '%20')
Start-Process -Wait -FilePath "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe" -ArgumentList `
  "--headless=new", "--disable-gpu", "--hide-scrollbars", "--allow-file-access-from-files", `
  "--force-device-scale-factor=1", "--window-size=1600,760", "--screenshot=`"$out`"", $src
"{0}  {1} KB" -f $out, [math]::Round((Get-Item $out).Length / 1KB)
