# Prenchen HD-123 EDID override

PowerShell installer for a Windows EDID override for the Prenchen HD-123 12.3FHD portable display.

Some HD-123 units report malformed EDID identity data to Windows, including a physical size of `0 cm x 0 cm`. That can make Windows treat the display as a generic panel and prevent per-monitor scale changes from working correctly. This script keeps the monitor's existing timing data, overrides only the base EDID physical size bytes to `29 cm x 11 cm`, recalculates the checksum, and persists a 150% scale preference for the corrected RTD monitor identity.

## Use

Download `prenchen-hd-123-edid.ps1`, open PowerShell, and run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\prenchen-hd-123-edid.ps1 --install
```

The script self-elevates with UAC when needed. After it finishes, disconnect and reconnect the monitor or restart Windows so Windows reloads the monitor EDID.

Windows may still cap the live scale at 100% when the display is active at `1920 x 720`. In that mode Windows reports the display source scale range as `100%..100%`, so the persisted value cannot be applied live until Windows exposes a larger scale range for the active mode.

To remove the override and the matching per-monitor scale preference:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\prenchen-hd-123-edid.ps1 --uninstall
```

The misspelled `--unintall` flag is also accepted.

## What it changes

The install command writes a monitor EDID override to:

```text
HKLM:\SYSTEM\CurrentControlSet\Enum\DISPLAY\RTD0000\4&23BDD226&1&UID48\Device Parameters\EDID_OVERRIDE
```

It backs up the current EDID to:

```text
C:\temp\prenchen-hd-123-edid-backups
```

It also sets `DpiValue = 2`, which maps to 150% scale, for Windows scale-factor keys starting with:

```text
RTD00001_
```

## Compatibility

This script targets the Prenchen HD-123 unit that Windows identifies as:

```text
DISPLAY\RTD0000\4&23BDD226&1&UID48
```

Do not use it for a different monitor ID without reviewing the script and changing the device path.

## License

MIT
