# Winnow

**Audit-first Windows debloating.** Inventory the machine, see exactly what would change, then change it — with a rollback journal for everything it touched.

[![PowerShell 5.1+](https://img.shields.io/badge/PowerShell-5.1%2B-5391FE)](https://learn.microsoft.com/powershell/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

> *To winnow:* to separate the grain from the chaff.

---

## Why another one

Most debloat scripts share the same three problems:

1. **They remove appx packages per-user and skip the provisioned copy.** The app comes back on the next feature update or new user profile, and you never notice.
2. **They can't undo.** A `.reg` export can't restore a value that didn't exist before — the correct undo there is *deletion*, not writing a zero back. Winnow records which case applies, per value, per machine.
3. **They break things people actually use.** Disabling `WSearch` kills Start menu and File Explorer search. Removing WebView2 breaks Start menu search, because on Windows 11 search *runs on* WebView2. Winnow refuses both, unconditionally.

Winnow also tells you when a tweak does nothing. `AllowTelemetry = 0` is in every debloat script on GitHub; Windows Home and Pro clamp it to `1` regardless. The profile says so in its own description rather than letting you believe you achieved something.

---

## Quick start

```powershell
git clone https://github.com/mrrogers16/Winnow.git
Import-Module .\Winnow\Winnow.psd1

# 1. Take a baseline. Read-only, no elevation needed (but better with it).
Invoke-WinnowScan -OutputPath .\scans\before

# 2. See what a profile would do. Nothing is written.
Invoke-WinnowApply privacy-baseline

# 3. Commit it. Elevated session required.
Invoke-WinnowApply privacy-baseline -Apply

# 4. Changed your mind?
Invoke-WinnowRollback -Apply
```

---

## Commands

| Command | What it does |
|---|---|
| `Invoke-WinnowScan` | Read-only inventory → CSV/TXT you can diff between runs |
| `Invoke-WinnowApply` | Apply profiles. **Dry-run unless `-Apply`** |
| `Invoke-WinnowRollback` | Reverse a run using its journal |
| `Get-WinnowRun` | List recorded runs |
| `Get-WinnowProfile` | List or inspect profiles |
| `Get-WinnowGuardList` | Show everything Winnow refuses to touch |

---

## Profiles

| Profile | Contents |
|---|---|
| `privacy-baseline` | Telemetry services, CEIP/feedback tasks, the suggestion and silent-install engine, Delivery Optimization peering |
| `debloat-microsoft` | In-box Microsoft apps, both installed and provisioned |
| `browser-hardening` | Edge/Chrome login preload, Edge reporting policies |
| `oem-msi` | MSI laptop OEM layer — keeps fan/thermal control, drops the rest |

Profiles are plain JSON. Adding something to strip is one object, no code change:

```json
{
  "id": "appx-solitaire",
  "type": "appx",
  "package": "Microsoft.MicrosoftSolitaireCollection",
  "description": "Ad-supported Solitaire"
}
```

Supported action types: `registry`, `service`, `scheduledTask`, `appx`, `runValue`.
Full schema: [docs/profile-schema.md](docs/profile-schema.md).

Keep your own profiles outside the repo with `$env:WINNOW_PROFILE_PATH`.

---

## Safety model

**Dry-run by default.** `Invoke-WinnowApply` without `-Apply` writes nothing, ever. It reports current state and what it would change.

**Rollback journal.** Each `-Apply` writes `%ProgramData%\Winnow\runs\<runid>.json` recording, per change, the prior value and whether the value or key existed at all. Rollback replays in reverse order.

**Guard rails.** A hard-coded list of things Winnow refuses to touch regardless of what a profile asks:

- Defender, firewall, BitLocker, Secure Boot task, TPM
- Windows Update chain
- `WSearch`, `PcaSvc` — not telemetry, cost more than they give
- winget (`Microsoft.DesktopAppInstaller`), the Store, Terminal, Snipping Tool, Calculator
- All media codecs (`*VideoExtension*`, `*ImageExtension*`)
- WebView2 / Edge runtime

There is deliberately **no override switch**. If you need to change the list, edit [`Private/Guard.ps1`](Private/Guard.ps1) in a commit you can see in `git log`.

**Not everything is reversible.** Appx removal isn't scriptable in reverse. Winnow marks those entries `Reversible = false`, tells you at the end of the run, and gives reinstall instructions on rollback instead of pretending.

---

## Recommended order on a new machine

1. **Windows Update, then GPU/chipset drivers, then vendor firmware.** Do this *first*. Driver installers re-add components — an NVIDIA update will happily reinstall its telemetry client over the top of your work.
2. `Invoke-WinnowScan` — baseline.
3. `Invoke-WinnowApply <profiles>` — dry run, read it.
4. `-Apply`, reboot.
5. `Invoke-WinnowScan` again and diff. Some listeners only clear after a restart.

---

## Known limitations

- Some OEM tasks are re-armed by their parent suite at boot. `oem-msi` documents which ones and why.
- `Get-Service -StartType` reports `Automatic` for both automatic and automatic-delayed. Rollback restores `Automatic`.
- Appx removal is one-way.
- Telemetry level 0 is not honoured on Home or Pro. This is a Windows limitation, not a bug here.

## Requirements

Windows 10 (2004+) or Windows 11 · PowerShell 5.1 or later · elevation for `-Apply`

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). New profiles are welcome; new entries on the guard list need a rationale in the PR.

## License

MIT — see [LICENSE](LICENSE).

**Use at your own risk.** This modifies system configuration. Read the dry-run output before you pass `-Apply`.
