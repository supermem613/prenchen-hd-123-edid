$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$DeviceId = 'DISPLAY\RTD0000\4&23BDD226&1&UID48'
$DeviceParams = 'HKLM:\SYSTEM\CurrentControlSet\Enum\' + $DeviceId + '\Device Parameters'
$OverrideKeyName = 'EDID_OVERRIDE'
$OverrideValueName = '0'
$BackupDir = 'C:\temp\prenchen-hd-123-edid-backups'
$PhysicalWidthCm = 29
$PhysicalHeightCm = 11
$DpiValue = 2
$ScaleFactorKeyPrefix = 'RTD00001_'
$DisplayDeviceName = '\\.\DISPLAY4'
$TargetWidth = 1600
$TargetHeight = 600
$TargetFrequency = 60

function Show-Usage {
  @'
Usage:
  powershell -NoProfile -ExecutionPolicy Bypass -File .\prenchen-hd-123-edid.ps1 --install
  powershell -NoProfile -ExecutionPolicy Bypass -File .\prenchen-hd-123-edid.ps1 --uninstall

Also accepts the misspelled --unintall alias.

Actions:
  --install    Apply the EDID override, add 1600x600@60, persist 150% scale, and switch modes when available.
  --uninstall  Remove the EDID override and per-monitor scale preference.

After install or uninstall, disconnect and reconnect the monitor or restart Windows.
'@
}

function Test-IsAdministrator {
  $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = [Security.Principal.WindowsPrincipal]::new($identity)
  return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Invoke-Elevated {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Action
  )

  if (Test-IsAdministrator) {
    return
  }

  $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" $Action"
  Start-Process -FilePath 'powershell.exe' -ArgumentList $arguments -Verb RunAs
  Write-Host "Launched elevated PowerShell for $Action. Accept the UAC prompt."
  exit 0
}

function Set-DetailedTimingDescriptor {
  param(
    [Parameter(Mandatory = $true)]
    [byte[]]$Edid,
    [Parameter(Mandatory = $true)]
    [int]$Offset,
    [Parameter(Mandatory = $true)]
    [int]$PixelClock10KHz,
    [Parameter(Mandatory = $true)]
    [int]$HActive,
    [Parameter(Mandatory = $true)]
    [int]$HBlank,
    [Parameter(Mandatory = $true)]
    [int]$VActive,
    [Parameter(Mandatory = $true)]
    [int]$VBlank,
    [Parameter(Mandatory = $true)]
    [int]$HSyncOffset,
    [Parameter(Mandatory = $true)]
    [int]$HSyncWidth,
    [Parameter(Mandatory = $true)]
    [int]$VSyncOffset,
    [Parameter(Mandatory = $true)]
    [int]$VSyncWidth,
    [Parameter(Mandatory = $true)]
    [int]$HImageMm,
    [Parameter(Mandatory = $true)]
    [int]$VImageMm,
    [Parameter(Mandatory = $true)]
    [int]$Flags
  )

  $Edid[$Offset + 0] = [byte]($PixelClock10KHz -band 0xFF)
  $Edid[$Offset + 1] = [byte](($PixelClock10KHz -shr 8) -band 0xFF)
  $Edid[$Offset + 2] = [byte]($HActive -band 0xFF)
  $Edid[$Offset + 3] = [byte]($HBlank -band 0xFF)
  $Edid[$Offset + 4] = [byte](((($HActive -shr 8) -band 0x0F) -shl 4) -bor (($HBlank -shr 8) -band 0x0F))
  $Edid[$Offset + 5] = [byte]($VActive -band 0xFF)
  $Edid[$Offset + 6] = [byte]($VBlank -band 0xFF)
  $Edid[$Offset + 7] = [byte](((($VActive -shr 8) -band 0x0F) -shl 4) -bor (($VBlank -shr 8) -band 0x0F))
  $Edid[$Offset + 8] = [byte]($HSyncOffset -band 0xFF)
  $Edid[$Offset + 9] = [byte]($HSyncWidth -band 0xFF)
  $Edid[$Offset + 10] = [byte]((($VSyncOffset -band 0x0F) -shl 4) -bor ($VSyncWidth -band 0x0F))
  $Edid[$Offset + 11] = [byte](((($HSyncOffset -shr 8) -band 0x03) -shl 6) -bor ((($HSyncWidth -shr 8) -band 0x03) -shl 4) -bor ((($VSyncOffset -shr 4) -band 0x03) -shl 2) -bor (($VSyncWidth -shr 4) -band 0x03))
  $Edid[$Offset + 12] = [byte]($HImageMm -band 0xFF)
  $Edid[$Offset + 13] = [byte]($VImageMm -band 0xFF)
  $Edid[$Offset + 14] = [byte](((($HImageMm -shr 8) -band 0x0F) -shl 4) -bor (($VImageMm -shr 8) -band 0x0F))
  $Edid[$Offset + 15] = 0
  $Edid[$Offset + 16] = 0
  $Edid[$Offset + 17] = [byte]$Flags
}

