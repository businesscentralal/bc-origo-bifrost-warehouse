# Changelog

## [Unreleased]

### Added (2026-10-19) - Bin master, default bin, movements, inventory documents and bin replenishment (#41-#47)

- `Warehouse.Bin.Get` (10078418) reads bins at a location with optional bin content, paged with take and skip. `Warehouse.Bin.Create` (10078419) inserts one or more bins through Validate, all or nothing, and lists every failing bin. `Warehouse.DefaultBin.Set` (10078420) creates the bin content row when missing (fixed, like the page) and sets Default; the bin that is already default answers `changed: false`. Business Central rejects a second default in OnValidate, so the previous default row is cleared first. (#45, #46)
- `Warehouse.Movement.Create` (10078421) creates a warehouse movement at a directed put-away and pick location from a movement worksheet or from inline lines. `Warehouse.Movement.Register` (10078422) registers it by number or SystemId, including a partial quantity; zero quantity to handle on every line is refused. (#41)
- `Warehouse.InventoryPick.Create` (10078423) creates an inventory pick from a released sales order, purchase return order, outbound transfer, assembly or production consumption; an open pick for the same document is returned with a warning. `Warehouse.InventoryPick.Post` (10078424) posts it, with optional per-line quantity and `invoice` for a sales order. (#42)
- `Warehouse.InventoryPutAway.Create` (10078425) creates an inventory put-away from a released purchase order, sales return order or inbound transfer. `Warehouse.InventoryPutAway.Post` (10078426) posts it, with optional per-line quantity and bin and `invoice` for a purchase order; a tracked line without lot or serial is refused per line. (#43)
- `Warehouse.InventoryMovement.Create` (10078427) creates an inventory movement at a basic warehouse location with bins, from inline lines or assembly consumption. `Warehouse.InventoryMovement.Register` (10078428) registers it, including a partial quantity. fromBin equal to toBin and a quantity above the from-bin content return `InvalidLine`. (#44)
- `Warehouse.BinReplenishment.Calculate` (10078429) runs Calculate Bin Replenishment into a movement worksheet at a directed location; nothing to replenish answers success with an empty line list. (#47)
- Posting gate: `Warehouse.Movement.Register`, `Warehouse.InventoryPick.Post`, `Warehouse.InventoryPutAway.Post` and `Warehouse.InventoryMovement.Register` require `BIFROST WhsePost ori` like the other post and register types; `invoice: true` on inventory pick and put-away post also requires `BIFROST WhseInv ori`. The gate refusal now carries a `nextStep` that names the missing permission set.
- One Impl codeunit per message type: each write type runs its own `OnRun` inside `Codeunit.Run` and shares `Whse Write Context ori` (10078430) for the payload, the result and the request readers. The enum value of each new type reuses its Impl codeunit number. App IDs 10078431-10078451 and 10078460-10078484 stay free.
- Generic `Data.Records.Set` writes are blocked on Bin (table), Bin Content Default, the movement worksheet quantity and bins, and the activity line quantity, bin, zone, lot, serial and expiration fields of the dedicated activity types (`Whse Data Restrict ori`).
- The new types read the request through the shared lookup reader, so `data` that is not a JSON object answers `InvalidParameterFormat` instead of a runtime error (#21 pattern).
- Tests 97080-97091, plus posting-gate deny and grant tests for the four new post and register types in 97023 and 97024.
### Fixed (2026-10-19) - Warehouse posting, put-away and previews with Omit Commit (#18)

- `Warehouse.Shipment.Post` and `Warehouse.Receipt.Post` run inside the caller's transaction when called with Omit Commit, and a Business Central posting error is raised as it is; without Omit Commit a posting error is still answered as `status = Error`.
- `Warehouse.Putaway.Create` with Omit Commit returns an already-open put-away for the posted receipt (`alreadyExisted = true`) and only runs the put-away report when none exists.
- `Warehouse.Shipment.PreviewPost` and `Warehouse.Receipt.Post.Preview` answer `PreconditionFailed` with a next step when called with Omit Commit, before any record is read; the HTTP/MCP path (no Omit Commit) is unchanged. Each type's errors chapter lists the new entry.
- Codeunits 10078407, 10078408, 10078410, 10078411 and 10078415. Test helpers 97021 and 97022 get a `RunMessage` overload with an explicit `OmitCommit`; preview tests (97013, 97016) use `false`. New test codeunit `Whse Omit Commit Tests ori` (97028) covers the preview refusal (document and quantities kept) and the posting-error paths in both modes. Test codeunits 97023, 97024 and 97026 declare their message arguments `temporary`.

### Fixed (2026-10-19) - Strict warehouse identifier validation (#21)

- The nine lookup types (Shipment.Post, Shipment.PreviewPost, Receipt.Post, Receipt.Post.Preview, Pick.Create, Pick.Register, Putaway.Create, Putaway.Register, Activity.Get) answer `InvalidParameterFormat` on `data` when the request is not a JSON object, and on the key when an identifier is `null`, a number, a boolean, an object or an array. Two or more wrong keys are one `MultipleErrors`, in key order. Nothing is looked up or posted while a value is wrong; an absent or empty key stays `MissingParameter`.
- The shared lookup errors chapter (`Whse Contract Parts ori`) describes the format rules and lists exactly one `MultipleErrors` entry. Codeunits 10078390, 10078407, 10078408, 10078410, 10078411, 10078412, 10078414, 10078415, 10078417, 10078455 and 10078459; new test codeunit `Whse Id Format Tests ori` (97029); contract tests in 97027.

### Changed (2026-10-19) - Warehouse identifier contract keys (#24)

- In the target chapter of Shipment.Post, Shipment.PreviewPost, Receipt.Post, Receipt.Post.Preview, Pick.Create and Putaway.Create every identifier key carries its own `data.` prefix. The accepted keys and descriptions are unchanged, and `tools/Test-ContractParameterKeys.ps1` passes. Contract tests in 97027.

### Changed (2026-10-19) - Activity.Get and BinContent.Get help match the code (#34)

- `Warehouse.Activity.Get` keeps documenting its identifier aliases (`activityNo`, `recordSystemId`, `id`), because the alias reading delivered by #37 reads them. Its errors chapter no longer lists `MissingParameter` (a request without an identifier reads the collection) and keeps `ConflictingIdentifiers`, which #37 answers.
- `Warehouse.BinContent.Get` declares its optional `tableView` parameter, so a request with `tableView` no longer gets an `UnknownParameter` warning. Codeunits 10078388, 10078390 and 10078459; contract tests in 97027.

### Fixed (2026-10-19) - Icelandic warehouse refusal text and translation sync (#27, #26)

- Warehouse refusal texts are translated: the Locked refusal labels of the create, post, preview, pick and put-away types now carry Icelandic text, with the English text, placeholders and error codes unchanged. `tools/Test-MixedLanguageLabels.ps1` passes.
- `app/Translations/Bifrost Warehouse.is-IS.xlf` is regenerated from the compiler output with `tools/Update-IcelandicXlf.ps1`, and `tools/Test-IcelandicXlfInSync.ps1` passes. Locale tests in 97011, 97014 and 97018.

### Fixed (2026-10-19) - Warehouse context-sensitive help host

- `contextSensitiveHelpUrl` in `app/app.json` points at `https://docs.bifrost.origo.is/{0}/help/warehouse/`. The Warehouse help pages themselves are maintained in the documentation site.

### Fixed (2026-10-16) - Raise Warehouse app version above UAT to unblock Deploy to Bifrost

- Warehouse main CI/CD #19 (run 38900771455, tip `3fc5293c`, shipping #15) failed on Deploy to Bifrost with `UnprocessableEntity`: the CI/CD build produced appVersion `28.0.0.19` (app.json `28.0.0.0` plus versioningStrategy 3 run revision 19), while UAT already held `28.0.18.0`, so Business Central refused the downgrade.
- Raise the top-level `Bifrost Warehouse` app and `Bifrost Warehouse - Tests` app versions from `28.0.0.0` to `28.0.19.0` in `app/app.json` and `test/app.json` (and the test app's `Bifrost Warehouse` dependency to `28.0.19.0`), keeping the Foundation `28.0.1.0` floor and the sibling app.json version scheme. With versioningStrategy 3 the CI/CD run revision remains the 4th segment, so the next build deploys as `28.0.19.N` - above UAT `28.0.18.0`.
- Version/metadata only: no AL objects, message types, XLF, permissions or IDs change.

### Fixed (2026-10-16) - Posting-gate HTTP test workaround (#39)

- Remove `EnableRegisteredAppHttp` and its setup calls from Whse Posting Gate Tests ori (97023) and Whse Post Gate Grant Tests ori (97024). The dispatcher tests now rely on Foundation's evaluation-sandbox gate fix, while retaining restrictive posting/invoicing permissions and assertions that callers cannot write NAV App Setting.

### Fixed (2026-10-14) - Warehouse activity identifier contract (#37)

- Main-based native compile: configure the existing Bifrost application telemetry endpoint and explicitly initialize activity paging counter in codeunit 10078390; no PR15 commits or test-file renames included.

- Whse Activity Get Impl ori (10078390) resolves all supplied identifiers with Whse Record Lookup ori (10078455), rejects conflicting activities, and reads documented `activityNo`, `id` and `recordSystemId` aliases. GUID aliases reject invalid formats and non-scalar identifier values are refused before lookup; identifier lookups remain single-record reads when combined with filters. Collection paging and line/filter behavior stay unchanged.
- Whse Activity Get Tests ori (97001) adds dispatcher regressions with unique per-test fixtures for conflicting/matching identifiers, aliases, invalid and unknown identifiers, filter isolation and exact translated help in LCIDs 1033/1039. Conflict help now includes localized when/fix/nextStep in en-US/is-IS, with synchronized XLF. The top-level app version stays unchanged.

### Changed (2026-10-13) - Preserve the Bifrost pipeline across AL-Go updates

- Added pipeline guards in `tools/Test-BifrostPipeline.ps1` and the `.github/workflows/BifrostPipeline.yaml` Bifrost Pipeline Guards workflow for main-only signing, shared Default/Test container hooks and full-build trigger coverage; pipeline and guard changes execute paired Default/Test builds. `AGENTS.md` documents preservation of these Bifrost pipeline requirements during system updates.
- `.AL-Go/settings.json` adds `.github/workflows/**` and `tools/Test-BifrostPipeline.ps1` to `fullBuildPatterns`; the guard self-test rejects removal of either pattern.
- Retain only posting-gate test fixtures in codeunits Whse Posting Gate Tests ori (97023) and Whse Post Gate Grant Tests ori (97024), and indirect NAV App Setting read in permission set Whse Gate Test ori (97025): the pipeline-only split reproduced two dispatcher test failures (93 executed, 91 passed, 2 failed). HTTP setup occurs before permission lowering; both tests assert that the caller cannot write settings. Response widths and test filenames stay at main.
- Native warning, telemetry/help metadata and test-fixture repairs are retained in the separate Warehouse contract batch (#18, #19, #25, #35); they are outside this pipeline-only PR. Architect disposition 1791931022.314599 permits unchanged main baseline warnings for this split; no warning suppressions are added.

### Changed (2026-10-12) - AL-Go v9.2 signs on Windows and Current compiles on BC 28.5

- CI/CD on `main` signs with AL-Go-Actions v9.2 on `windows-latest`. Run 38238977303 compiled, then `Sign@v9.0` failed on the Linux runner with `Failed to install signing tool`. `.github/AL-Go-Settings.json` matches Language Models: signing stays on for `main`, with `githubRunner` `windows-latest` and `githubRunnerShell` `pwsh`. System files and workflows are Alpaca-AppSource `4cd474c40c167da7b929d5032d30c23a6bb3b225` (AL-Go-Actions v9.2, Alpaca Actions v2.11).
- Current builds use sandbox artifact `/sandbox/28.5.54151.55751/w1/latest` in `.AL-Go/settings.json` and `.github/Test Current.settings.json`. `.AL-Go/settings.json` is listed in `fullBuildPatterns`. Next Minor and Next Major stay on `////nextminor` and `////nextmajor`. Runtime stays 17.0. The app version stays 28.0.0.0.

### Fixed (2026-10-09) - Warehouse test transaction mode (#19)

- Whse Shipment Test Helper ori (97021) and Whse Receipt Test Helper ori (97022) explicitly use committing Dispatcher execution for posting, preview and put-away tests and match its Text[100] response content type.

### Fixed (2026-10-11) - posting-gate tests grant the dispatcher Company read (#19)

- Whse Gate Test ori (97025) grants indirect read on Company (table 2000000006). The two restrictive gate tests call `Dispatcher.Execute`, and Foundation `Eula Consent ori` reads Company while building the consent key. This is not a direct Company read, not a `Setup ori` grant, and not another version change.

### Fixed (2026-10-10) - UAT dependency installation

- UAT feature-app deployment uses the Foundation app already deployed by its own pipeline in Dev scope, avoiding an unauthorized AppSource Foundation installation. `.github/AL-Go-Settings.json`: `DeployToBifrost.DependencyInstallMode = "ignore"`. AppSource delivery is unchanged; no AL objects or IDs change.

### Changed (2026-10-04) - CI/CD builds only main; every pull request gets a Pull Request Build

- Build policy only, no app change. `CI/CD` runs on pushes to `main` only, and `Pull Request Build` runs for pull requests into any branch. `.github/AL-Go-Settings.json` sets `CICDPushBranches` to `main` and `CICDPullRequestBranches` to `**`, so Update AL-Go System Files keeps the triggers.

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

### Fixed (2026-10-14) - Test compilation alignment for Foundation helper migration (#20)

- Prefix the temporary message-argument variables in test codeunits 97023, 97024 and 97026 with `Temp` to satisfy CodeCop AA0073 on AL 18.1; test behavior and assertions are unchanged.
- Rename test files to match existing objects 97000–97002 and 97010–97027; align response content-type buffers in 97000, 97001, 97023 and 97024 to the dispatcher’s Text[100] parameter, remove the shadowed assertion variable in 97027 and label the assertion format in 97013. Test assertions, permission grants and message contracts are unchanged.

### Changed (2026-10-14) - Build settings aligned with Bifrost Inventory

- Builds use AL-Go versioning strategy 3 (`app.json` stays at `X.Y.0.0`) and retain short-lived artifacts for 30 days.
- Full builds also match changes to `.github/AL-Go-Settings.json`, so repository build settings trigger a full build.

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
