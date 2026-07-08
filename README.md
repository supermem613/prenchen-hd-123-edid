# Prenchen HD-123 EDID override

PowerShell installer for a Windows EDID override for the Prenchen HD-123 12.3FHD portable display.

Some HD-123 units report malformed EDID identity data to Windows, including a physical size of `0 cm x 0 cm`. That can make Windows treat the display as a generic panel and prevent per-monitor scale changes from working correctly.

This script:

1. Overrides the base EDID physical size bytes to `29 cm x 11 cm`.
2. Adds a custom **1600 x 600 @ 60Hz** 8:3 detailed timing.
3. Persists a 150% scale preference for the corrected RTD monitor identity.
4. Switches `\\.\DISPLAY4` to `1600 x 600 @ 60Hz` when Windows exposes the custom mode.

## Use

Download `prenchen-hd-123-edid.ps1`, open PowerShell, and run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\prenchen-hd-123-edid.ps1 --install
```

The script self-elevates with UAC when needed. On the first run, Windows may not expose `1600 x 600` until the monitor EDID is reloaded. If the script says the mode is not available yet, disconnect and reconnect the monitor or restart Windows, then run the same install command again.

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

Finally, it attempts to set:

```text
\\.\DISPLAY4 -> 1600 x 600 @ 60Hz
```

## Compatibility

This script targets the Prenchen HD-123 unit that Windows identifies as:

```text
DISPLAY\RTD0000\4&23BDD226&1&UID48
```

Do not use it for a different monitor ID or display number without reviewing the script and changing the device path and `\\.\DISPLAY4` target.

## License

MIT
