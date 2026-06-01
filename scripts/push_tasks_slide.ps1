# Copy tasks PNG to the frame slideshow and register it in Aimor's DB.
param(
    [string]$Adb = "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\Google.PlatformTools_Microsoft.Winget.Source_8wekyb3d8bbwe\platform-tools\adb.exe",
    [string]$Image = (Join-Path (Split-Path $PSScriptRoot -Parent) "tasks\tasks_today.png")
)

if (-not (Test-Path $Image)) {
    throw "Missing tasks_today.png. Run: python tasks/render_tasks.py"
}

& $Adb push $Image /sdcard/aimor/image/tasks_today.png

$ts = [int64]([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())
$upload = Get-Date -Format 'yyyy/MM/dd HH:mm'
$sqlPath = Join-Path $env:TEMP 'register_tasks.sql'
@(
    "DELETE FROM MEDIA_BEAN WHERE DEST_FILE_NAME='tasks_today.png';"
    "INSERT INTO MEDIA_BEAN (DEST_FILE_NAME,MEDIA_TYPE,IS_DISPLAY,TITLE,U_ID,MEDIA_PATH,IS_AUTO_PLAY,DURATION,MUTE,SCALE_TYPE,MAX_SCALE,MIN_SCALE,M_MULTIPLE,FOCUS_X,FOCUS_Y,TAKEN_PIC_TIME,UPLOAD_TIME,UPLOAD_TIME_LONG,PHOTO_WIDTH,PHOTOHEIGHT,LIKED,GROUP_LABEL) VALUES ('tasks_today.png',0,0,'Today',0,'/storage/emulated/0/aimor/image/tasks_today.png',0,0.0,0,1,1.0,1.0,1.0,0.5,0.5,$ts,'$upload',$ts,1280.0,800.0,0,'tasks');"
) | Set-Content -Encoding ASCII $sqlPath

& $Adb push $sqlPath /data/local/tmp/register_tasks.sql
& $Adb shell 'sqlite3 /data/data/com.efercro.os.aimor/databases/db_aimor.db < /data/local/tmp/register_tasks.sql'
& $Adb shell 'am force-stop com.efercro.os.aimor'
Start-Sleep 2
& $Adb shell 'monkey -p com.efercro.os.aimor -c android.intent.category.LAUNCHER 1'
Write-Host 'Tasks slide pushed to frame.'
