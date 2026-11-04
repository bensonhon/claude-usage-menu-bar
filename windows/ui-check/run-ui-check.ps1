param(
    [Parameter(Mandatory = $true)] [string] $ExecutablePath,
    [Parameter(Mandatory = $true)] [string] $ScreenshotFolderPath
)

$ErrorActionPreference = 'Stop'
$ExecutablePath = (Resolve-Path $ExecutablePath).Path
New-Item -ItemType Directory -Force -Path $ScreenshotFolderPath | Out-Null
$ScreenshotFolderPath = (Resolve-Path $ScreenshotFolderPath).Path
$uiCheckFolderPath = $PSScriptRoot
$workFolderPath = Join-Path $env:RUNNER_TEMP 'ui-check'
New-Item -ItemType Directory -Force -Path $workFolderPath | Out-Null

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class NativeInput
{
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] public static extern void mouse_event(uint flags, uint dx, uint dy, uint data, UIntPtr extraInfo);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr SendMessageTimeout(IntPtr window, uint message, UIntPtr wParam, string lParam, uint flags, uint timeout, out UIntPtr result);
    public static void LeftClick(int x, int y)
    {
        SetCursorPos(x, y);
        System.Threading.Thread.Sleep(150);
        mouse_event(0x0002, 0, 0, 0, UIntPtr.Zero);
        System.Threading.Thread.Sleep(60);
        mouse_event(0x0004, 0, 0, 0, UIntPtr.Zero);
    }
    public static void BroadcastThemeChange()
    {
        UIntPtr result;
        SendMessageTimeout(new IntPtr(0xffff), 0x001A, UIntPtr.Zero, "ImmersiveColorSet", 0x0002, 3000, out result);
    }
}
'@

$TreeScope = [System.Windows.Automation.TreeScope]
$AutomationElement = [System.Windows.Automation.AutomationElement]
$ControlType = [System.Windows.Automation.ControlType]

function Save-Screenshot([string] $name) {
    $screen = [System.Windows.Forms.SystemInformation]::VirtualScreen
    $bitmap = New-Object System.Drawing.Bitmap $screen.Width, $screen.Height
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.CopyFromScreen($screen.Left, $screen.Top, 0, 0, $bitmap.Size)
    $bitmap.Save((Join-Path $ScreenshotFolderPath "$name.png"), [System.Drawing.Imaging.ImageFormat]::Png)
    $graphics.Dispose()
    $bitmap.Dispose()
    Write-Host "Saved screenshot $name"
}

function Save-ZoomedScreenRegion([string] $name, [System.Windows.Rect] $region, [int] $zoom) {
    $left = [int][Math]::Max(0, $region.Left)
    $top = [int][Math]::Max(0, $region.Top)
    $width = [int]$region.Width
    $height = [int]$region.Height
    $capture = New-Object System.Drawing.Bitmap $width, $height
    $captureGraphics = [System.Drawing.Graphics]::FromImage($capture)
    $captureGraphics.CopyFromScreen($left, $top, 0, 0, $capture.Size)
    $zoomed = New-Object System.Drawing.Bitmap ($width * $zoom), ($height * $zoom)
    $zoomedGraphics = [System.Drawing.Graphics]::FromImage($zoomed)
    $zoomedGraphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
    $zoomedGraphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::Half
    $zoomedGraphics.DrawImage($capture, 0, 0, $width * $zoom, $height * $zoom)
    $zoomed.Save((Join-Path $ScreenshotFolderPath "$name.png"), [System.Drawing.Imaging.ImageFormat]::Png)
    $captureGraphics.Dispose(); $capture.Dispose(); $zoomedGraphics.Dispose(); $zoomed.Dispose()
    Write-Host "Saved zoomed screenshot $name"
}

function Write-TextFile([string] $path, [string] $text) {
    New-Item -ItemType Directory -Force -Path (Split-Path $path) | Out-Null
    [System.IO.File]::WriteAllText($path, $text, (New-Object System.Text.UTF8Encoding $false))
}