function Set-EdidChecksum {
  param(
    [Parameter(Mandatory = $true)]
    [byte[]]$Edid
  )

  $Edid[127] = 0
  $sum = 0
  for ($i = 0; $i -lt 127; $i++) {
    $sum = ($sum + $Edid[$i]) -band 0xFF
  }
  $Edid[127] = [byte]((256 - $sum) -band 0xFF)
}

function Get-BaseEdidOverride {
  $current = [byte[]](Get-ItemProperty -LiteralPath $DeviceParams).EDID
  if ($current.Length -lt 128) {
    throw "EDID for $DeviceId is too short. Expected at least 128 bytes, got $($current.Length)."
  }

  New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
  $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
  [IO.File]::WriteAllBytes((Join-Path $BackupDir "original-edid-$timestamp.bin"), $current)

  $override = [byte[]]::new(128)
  [Array]::Copy($current, $override, 128)
  $override[21] = [byte]$PhysicalWidthCm
  $override[22] = [byte]$PhysicalHeightCm

  Set-DetailedTimingDescriptor `
    -Edid $override `
    -Offset 72 `
    -PixelClock10KHz 6632 `
    -HActive $TargetWidth `
    -HBlank 160 `
    -VActive $TargetHeight `
    -VBlank 28 `
    -HSyncOffset 48 `
    -HSyncWidth 32 `
    -VSyncOffset 3 `
    -VSyncWidth 5 `
    -HImageMm 290 `
    -VImageMm 110 `
    -Flags 0x1A

  Set-EdidChecksum -Edid $override

  return $override
}

