$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$DeviceId = 'DISPLAY\RTD0000\4&23BDD226&1&UID48'
$DeviceParams = 'HKLM:\SYSTEM\CurrentControlSet\Enum\' + $DeviceId + '\Device Parameters'
$OverrideKeyName = 'EDID_OVERRIDE'
$OverrideValueName = '0'
$BackupDir = 'C:\temp\prenchen-hd-123-edid-backups'
$PhysicalWidthCm = 29
$PhysicalHeightCm = 11

function Show-Usage {
  @'
Usage:
  powershell -NoProfile -ExecutionPolicy Bypass -File .\prenchen-hd-123-edid.ps1 --install
  powershell -NoProfile -ExecutionPolicy Bypass -File .\prenchen-hd-123-edid.ps1 --uninstall

Also accepts the misspelled --unintall alias.

Actions:
  --install    Apply an EDID override for the Prenchen HD-123 / 12.3FHD.
  --uninstall  Remove the EDID override.

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

  $sum = 0
  for ($i = 0; $i -lt 127; $i++) {
    $sum = ($sum + $override[$i]) -band 0xFF
  }
  $override[127] = [byte]((256 - $sum) -band 0xFF)

  return $override
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

  Write-Host "Applied EDID override for Prenchen HD-123 / 12.3FHD."
  Write-Host "Physical size is now $PhysicalWidthCm cm x $PhysicalHeightCm cm in the override."
  Write-Host 'Disconnect and reconnect the monitor or restart Windows for Windows to reload the EDID.'
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