function Write-Credentials([string] $configFolderPath, [string] $accessToken, [string] $subscriptionType) {
    $expiresAt = [DateTimeOffset]::UtcNow.AddDays(1).ToUnixTimeMilliseconds()
    $credentials = @{ claudeAiOauth = @{ accessToken = $accessToken; expiresAt = $expiresAt; subscriptionType = $subscriptionType } }
    Write-TextFile (Join-Path $configFolderPath '.credentials.json') ($credentials | ConvertTo-Json -Depth 4)
}

function Write-TokenHistory([string] $configFolderPath, [string[]] $projectNames, [string[]] $models) {
    $lines = New-Object System.Collections.Generic.List[string]
    $now = [DateTimeOffset]::UtcNow
    for ($index = 0; $index -lt $projectNames.Count; $index++) {
        $sessionId = "ui-check-session-$index"
        for ($turn = 0; $turn -lt 6; $turn++) {
            $line = @{
                type = 'assistant'
                timestamp = $now.AddMinutes(-(($index * 140) + ($turn * 9))).ToString('o')
                sessionId = $sessionId
                cwd = "C:\Users\runneradmin\code\$($projectNames[$index])"
                message = @{
                    id = "ui-check-message-$index-$turn"
                    model = $models[$index % $models.Count]
                    usage = @{ input_tokens = 1200 + ($turn * 310); output_tokens = 2400 + ($index * 97); cache_creation_input_tokens = 18000; cache_read_input_tokens = 240000 + ($turn * 15000) }
                }
            }
            $lines.Add(($line | ConvertTo-Json -Depth 5 -Compress))
        }
        Write-TextFile (Join-Path $configFolderPath "projects\$($projectNames[$index])\$sessionId.jsonl") (($lines -join "`n") + "`n")
        $lines.Clear()
    }
}

function Start-FakeUsageApi {
    $openSslPath = 'C:\Program Files\Git\usr\bin\openssl.exe'
    if (-not (Test-Path $openSslPath)) { $openSslPath = 'openssl' }
    $certificatePath = Join-Path $workFolderPath 'platform.claude.com.pem'
    $keyPath = Join-Path $workFolderPath 'platform.claude.com.key'
    $derCertificatePath = Join-Path $workFolderPath 'platform.claude.com.cer'
    & $openSslPath req -x509 -newkey rsa:2048 -nodes -keyout $keyPath -out $certificatePath -days 2 -subj '/CN=platform.claude.com' -addext 'subjectAltName=DNS:platform.claude.com'
    if ($LASTEXITCODE -ne 0) { throw 'openssl could not make the test certificate' }
    & $openSslPath x509 -in $certificatePath -outform der -out $derCertificatePath
    Import-Certificate -FilePath $derCertificatePath -CertStoreLocation Cert:\LocalMachine\Root | Out-Null
    Add-Content -Path "$env:windir\System32\drivers\etc\hosts" -Value "`r`n127.0.0.1 platform.claude.com"
    ipconfig /flushdns | Out-Null
    $server = Start-Process python -ArgumentList @((Join-Path $uiCheckFolderPath 'fake_usage_api.py'), $certificatePath, $keyPath) -PassThru -WindowStyle Hidden
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    for ($attempt = 0; $attempt -lt 30; $attempt++) {
        try {
            $response = Invoke-WebRequest -UseBasicParsing -Uri 'https://platform.claude.com/api/oauth/usage' -Headers @{ Authorization = 'Bearer ui-check-main-token' }
            Write-Host "Fake usage API answers: $($response.Content)"
            return $server
        }
        catch {
            Start-Sleep -Milliseconds 500
        }
    }
    throw 'The fake usage API did not answer over HTTPS'
}