function Set-TargetDisplayMode {
  $modeChangerCode = @'
using System;
using System.Runtime.InteropServices;

public static class PrenchenDisplayMode
{
    public const int ENUM_CURRENT_SETTINGS = -1;
    public const int CDS_UPDATEREGISTRY = 0x00000001;
    public const int CDS_TEST = 0x00000002;
    public const int DISP_CHANGE_SUCCESSFUL = 0;
    public const int DM_BITSPERPEL = 0x00040000;
    public const int DM_PELSWIDTH = 0x00080000;
    public const int DM_PELSHEIGHT = 0x00100000;
    public const int DM_DISPLAYFREQUENCY = 0x00400000;

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto)]
    public struct DEVMODE
    {
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmDeviceName;
        public short dmSpecVersion;
        public short dmDriverVersion;
        public short dmSize;
        public short dmDriverExtra;
        public int dmFields;
        public int dmPositionX;
        public int dmPositionY;
        public int dmDisplayOrientation;
        public int dmDisplayFixedOutput;
        public short dmColor;
        public short dmDuplex;
        public short dmYResolution;
        public short dmTTOption;
        public short dmCollate;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmFormName;
        public short dmLogPixels;
        public int dmBitsPerPel;
        public int dmPelsWidth;
        public int dmPelsHeight;
        public int dmDisplayFlags;
        public int dmDisplayFrequency;
        public int dmICMMethod;
        public int dmICMIntent;
        public int dmMediaType;
        public int dmDitherType;
        public int dmReserved1;
        public int dmReserved2;
        public int dmPanningWidth;
        public int dmPanningHeight;
    }

    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern bool EnumDisplaySettingsEx(string lpszDeviceName, int iModeNum, ref DEVMODE lpDevMode, int dwFlags);

    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern int ChangeDisplaySettingsEx(string lpszDeviceName, ref DEVMODE lpDevMode, IntPtr hwnd, int dwflags, IntPtr lParam);
}
'@

  Add-Type -TypeDefinition $modeChangerCode

  $mode = New-Object PrenchenDisplayMode+DEVMODE
  $mode.dmSize = [Runtime.InteropServices.Marshal]::SizeOf([type]'PrenchenDisplayMode+DEVMODE')
  if (-not [PrenchenDisplayMode]::EnumDisplaySettingsEx($DisplayDeviceName, [PrenchenDisplayMode]::ENUM_CURRENT_SETTINGS, [ref]$mode, 0)) {
    Write-Warning "Could not read current mode for $DisplayDeviceName."
    return
  }

  $mode.dmPelsWidth = $TargetWidth
  $mode.dmPelsHeight = $TargetHeight
  $mode.dmDisplayFrequency = $TargetFrequency
  $mode.dmBitsPerPel = 32
  $mode.dmFields = $mode.dmFields -bor [PrenchenDisplayMode]::DM_PELSWIDTH -bor [PrenchenDisplayMode]::DM_PELSHEIGHT -bor [PrenchenDisplayMode]::DM_DISPLAYFREQUENCY -bor [PrenchenDisplayMode]::DM_BITSPERPEL

  $test = [PrenchenDisplayMode]::ChangeDisplaySettingsEx($DisplayDeviceName, [ref]$mode, [IntPtr]::Zero, [PrenchenDisplayMode]::CDS_TEST, [IntPtr]::Zero)
  if ($test -ne [PrenchenDisplayMode]::DISP_CHANGE_SUCCESSFUL) {
    Write-Warning "Windows has not exposed ${TargetWidth}x${TargetHeight}@${TargetFrequency} yet. Reconnect the monitor or restart Windows, then run --install again. Test code: $test."
    return
  }

  $apply = [PrenchenDisplayMode]::ChangeDisplaySettingsEx($DisplayDeviceName, [ref]$mode, [IntPtr]::Zero, [PrenchenDisplayMode]::CDS_UPDATEREGISTRY, [IntPtr]::Zero)
  if ($apply -ne [PrenchenDisplayMode]::DISP_CHANGE_SUCCESSFUL) {
    Write-Warning "Windows accepted the mode test but did not apply ${TargetWidth}x${TargetHeight}@${TargetFrequency}. Apply code: $apply."
    return
  }

  Write-Host "Set $DisplayDeviceName to ${TargetWidth}x${TargetHeight}@${TargetFrequency}."
}

function Get-ScaleFactorKeys {
  $scaleFactorRoot = 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers\ScaleFactors'
  if (-not (Test-Path -LiteralPath $scaleFactorRoot)) {
    return @()
  }

  return @(Get-ChildItem -LiteralPath $scaleFactorRoot | Where-Object { $_.PSChildName.StartsWith($ScaleFactorKeyPrefix) })
}

