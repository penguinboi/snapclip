#!/usr/bin/env pwsh
# ABOUTME: Interactive screenshot, saved to a folder, with the file path copied to the clipboard.
# ABOUTME: Drives the built-in Windows snip overlay and turns the image it hands back into a saved PNG path.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Windows.Forms, System.Drawing

# The snip overlay runs asynchronously and reports neither an exit code nor a
# cancellation, so the clipboard sequence number is the only trustworthy signal
# that the user actually captured something.
if (-not ('Snapclip.Native' -as [type])) {
    Add-Type -Namespace Snapclip -Name Native -MemberDefinition @'
[DllImport("user32.dll")] public static extern uint GetClipboardSequenceNumber();
'@
}

function Get-SnapclipConfig {
    <#
    .SYNOPSIS
    Reads the same KEY=VALUE config file the macOS version uses.
    #>
    param(
        [string] $ConfigPath = (Join-Path $HOME '.config/snapclip/config')
    )

    $config = @{
        ScreenshotDir = Join-Path ([Environment]::GetFolderPath('MyPictures')) 'snapclip'
        RetentionDays = 7
    }

    if (Test-Path -LiteralPath $ConfigPath) {
        foreach ($line in Get-Content -LiteralPath $ConfigPath) {
            if ($line -notmatch '^\s*([A-Z_]+)\s*=\s*(.*?)\s*$') { continue }
            $key   = $Matches[1]
            $value = $Matches[2].Trim("'", '"')
            switch ($key) {
                'SCREENSHOT_DIR' { $config.ScreenshotDir = $value }
                'RETENTION_DAYS' { $config.RetentionDays = [int] $value }
            }
        }
    }

    $config
}

function Remove-ExpiredCaptures {
    <#
    .SYNOPSIS
    Prunes old captures so the folder does not grow forever.
    #>
    param(
        [Parameter(Mandatory)] [string] $Directory,
        [Parameter(Mandatory)] [int]    $RetentionDays
    )

    if (-not (Test-Path -LiteralPath $Directory)) { return }

    $cutoff = (Get-Date).AddDays(-$RetentionDays)
    Get-ChildItem -LiteralPath $Directory -Filter 'shot-*.png' -File |
        Where-Object { $_.LastWriteTime -lt $cutoff } |
        Remove-Item -Force
}

function Get-CaptureFilePath {
    param(
        [Parameter(Mandatory)] [string]   $Directory,
        [datetime]                        $Timestamp = (Get-Date)
    )

    Join-Path $Directory ('shot-{0}.png' -f $Timestamp.ToString('yyyyMMdd-HHmmss'))
}

function Save-ClipboardImage {
    <#
    .SYNOPSIS
    Writes the clipboard image to disk, returning $true when one was present.
    #>
    param(
        [Parameter(Mandatory)] [string] $Path
    )

    $data = [Windows.Forms.Clipboard]::GetDataObject()

    # The snip tool offers a real PNG stream alongside the bitmap. Preferring it
    # keeps transparency intact, which the DIB conversion behind GetImage() drops.
    if ($data -and $data.GetDataPresent('PNG')) {
        $stream = $data.GetData('PNG')
        $stream.Position = 0
        $file = [IO.File]::Create($Path)
        try { $stream.CopyTo($file) } finally { $file.Dispose() }
        return $true
    }

    $image = [Windows.Forms.Clipboard]::GetImage()
    if ($null -eq $image) { return $false }
    try { $image.Save($Path, [Drawing.Imaging.ImageFormat]::Png) } finally { $image.Dispose() }
    $true
}

