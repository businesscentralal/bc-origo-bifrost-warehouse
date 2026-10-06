# Changelog

## [Unreleased]

### Changed (2026-10-05) - align with Bifrost Foundation 28.0.1

- The Foundation dependency floor is **28.0.1.0** in `app/app.json` and `test/app.json`, the same floor as Bifrost Language Models and Bifrost Attachments.
- The warehouse tables already declare `Extensible`; this alignment changes no table or page extensibility.
- `tools/` carries Foundation's source guards. The Source Guards workflow runs the five selected source checks: no call stack in answers, validated table views, no obsolete, permission coverage, and Icelandic keyword counts. Contract-parameter and mixed-language guards are copied but not wired in.
- Migrate 23 removed Dispatcher helper calls in creation/posting/preview implementations (10078406–10078409, 10078411–10078412, 10078415) to Foundation Request Value Reader ori (10078336) and Posting Preview Helper ori (10078335), preserving arguments and responses.
- Replace repeated/filler discovery keywords in Whse Pick Create Impl ori (10078412), Whse Shipment Create Impl ori (10078406) and Whse Shipment Post Impl ori (10078407) with Icelandic equivalents and regenerate translations.
- Extend receipt creation tests (97014) and shipment posting tests (97012) for typed-input rejection and persisted date overrides; assert captured entry counts in receipt/shipment preview suites (97016, 97013).
- Align the seven ordinary (non-forced) write-restriction calls in Whse Write Restrict Tests ori (97026), rename the Whse MsgType EnumExt ori (10078385) file, and preserve contract serialization/paging while removing mechanical warnings in Whse Contract Parts ori (10078459) and Whse Activity Get Impl ori (10078390).
- Help Links is not wired in until `businesscentralal/bifrost` main has `help/warehouse/`.

### Changed (2026-10-01) - Warehouse.Putaway.Create declares effect irreversible (#14)

- `Warehouse.Putaway.Create` runs Business Central's `Whse.-Source - Create Document` report, which commits each put-away it creates, so the type now declares effect `irreversible` (still idempotent: it returns an already-open put-away). The Orchestrator's Omit Commit guard refuses it in a rollback chain. Its selection description and overview say so.
- `Warehouse.Receipt.Create` (Business Central's Get Source Documents report commits each receipt header) and `Warehouse.Pick.Create` (created through `Codeunit.Run` with a return value, which commits) declare `irreversible` too, with their selection descriptions and overviews. `Warehouse.Shipment.Create` stays `write`: report 5753 has no commit on the shipment path.

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
