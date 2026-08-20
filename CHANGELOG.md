# Changelog

All notable changes to this project are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
this project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.1.0] - 2026-08-19

### Added
- `Invoke-WinnowScan` - read-only inventory of apps, services, scheduled tasks,
  startup entries, privacy registry state, listening ports and security posture.
- `Invoke-WinnowApply` - profile engine, dry-run by default.
- `Invoke-WinnowRollback` / `Get-WinnowRun` - per-machine rollback journal.
- `Get-WinnowProfile`, `Get-WinnowGuardList`.
- Action types: `registry`, `service`, `scheduledTask`, `appx`, `runValue`.
- Profiles: `privacy-baseline`, `debloat-microsoft`, `browser-hardening`, `oem-msi`.
- Unconditional guard list covering Defender, BitLocker, Secure Boot, the
  Windows Update chain, WSearch, PcaSvc, winget, media codecs and WebView2.

### Notes
- Appx removal is recorded as irreversible; rollback reports reinstall
  instructions rather than failing silently.
- `runValue` actions match by wildcard, because Edge and Chrome autolaunch
  entries carry a per-install GUID suffix.