function Get-TrayButtons {
    $buttonCondition = New-Object System.Windows.Automation.PropertyCondition($AutomationElement::ControlTypeProperty, $ControlType::Button)
    $taskbar = $AutomationElement::RootElement.FindFirst($TreeScope::Children, (New-Object System.Windows.Automation.PropertyCondition($AutomationElement::ClassNameProperty, 'Shell_TrayWnd')))
    if ($null -eq $taskbar) { throw 'The taskbar was not found' }
    return @($taskbar.FindAll($TreeScope::Descendants, $buttonCondition))
}

function Write-TrayButtonNames {
    foreach ($button in Get-TrayButtons) {
        $name = $button.Current.Name -replace "`r?`n", ' | '
        Write-Host "Taskbar button: '$name' at $($button.Current.BoundingRectangle)"
    }
}

function Find-TrayButton([string] $accountLabel) {
    $namePattern = '^' + [regex]::Escape($accountLabel) + '(\s|$)'
    for ($attempt = 0; $attempt -lt 20; $attempt++) {
        $match = Get-TrayButtons | Where-Object { $_.Current.Name -match $namePattern -and -not $_.Current.BoundingRectangle.IsEmpty } | Select-Object -First 1
        if ($null -ne $match) { return $match }
        Start-Sleep -Milliseconds 500
    }
    Write-TrayButtonNames
    throw "No tray icon whose tooltip starts with the account label '$accountLabel'"
}

function Show-AllTrayIcons {
    $explorerKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer'
    Set-ItemProperty -Path $explorerKey -Name EnableAutoTray -Value 0 -Type DWord
    $notifyIconSettingsKey = 'HKCU:\Control Panel\NotifyIconSettings'
    if (Test-Path $notifyIconSettingsKey) {
        foreach ($iconKey in Get-ChildItem $notifyIconSettingsKey) {
            $executablePath = (Get-ItemProperty $iconKey.PSPath).ExecutablePath
            if ($executablePath -and $executablePath -like '*ClaudeUsageTray.exe') {
                Set-ItemProperty -Path $iconKey.PSPath -Name IsPromoted -Value 1 -Type DWord
            }
        }
    }
    Start-Sleep -Seconds 2
}

function Click-Element($element) {
    $bounds = $element.Current.BoundingRectangle
    [NativeInput]::LeftClick([int]($bounds.Left + $bounds.Width / 2), [int]($bounds.Top + $bounds.Height / 2))
}

function Get-FlyoutWindow($process) {
    $condition = New-Object System.Windows.Automation.AndCondition(
        (New-Object System.Windows.Automation.PropertyCondition($AutomationElement::ProcessIdProperty, $process.Id)),
        (New-Object System.Windows.Automation.PropertyCondition($AutomationElement::NameProperty, 'Claude Usage')),
        (New-Object System.Windows.Automation.PropertyCondition($AutomationElement::ControlTypeProperty, $ControlType::Window)))
    return $AutomationElement::RootElement.FindFirst($TreeScope::Children, $condition)
}

function Wait-FlyoutOpen($process) {
    for ($attempt = 0; $attempt -lt 20; $attempt++) {
        $flyout = Get-FlyoutWindow $process
        if ($null -ne $flyout -and -not $flyout.Current.IsOffscreen -and -not $flyout.Current.BoundingRectangle.IsEmpty) {
            Start-Sleep -Milliseconds 600
            return $flyout
        }
        Start-Sleep -Milliseconds 250
    }
    throw 'The flyout did not open'
}

function Invoke-FlyoutButton($process, [string] $name) {
    $flyout = Wait-FlyoutOpen $process
    $condition = New-Object System.Windows.Automation.AndCondition(
        (New-Object System.Windows.Automation.PropertyCondition($AutomationElement::NameProperty, $name)),
        (New-Object System.Windows.Automation.PropertyCondition($AutomationElement::ControlTypeProperty, $ControlType::Button)))
    $button = $flyout.FindFirst($TreeScope::Descendants, $condition)
    if ($null -eq $button) { throw "No flyout button named '$name'" }
    $button.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
    Start-Sleep -Milliseconds 900
}