function Show-SnapclipNotification {
    param(
        [Parameter(Mandatory)] [string] $Message
    )

    $icon = New-Object Windows.Forms.NotifyIcon
    try {
        $icon.Icon = [Drawing.SystemIcons]::Information
        $icon.Visible = $true
        $icon.ShowBalloonTip(2000, 'Snapclip', $Message, [Windows.Forms.ToolTipIcon]::Info)
        Start-Sleep -Milliseconds 2000
    } catch {
        # The path is already on the clipboard, so a failed toast must not fail the capture.
        Write-Warning "Snapclip notification failed: $($_.Exception.Message)"
    } finally {
        $icon.Dispose()
    }
}

function Get-SnapclipIntroMarker {
    Join-Path $HOME '.config/snapclip/.introduced'
}

function Show-SnapclipUsage {
    $config = Get-SnapclipConfig
    @"
Snapclip - capture a screenshot and copy its file path to the clipboard.

The clipboard receives the PATH to the PNG, not the image itself, so it can be
pasted straight into anything that reads files: an AI coding assistant, a chat,
a bug report.

Usage:
  snapclip            open the snip overlay and capture
  snapclip -Help      show this

Hotkey:   Ctrl+Shift+1
Captures: $($config.ScreenshotDir)
Config:   $(Join-Path $HOME '.config/snapclip/config')
            SCREENSHOT_DIR=C:\some\path
            RETENTION_DAYS=$($config.RetentionDays)

Rebind the hotkey by re-running install.ps1 -Hotkey "CTRL+ALT+1"
"@
}

function Show-SnapclipIntroOnce {
    <#
    .SYNOPSIS
    Explains the tool the first time it captures, then never again. Returns
    $true when it showed the intro.
    #>
    param(
        [Parameter(Mandatory)] $Config,
        [string] $MarkerPath = (Get-SnapclipIntroMarker),
        [switch] $Quiet
    )

    $marker = $MarkerPath
    if (Test-Path -LiteralPath $marker) { return $false }

    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $marker) | Out-Null
    New-Item -ItemType File -Force -Path $marker | Out-Null

    # "The path, not the image" is the surprising part, and a hotkey tool has no
    # other moment to explain itself.
    if (-not $Quiet) {
        Show-SnapclipNotification -Message ("The FILE PATH is on your clipboard, not the image. " +
            "Captures go to $($Config.ScreenshotDir) and are deleted after $($Config.RetentionDays) days.")
    }
    $true
}

function Invoke-Snapclip {
    <#
    .SYNOPSIS
    Opens the snip overlay, saves what the user captured, and puts its path on the clipboard.
    #>
    param(
        [int] $TimeoutSeconds = 120
    )

    $config = Get-SnapclipConfig
    New-Item -ItemType Directory -Force -Path $config.ScreenshotDir | Out-Null
    Remove-ExpiredCaptures -Directory $config.ScreenshotDir -RetentionDays $config.RetentionDays

    $sequenceBefore = [Snapclip.Native]::GetClipboardSequenceNumber()
    Start-Process 'ms-screenclip:'

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 150

        if ([Snapclip.Native]::GetClipboardSequenceNumber() -eq $sequenceBefore) { continue }
        # Something reached the clipboard, but the user may have copied text on the
        # way to snipping. Keep waiting for an image rather than giving up.
        if (-not [Windows.Forms.Clipboard]::ContainsImage()) { continue }

        $path = Get-CaptureFilePath -Directory $config.ScreenshotDir
        if (Save-ClipboardImage -Path $path) {
            Set-Clipboard -Value $path
            if (-not (Show-SnapclipIntroOnce -Config $config)) {
                Show-SnapclipNotification -Message 'Path copied to clipboard'
            }
            return $path
        }
    }

    # Escaped, or wandered off. Leave the clipboard exactly as we found it.
    $null
}

# Dot-sourcing loads the functions for the tests; running the file captures.
if ($MyInvocation.InvocationName -ne '.') {
    if ($args | Where-Object { $_ -in '-Help', '--help', '-h', '/?' }) {
        Show-SnapclipUsage
    } else {
        $captured = Invoke-Snapclip
        if ($captured) { Write-Output $captured }
    }
}
