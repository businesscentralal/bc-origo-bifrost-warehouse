# Changelog

## [Unreleased]

### Changed (2026-10-01) - Warehouse.Putaway.Create declares effect irreversible (#14)

- `Warehouse.Putaway.Create` runs Business Central's `Whse.-Source - Create Document` report, which commits each put-away it creates, so the type now declares effect `irreversible` (still idempotent: it returns an already-open put-away). The Orchestrator's Omit Commit guard refuses it in a rollback chain. Its selection description and overview say so.
- `Warehouse.Pick.Create` stays `write`: its report commits only when a print option is set, which Bifröst never does.

### Changed (2026-10-01) - complete the Warehouse message contracts and remove the markdown help procedure (#10, #11)

- The twelve Warehouse message types implement every chapter of the current `Msg Contract ori`, so the app builds against Foundation again (`main` failed with AL0582 on `GetWorkflow`, `GetExamples`, `GetNotes` and, for five types, `GetParameters`).
- The receipt, put-away, shipment and pick types return a `workflow` chapter with the inbound (receipt → post → put-away → register) or outbound (shipment → pick → register → post) flow, built once in `Whse Contract Parts ori`.
- Every message type codeunit drops `GetMessageHelpAsMarkdownDocument`. Foundation removed it from `Msg Interface ori` (core#198); help is the contract chapters that `Help.Implementation.Get` returns.
- Bifrost Foundation dependency raised to 28.0.0.186, the first Foundation build without the procedure, in `app/app.json` and `test/app.json`.
- The contract test codeunit 97027 is renamed `Whse Msg Contract Tests ori` (the old name exceeded 30 characters) and declares `System.TestLibraries.Utilities`, so the test app compiles again.

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
