# Changelog

## [Unreleased]

### Changed (2026-10-01) - Build and deployment aligned with Bifrost Inventory

- AL-Go workflows updated to the same template as Bifrost Inventory (AL-Go Actions v9.2) for continuous deployment of `main` to the Bifrost sandbox.
- Builds on `main` are now code-signed from Azure Key Vault on a Windows runner and versioned with AL-Go versioning strategy 3 (`app.json` stays at `X.Y.0.0`); pull-request builds stay unsigned.
- Removed the docs-only Deploy Reference Documentation workflow; documentation lives in businesscentralal/bifrost.
- Telemetry now goes to the shared Bifröst Application Insights resource, like every other Bifröst app.

### Added (2026-09-29) - Warehouse message contracts (#10)

- All twelve Warehouse message types now expose structured `Msg Contract ori` chapters for envelope, target, parameters, response, errors, effect, metering and related workflows.
- Warehouse discovery now provides distinct English and Icelandic selection descriptions and keywords for every type.
- Replaced the single-type markdown help codeunits with structured contracts; the legacy markdown interface remains as an empty compatibility response until the follow-up removal issue.
- Added warehouse contract conformance tests and shared contract parts.

### Added

- Bifrost Warehouse app and test-app scaffold with registered object ID ranges.
- `Warehouse.BinContent.Get` message type.
- `Warehouse.Activity.Get` message type.
- Foundation read/full permission-set extensions and lifecycle codeunits.

### Added (2026-09-29) - Warehouse message types moved from Foundation (#4)

- The ten Warehouse.* message types (Shipment Create/Post/PreviewPost, Receipt Create/Post/Post.Preview, Pick Create/Register, Putaway Create/Register) moved here from Bifrost Foundation.
- New permission sets BIFROST WhsePost ori and BIFROST WhseInv ori. They are NOT included in the Read/Full sets and must be assigned explicitly.
- Posting previews are no longer gated by posting permission.
- A new write-block subscriber refuses generic data-record writes to the warehouse document tables.
