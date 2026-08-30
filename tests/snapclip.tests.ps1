#!/usr/bin/env pwsh
# ABOUTME: Tests for the Windows Snapclip capture script.
# ABOUTME: Clipboard cases use the real clipboard and will overwrite whatever is currently on it.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '..' 'src' 'snapclip.ps1')

$script:Passed = 0
$script:Failed = 0

function Test-Case {
    param([string] $Name, [scriptblock] $Body)
    try {
        & $Body
        $script:Passed++
        Write-Host "  PASS  $Name" -ForegroundColor Green
    } catch {
        $script:Failed++
        Write-Host "  FAIL  $Name" -ForegroundColor Red
        Write-Host "        $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Assert-Equal {
    param($Expected, $Actual)
    if ($Expected -ne $Actual) { throw "expected [$Expected], got [$Actual]" }
}

function Assert-True {
    param($Condition, [string] $Because)
    if (-not $Condition) { throw "expected true: $Because" }
}

function New-Sandbox {
    $path = Join-Path ([IO.Path]::GetTempPath()) ("snapclip-test-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $path -Force | Out-Null
    $path
}

Write-Host "`nGet-SnapclipConfig"

Test-Case 'defaults to Pictures\snapclip and 7 day retention when no config exists' {
    $config = Get-SnapclipConfig -ConfigPath (Join-Path (New-Sandbox) 'absent')
    Assert-Equal (Join-Path ([Environment]::GetFolderPath('MyPictures')) 'snapclip') $config.ScreenshotDir
    Assert-Equal 7 $config.RetentionDays
}

Test-Case 'reads SCREENSHOT_DIR and RETENTION_DAYS' {
    $file = Join-Path (New-Sandbox) 'config'
    Set-Content -LiteralPath $file -Value @('SCREENSHOT_DIR=D:\shots', 'RETENTION_DAYS=30')
    $config = Get-SnapclipConfig -ConfigPath $file
    Assert-Equal 'D:\shots' $config.ScreenshotDir
    Assert-Equal 30 $config.RetentionDays
}

Test-Case 'parses RETENTION_DAYS as a number, not a string' {
    $file = Join-Path (New-Sandbox) 'config'
    Set-Content -LiteralPath $file -Value 'RETENTION_DAYS=14'
    Assert-True ((Get-SnapclipConfig -ConfigPath $file).RetentionDays -is [int]) 'RetentionDays should be [int]'
}

Test-Case 'ignores commented-out settings' {
    $file = Join-Path (New-Sandbox) 'config'
    Set-Content -LiteralPath $file -Value @('# RETENTION_DAYS=99', 'RETENTION_DAYS=3')
    Assert-Equal 3 (Get-SnapclipConfig -ConfigPath $file).RetentionDays
}

Test-Case 'strips surrounding quotes from a path' {
    $file = Join-Path (New-Sandbox) 'config'
    Set-Content -LiteralPath $file -Value 'SCREENSHOT_DIR="C:\My Shots"'
    Assert-Equal 'C:\My Shots' (Get-SnapclipConfig -ConfigPath $file).ScreenshotDir
}

Write-Host "`nRemove-ExpiredCaptures"

Test-Case 'deletes captures older than the retention window and keeps recent ones' {
    $dir = New-Sandbox
    $old = Join-Path $dir 'shot-20200101-000000.png'
    $new = Join-Path $dir 'shot-20991231-000000.png'
    Set-Content -LiteralPath $old -Value 'x'; Set-Content -LiteralPath $new -Value 'x'
    (Get-Item $old).LastWriteTime = (Get-Date).AddDays(-30)

    Remove-ExpiredCaptures -Directory $dir -RetentionDays 7
    Assert-True (-not (Test-Path $old)) 'old capture should be pruned'
    Assert-True (Test-Path $new) 'recent capture should survive'
}

Test-Case 'leaves unrelated files alone' {
    $dir = New-Sandbox
    $other = Join-Path $dir 'holiday.png'
    Set-Content -LiteralPath $other -Value 'x'
    (Get-Item $other).LastWriteTime = (Get-Date).AddDays(-400)

    Remove-ExpiredCaptures -Directory $dir -RetentionDays 7
    Assert-True (Test-Path $other) 'only shot-*.png files are managed'
}

Test-Case 'does not throw when the capture folder does not exist yet' {
    Remove-ExpiredCaptures -Directory (Join-Path (New-Sandbox) 'nope') -RetentionDays 7
}

Write-Host "`nGet-CaptureFilePath"

Test-Case 'builds a timestamped name matching the macOS format' {
    $path = Get-CaptureFilePath -Directory 'C:\shots' -Timestamp ([datetime]'2026-08-30T14:05:09')
    Assert-Equal 'C:\shots\shot-20260830-140509.png' $path
}

Write-Host "`nSave-ClipboardImage (uses the real clipboard)"

Test-Case 'writes a decodable PNG from an image on the clipboard' {
    $bitmap = New-Object Drawing.Bitmap 40, 25
    $graphics = [Drawing.Graphics]::FromImage($bitmap)
    $graphics.Clear([Drawing.Color]::Firebrick)
    $graphics.Dispose()
    [Windows.Forms.Clipboard]::SetImage($bitmap)

    $path = Join-Path (New-Sandbox) 'out.png'
    Assert-True (Save-ClipboardImage -Path $path) 'should report a saved image'

    $written = [Drawing.Image]::FromFile($path)
    try {
        Assert-Equal 40 $written.Width
        Assert-Equal 25 $written.Height
    } finally { $written.Dispose() }
}

Test-Case 'reports no image when the clipboard holds text' {
    Set-Clipboard -Value 'just some text'
    Assert-True (-not (Save-ClipboardImage -Path (Join-Path (New-Sandbox) 'none.png'))) 'text is not an image'
}

Write-Host "`n$($script:Passed) passed, $($script:Failed) failed`n"
exit ([int]($script:Failed -gt 0))