function Scroll-FlyoutToBottom($process) {
    $flyout = Wait-FlyoutOpen $process
    $scrollCondition = New-Object System.Windows.Automation.PropertyCondition($AutomationElement::IsScrollPatternAvailableProperty, $true)
    $scrollable = $flyout.FindFirst($TreeScope::Descendants, $scrollCondition)
    if ($null -eq $scrollable) { return }
    $scrollPattern = $scrollable.GetCurrentPattern([System.Windows.Automation.ScrollPattern]::Pattern)
    if ($scrollPattern.Current.VerticallyScrollable) {
        $scrollPattern.SetScrollPercent([System.Windows.Automation.ScrollPattern]::NoScroll, 100)
    }
    Start-Sleep -Milliseconds 500
}

function Save-FlyoutScreenshot($process, [string] $name) {
    Assert-AppRunning $process
    $flyout = Wait-FlyoutOpen $process
    $bounds = $flyout.Current.BoundingRectangle
    $region = New-Object System.Windows.Rect ($bounds.Left - 8), ($bounds.Top - 8), ($bounds.Width + 16), ($bounds.Height + 16)
    Save-ZoomedScreenRegion $name $region 2
}

function Save-TrayScreenshot([string] $name) {
    $screen = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $workArea = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $taskbarHeight = $screen.Height - $workArea.Height
    if ($taskbarHeight -le 0) { $taskbarHeight = 48 }
    $region = New-Object System.Windows.Rect ($screen.Width - 520), ($screen.Height - $taskbarHeight), 520, $taskbarHeight
    Save-ZoomedScreenRegion $name $region 3
}

function Assert-AppRunning($process) {
    $process.Refresh()
    if ($process.HasExited) {
        Save-Screenshot 'app-exited'
        throw "ClaudeUsageTray exited with code $($process.ExitCode)"
    }
    $dialogCondition = New-Object System.Windows.Automation.AndCondition(
        (New-Object System.Windows.Automation.PropertyCondition($AutomationElement::ProcessIdProperty, $process.Id)),
        (New-Object System.Windows.Automation.PropertyCondition($AutomationElement::ClassNameProperty, '#32770')))
    $errorDialog = $AutomationElement::RootElement.FindFirst($TreeScope::Children, $dialogCondition)
    if ($null -ne $errorDialog) {
        Save-Screenshot 'error-dialog'
        $dialogText = ($errorDialog.FindAll($TreeScope::Descendants, [System.Windows.Automation.Condition]::TrueCondition) | ForEach-Object { $_.Current.Name }) -join "`n"
        throw "ClaudeUsageTray showed an error dialog:`n$dialogText"
    }
}

function Start-TrayApp {
    $process = Start-Process -FilePath $ExecutablePath -PassThru
    Start-Sleep -Seconds 6
    Assert-AppRunning $process
    Show-AllTrayIcons
    return $process
}

function Stop-TrayApp($process) {
    if (-not $process.HasExited) {
        Stop-Process -Id $process.Id -Force
        $process.WaitForExit(5000) | Out-Null
    }
    Start-Sleep -Seconds 2
}

try {
    Set-DisplayResolution -Width 1920 -Height 1080 -Force
}
catch {
    Write-Host "Display resolution stays as it is: $($_.Exception.Message)"
}

$homeFolderPath = $env:USERPROFILE
$mainConfigFolderPath = Join-Path $homeFolderPath '.claude'
$workConfigFolderPath = Join-Path $homeFolderPath '.claude-work'
$appDataFolderPath = Join-Path $env:APPDATA 'ClaudeUsageTray'
Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $mainConfigFolderPath, $workConfigFolderPath, $appDataFolderPath

Write-Credentials $mainConfigFolderPath 'ui-check-main-token' 'max'
Write-Credentials $workConfigFolderPath 'ui-check-work-token' 'pro'
Write-TokenHistory $mainConfigFolderPath @('billing-api', 'web-dashboard', 'infra-scripts', 'mobile-app') @('claude-opus-5-5', 'claude-sonnet-5-5', 'claude-haiku-5-5')
Write-TokenHistory $workConfigFolderPath @('data-pipeline', 'docs-site') @('claude-sonnet-5-5')
$fakeUsageApi = Start-FakeUsageApi

