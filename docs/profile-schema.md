# Profile schema

A profile is a JSON file in `profiles/` (or any directory on
`$env:WINNOW_PROFILE_PATH`, semicolon separated).

```json
{
  "name": "my-profile",
  "description": "One line explaining scope and what it deliberately leaves alone.",
  "actions": [ ... ]
}
```

| Field | Required | Notes |
|---|---|---|
| `name` | yes | Should match the filename |
| `description` | no | Shown in `Get-WinnowProfile` and at the top of an apply run |
| `actions` | yes | Array of action objects |

Every action requires `id` and `type`. `id` must be unique **across all
profiles** — CI enforces this — because `-Include` / `-Exclude` and the rollback
journal key on it.

`description` is optional but effectively mandatory in practice: it is what the
user reads in the dry run before deciding.

---

## `registry`

```json
{
  "id": "cdm-silent-installs",
  "type": "registry",
  "description": "Stop Windows silently installing promotional apps",
  "path": "HKCU:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\ContentDeliveryManager",
  "value": "SilentInstalledAppsEnabled",
  "data": 0,
  "kind": "DWord"
}
```

| Field | Required | Default |
|---|---|---|
| `path` | yes | PowerShell-style (`HKCU:\...`), backslashes escaped in JSON |
| `value` | yes | Value name |
| `data` | yes | Desired data |
| `kind` | no | `DWord`. Also `QWord`, `String`, `ExpandString`, `MultiString`, `Binary` |

**Rollback** records whether the *key* and the *value* existed beforehand:

- value existed → restored to its prior data and type
- value did not exist → deleted
- key did not exist → deleted, but only if Winnow created it and it is still empty

That distinction is the whole reason the journal exists.

---

## `service`

```json
{
  "id": "svc-diagtrack",
  "type": "service",
  "description": "Connected User Experiences and Telemetry",
  "service": "DiagTrack",
  "startupType": "Disabled",
  "stop": true
}
```

| Field | Required | Default |
|---|---|---|
| `service` | yes | Service short name, not display name |
| `startupType` | no | `Disabled`. Also `Manual`, `Automatic` |
| `stop` | no | `true` |

A missing service is reported as "not present", not an error — profiles are
shared across machines with different hardware.

**Caveat:** `Get-Service` reports `Automatic` for both automatic and
automatic-delayed. Rollback restores `Automatic`.

---

## `scheduledTask`

```json
{
  "id": "task-ceip-consolidator",
  "type": "scheduledTask",
  "description": "CEIP data consolidation and upload",
  "taskPath": "\\Microsoft\\Windows\\Customer Experience Improvement Program\\",
  "taskName": "Consolidator"
}
```

`taskPath` must have a **leading and trailing backslash**. Tasks at the root use
`"\\"`.

Only disabling is supported — Winnow never unregisters a task, so rollback is
always possible.

---

## `appx`

```json
{
  "id": "appx-bing-news",
  "type": "appx",
  "description": "Microsoft News",
  "package": "Microsoft.BingNews",
  "removeProvisioned": true
}
```

| Field | Required | Default |
|---|---|---|
| `package` | yes | Package `Name`, not `PackageFullName` |
| `removeProvisioned` | no | `true` |

Removes the installed package for all users **and** the provisioned copy.
Skipping the provisioned half is why apps reappear after feature updates.

**Not reversible.** The journal marks it, and rollback prints reinstall
instructions.

---

## `runValue`

```json
{
  "id": "run-edge-autolaunch",
  "type": "runValue",
  "description": "Remove Edge's hidden background preload at login",
  "hive": "HKCU",
  "match": "MicrosoftEdgeAutoLaunch_*"
}
```

| Field | Required | Default |
|---|---|---|
| `match` | yes | Wildcard against value names under `...\CurrentVersion\Run` |
| `hive` | no | `HKCU`. Also `HKLM` |

Wildcard rather than exact name because Edge and Chrome suffix their autolaunch
entries with a per-install GUID — a hard-coded name works on exactly one machine.

Rollback restores the removed name/data pairs.

---

## Adding a new type

See [CONTRIBUTING.md](../CONTRIBUTING.md). Three functions in
`Private/Actions.ps1`, one case in each of the three dispatchers.
