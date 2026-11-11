# Runs the on-device map test and collects screenshots at its marked steps.
#
# Usage (from the project root, phone connected):
#
#   powershell -File tools\dev\run_device_map_test.ps1 -Label online
#   powershell -File tools\dev\run_device_map_test.ps1 -Label offline -ExpectOffline
#
# For the offline run, connect the phone by USB and enable airplane mode
# first. Screenshots are saved to build\device_shots\<Label>\.

param(
    [string]$Label = "online",
    [switch]$ExpectOffline,
    [string]$JdkDir = "C:\Program Files\Android\Android Studio\jbr",
    [string[]]$Shots = @("zoom-10", "zoom-14", "zoom-18", "edge-n", "edge-se", "edge-w", "bangla-labels")
)

$ErrorActionPreference = "Continue"
$adb = Join-Path $env:LOCALAPPDATA "Android\sdk\platform-tools\adb.exe"
$projectRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..")
Set-Location $projectRoot

$device = (& $adb devices | Select-String "\tdevice$" | Select-Object -First 1).Line -replace "\tdevice$", ""
if (-not $device) { Write-Output "No phone connected."; exit 1 }

$airplane = (& $adb -s $device shell settings get global airplane_mode_on).Trim()
Write-Output "DEVICE $device airplane_mode_on=$airplane"

# MapLibre's Android plugin needs JDK 21 or newer to build.
if (Test-Path $JdkDir) { $env:GRADLE_OPTS = "-Dorg.gradle.java.home=`"$JdkDir`"" }

$defines = @("--dart-define=DEMO_DATA=true")
if ($ExpectOffline) { $defines += "--dart-define=EXPECT_OFFLINE=true" }

$local = Join-Path $projectRoot "build\device_shots\$Label"
New-Item -ItemType Directory -Force $local | Out-Null
$log = Join-Path $local "drive.log"
Set-Content -Path $log -Value "" -Encoding utf8

# Middle of the upper half of the screen, over the map.
$tapX = 540
$tapY = 800
$size = (& $adb -s $device shell wm size) -join " "
if ($size -match "(\d+)x(\d+)") {
    $tapX = [int]([int]$Matches[1] / 2)
    $tapY = [int]([int]$Matches[2] / 3)
}

$remote = "/data/local/tmp/bu_map_shots"
& $adb -s $device shell "rm -rf $remote; mkdir -p $remote" | Out-Null

# A profile build is used because it is about a fifth of the size of a debug
# build, which matters on a phone that is short of storage.
flutter drive --driver=test_driver/integration_test.dart --target=integration_test/offline_map_test.dart --profile -d $device @defines 2>&1 | ForEach-Object {
    $line = "$_"
    Add-Content -Path $log -Value $line -Encoding utf8
    if ($line -match "MAPSHOT (\S+)") {
        $step = $Matches[1]
        if ($Shots -contains $step) {
            & $adb -s $device shell screencap -p "$remote/$step.png" | Out-Null
        }
        # Keep the screen from timing out. The test ignores touches, so a tap
        # in the middle of the map does nothing except count as activity.
        & $adb -s $device shell input tap $tapX $tapY | Out-Null
    }
    if ($line -match "MAPCHECK|All tests passed|Some tests failed|\[E\]|Expected:|Actual:|Nothing drawn|No roads|No labels|No buildings|still has internet|never created|FAILURE|What went wrong|INSTALL_FAILED|No devices") {
        Write-Output $line
    }
}

cmd /c "`"$adb`" -s $device pull $remote/. `"$local`" >nul 2>&1"
& $adb -s $device shell "rm -rf $remote" | Out-Null
Write-Output "SHOTS $((Get-ChildItem $local -Filter *.png).Count) saved to $local"