$process = Start-TrayApp
Write-TrayButtonNames
Save-Screenshot '01-desktop-after-launch'
Save-TrayScreenshot '02-tray-dark-taskbar'

$mainRingButton = Find-TrayButton 'claude'
Click-Element $mainRingButton
Save-FlyoutScreenshot $process '03-flyout-dark-main-account'
Save-Screenshot '04-desktop-with-flyout'

Scroll-FlyoutToBottom $process
Save-FlyoutScreenshot $process '05-flyout-dark-scrolled-to-bottom'

Invoke-FlyoutButton $process 'Light mode'
Save-FlyoutScreenshot $process '06-flyout-light'

Invoke-FlyoutButton $process 'Simple Mode'
Save-FlyoutScreenshot $process '07-flyout-light-simple-mode'
Invoke-FlyoutButton $process 'Simple Mode'
Invoke-FlyoutButton $process 'Dark mode'

Invoke-FlyoutButton $process 'Accounts'
Scroll-FlyoutToBottom $process
Save-FlyoutScreenshot $process '08-flyout-accounts-list'
Invoke-FlyoutButton $process 'Edit labels & order'
Scroll-FlyoutToBottom $process
Save-FlyoutScreenshot $process '09-flyout-editing-accounts'
Invoke-FlyoutButton $process 'Done'

$workRingButton = Find-TrayButton 'claude-work'
Click-Element $workRingButton
Save-FlyoutScreenshot $process '10-flyout-work-account-from-its-ring'

[System.Windows.Forms.SendKeys]::SendWait('{ESC}')
Start-Sleep -Seconds 1
Assert-AppRunning $process
Save-Screenshot '11-desktop-after-escape'

$ringBounds = (Find-TrayButton 'claude').Current.BoundingRectangle
[NativeInput]::SetCursorPos([int]($ringBounds.Left + $ringBounds.Width / 2), [int]($ringBounds.Top + $ringBounds.Height / 2)) | Out-Null
Start-Sleep -Seconds 3
Save-Screenshot '12-ring-hover-tooltip'
[NativeInput]::SetCursorPos(200, 200) | Out-Null

$personalizeKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
New-Item -Force -Path $personalizeKey -ErrorAction SilentlyContinue | Out-Null
Set-ItemProperty -Path $personalizeKey -Name SystemUsesLightTheme -Value 1 -Type DWord
Set-ItemProperty -Path $personalizeKey -Name AppsUseLightTheme -Value 1 -Type DWord
[NativeInput]::BroadcastThemeChange()
Start-Sleep -Seconds 4
Assert-AppRunning $process
Save-TrayScreenshot '13-tray-light-taskbar'
Set-ItemProperty -Path $personalizeKey -Name SystemUsesLightTheme -Value 0 -Type DWord
Set-ItemProperty -Path $personalizeKey -Name AppsUseLightTheme -Value 0 -Type DWord
[NativeInput]::BroadcastThemeChange()

Stop-TrayApp $process
Remove-Item -Force (Join-Path $mainConfigFolderPath '.credentials.json'), (Join-Path $workConfigFolderPath '.credentials.json')
$process = Start-TrayApp
Write-TrayButtonNames
Save-TrayScreenshot '14-tray-signed-out'
Click-Element (Find-TrayButton 'claude')
Save-FlyoutScreenshot $process '15-flyout-signed-out'

Invoke-FlyoutButton $process 'Quit'
Start-Sleep -Seconds 2
$process.Refresh()
if (-not $process.HasExited) { throw 'Quit did not close the app' }
Write-Host 'Quit closed the app'
Save-TrayScreenshot '16-tray-after-quit'

Stop-Process -Id $fakeUsageApi.Id -Force -ErrorAction SilentlyContinue
Write-Host 'UI check finished'
