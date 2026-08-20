# Contributing

## Adding to a profile

Profiles are JSON. Most contributions are a few lines, no code change:

```json
{
  "id": "appx-example",
  "type": "appx",
  "package": "Microsoft.Example",
  "description": "What it is, and what breaks if it goes"
}
```

Two rules for `description`:

- Say what the thing **is**, not just its name.
- Say what the user **loses**. "Removes Widgets - the taskbar widget button
  disappears" is useful. "Removes bloat" is not.

If a tweak is a placebo on some editions, say so in the description. See the
`telemetry-level` entry in `privacy-baseline` for the pattern.

## Adding an action type

Add three functions to `Private/Actions.ps1` and one case to each of the three
dispatchers at the bottom of that file:

- `Resolve-Winnow<Type>` - read state, decide if work is needed, **never write**
- `Set-Winnow<Type>` - perform the change, return a journal entry with `Before`
- `Undo-Winnow<Type>` - take a journal entry, restore `Before`

Set `Reversible = $false` on the entry if undo is not possible, and have `Undo-`
return instructions for the human instead.

## Adding to the guard list

Guard entries need a **rationale in the PR description** explaining what breaks
without the guard. The bar is "a reasonable person would be annoyed if this
disappeared", not "it might be used by something".

## Before opening a PR

```powershell
Invoke-ScriptAnalyzer -Path . -Recurse -Settings ./PSScriptAnalyzerSettings.psd1
Get-ChildItem profiles/*.json | ForEach-Object {
    $null = Get-Content $_ -Raw | ConvertFrom-Json; "$($_.Name) ok"
}
```

CI runs both on push.
