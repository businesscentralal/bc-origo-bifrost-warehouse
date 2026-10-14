# Changelog

## [Unreleased]

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