function Set-ScalePreference {
  $scaleKeys = Get-ScaleFactorKeys
  if ($scaleKeys.Count -eq 0) {
    Write-Warning "No Windows scale-factor key starting with $ScaleFactorKeyPrefix was found."
    return
  }

  $perMonitorRoot = 'HKCU:\Control Panel\Desktop\PerMonitorSettings'
  if (-not (Test-Path -LiteralPath $perMonitorRoot)) {
    New-Item -Path 'HKCU:\Control Panel\Desktop' -Name 'PerMonitorSettings' -Force | Out-Null
  }

  foreach ($scaleKey in $scaleKeys) {
    New-ItemProperty -LiteralPath $scaleKey.PSPath -Name 'DpiValue' -PropertyType DWord -Value $DpiValue -Force | Out-Null

    $perMonitorPath = Join-Path $perMonitorRoot $scaleKey.PSChildName
    if (-not (Test-Path -LiteralPath $perMonitorPath)) {
      New-Item -Path $perMonitorRoot -Name $scaleKey.PSChildName -Force | Out-Null
    }
    New-ItemProperty -LiteralPath $perMonitorPath -Name 'DpiValue' -PropertyType DWord -Value $DpiValue -Force | Out-Null
  }
}

function Install-Override {
  Invoke-Elevated '--install'

  if (-not (Test-Path -LiteralPath $DeviceParams)) {
    throw "Monitor registry path not found: $DeviceParams"
  }

  $override = Get-BaseEdidOverride
  $overridePath = Join-Path $DeviceParams $OverrideKeyName
  if (-not (Test-Path -LiteralPath $overridePath)) {
    New-Item -Path $DeviceParams -Name $OverrideKeyName -Force | Out-Null
  }

  New-ItemProperty -LiteralPath $overridePath -Name $OverrideValueName -PropertyType Binary -Value $override -Force | Out-Null

  $written = [byte[]](Get-ItemProperty -LiteralPath $overridePath).$OverrideValueName
  if ($written.Length -ne $override.Length) {
    throw "Override write verification failed. Expected $($override.Length) bytes, got $($written.Length)."
  }
  for ($i = 0; $i -lt $override.Length; $i++) {
    if ($written[$i] -ne $override[$i]) {
      throw "Override write verification failed at byte $i."
    }
  }

  Set-ScalePreference
  Set-TargetDisplayMode

  Write-Host "Applied EDID override for Prenchen HD-123 / 12.3FHD."
  Write-Host "Physical size is now $PhysicalWidthCm cm x $PhysicalHeightCm cm in the override."
  Write-Host "Added custom ${TargetWidth}x${TargetHeight}@${TargetFrequency} 8:3 timing to the override."
  Write-Host 'Windows scale preference is now persisted as 150% for the corrected RTD monitor identity.'
  Write-Host 'If the mode was not available yet, disconnect and reconnect the monitor or restart Windows, then run --install again.'
}

function Uninstall-Override {
  Invoke-Elevated '--uninstall'

  $overridePath = Join-Path $DeviceParams $OverrideKeyName
  if (Test-Path -LiteralPath $overridePath) {
    Remove-Item -LiteralPath $overridePath -Recurse -Force
    Write-Host 'Removed EDID override for Prenchen HD-123 / 12.3FHD.'
  } else {
    Write-Host 'No EDID override was present for Prenchen HD-123 / 12.3FHD.'
  }
  foreach ($scaleKey in Get-ScaleFactorKeys) {
    $perMonitorPath = Join-Path 'HKCU:\Control Panel\Desktop\PerMonitorSettings' $scaleKey.PSChildName
    if (Test-Path -LiteralPath $perMonitorPath) {
      Remove-Item -LiteralPath $perMonitorPath -Recurse -Force
    }
  }
  Write-Host 'Disconnect and reconnect the monitor or restart Windows for Windows to reload the EDID.'
}

if ($args.Count -ne 1) {
  Show-Usage
  exit 2
}

switch ($args[0].ToLowerInvariant()) {
  '--install' { Install-Override }
  '--uninstall' { Uninstall-Override }
  '--unintall' { Uninstall-Override }
  '--help' { Show-Usage }
  '-h' { Show-Usage }
  default {
    Show-Usage
    exit 2
  }
}
