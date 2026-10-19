# AppSource build gate

Ported on 2026-10-19 from Bifrost Attachments (`bc-origo-bifrost-attachments`, issue #78,
`tools/AppSourceBuildGate.md` on main). The scripts are unchanged apart from the product
identity: the Test friend is `Bifrost Warehouse - Tests` (`6ae41d19-d457-4d62-bd87-0413ff18de75`),
read from `test/app.json`. Section numbers and pins below are the Attachments design record;
the Foundation pins (523 fixture, 530 candidate) and the BC 28.5 / BC 29 Base Application
profiles are shared because both apps build against the same Foundation release and artifact.

The shipping build must provide actual final compiler settings, a complete clean
compile, compiled NAVX identities and current-run hook receipts. A setting file or
source-only friend removal is insufficient. `PipelineInitialize` preserves the
existing Default friend/AS0081 stripping and the Alpaca initialization.

`PipelineInitialize` explicitly installs the real Run-AlPipeline
`CompileAppWithBcCompilerFolder` callback using Alpaca's parent-context scope
mechanism; AL-Go v9.2 does not auto-register that filename. An existing compiler
override blocks replacement pending its owner's coordination.
The callback snapshots the real symbol directory **before**
the helper copies its newly built product there. It forwards the original helper
parameters and output callback and retains an isolated compiler log.
`PostCompileApp` receives the returned package, app type and final compilation
parameters, checks the intended CodeCop, UICop and AppSourceCop flags and
`failOn=warning`, and captures executable/cop/helper hashes before cleanup.
`PipelineFinalize` requires all expected product/test receipts and matches them
to the actual `.buildartifacts/Apps` and `TestApps` outputs. Translation precompiles
are classified separately and cannot substitute for a final compile receipt.

The reader accepts the genuine compiler's NAVX v2 40-byte header and its declared
ZIP payload, checks CRCs and unique manifest/entries, and compares AppId, publisher,
name, full version, source commit and compiler identity. Default carries no friend
grants. The Test product carries exactly the Warehouse test friend;
the test app carries none. Final output content must match the compile receipt.
An arbitrary ZIP, `.app` filename, signature tail or stale output cannot pass.

The separate controlled523 Foundation fixture is main
`336b91d9fff11b71ae5cd75dee08186d4218bf07`, run `37544940349`, attempt 2,
`Origo_Bifrost Foundation_28.0.2.523.app`, SHA256
`5901bebe66b44e91ed6110620e62ee45d122ba9e0378dcfda4aeef4d00d3ae0f`.
The controlled fixture retains these exact bytes. Current actual precompile inventory
requires the internally approved exact candidate530 below, with zero product self-app inputs. Test must use the exact just-built product. Changing the approved
input requires a reviewed tooling change; the app dependency floor is
**28.0.3.530** (`tools/check_build_inputs.py` refuses a lower floor). Symbol inventories are independent of the donated manifest guard.

Run/attempt/job, checkout SHA, compiled-source SHA, build mode, script hashes,
package/content digests and source hashes are retained in sanitized JSON under
`.buildartifacts/AppSourceGate/<mode>`. The checkout can be a synthetic PR merge;
the manifest's compiled-source commit is checked independently. Existing receipts
cannot be reused. Missing/displaced hooks, truncated later logs, disabled cops,
fallbacks, workspace compilation and unsupported compiler collection fail closed.
Container-only compilation needs a supported identity collector before acceptance.

## Infrastructure and acceptance holds

The concrete workflow patch is an external review artifact, **not applied here**.
It runs `Assert-AppSourceBuild.ps1 -Stage Pipeline` immediately after RunPipeline,
then `-Stage Signed` immediately after the existing Sign action when shipping
signing is intended. It preserves signing selection, action pins and credentials.
Windows `Get-AuthenticodeSignature` must return `Valid` for the actual NAVX output
with a signer certificate and supported SIP/trust; absence or an unsupported
provider is a blocker. Signing is allowed to change whole-package bytes, but
must preserve every package entry/manifest. No synthetic signature success is
used by the tests. Failed builds retain the original failure and upload sanitized
receipts only.

In this repository the Signed stage is deferred as in Attachments: the workflow runs the
Pipeline stage only. Signature trust of the Default package is checked by hand on a Windows
machine with NAVX trust before submission (see `app/docs/appsource/release-checklist.md`).

## Tooling regressions

Generate isolated genuine NAVX fixtures with the installed compiler and run:

```powershell
./tools/New-AppSourceGateFixtures.ps1 -CompilerDll <actual-alc.dll> -Dotnet <dotnet> -OutputFolder <temporary-fixture-folder>
./tools/Test-AppSourceBuildGate.ps1 -FixtureFolder <temporary-fixture-folder> -FoundationPackage <controlled-523.app> -CandidateFoundationPackage <exact-Apps530.app> -MeasuredBasePackage <exact-BC29-BaseApplication.app>
python -m unittest discover -s tools/tests -p test_build_inputs.py -v
```

Missing real packages fails the fixture suite, never skips it. The isolated
`tools/fixtures` codeunit is never included in the product/test apps and consumes
no product allocation. Those compiles exercise NAVX/tooling behavior; they do not
claim product, effective-analyzer, BC runtime or signature-trust certification.

## Isolated Foundation staging (#78 input continuation)

`stage_foundation_inputs.py stage --input request.json --destination <fresh-dir>`
validates the already downloaded immutable Apps/TestApps archives and exact
allowlisted provenance, then extracts into distinct `Apps/` and `TestApps/`
directories. It writes `selection.json`, `helper-inputs.json`, `installApps.json`
and `installTestApps.json`. No downloads, helper installation or hook changes
occur. Maximum 128 files and 128 MiB per inventory/archive; flat `.app` artifact
entries only. URLs, GUIDs, wildcard inputs and symlinks fail closed and need an
explicitly reviewed adapter; they are never silently dropped.

The controlled523 Foundation Apps pin remains
`5901bebe66b44e91ed6110620e62ee45d122ba9e0378dcfda4aeef4d00d3ae0f`,
source `336b91d9fff11b71ae5cd75dee08186d4218bf07`, run `37544940349`,
attempt 2, Apps artifact `11459147009`, with zero friends. Only the exact
same-AppId Foundation product collision from TestApps artifact `11459677378`
is excluded. All distinct genuine dependencies remain; parenthesized test
inputs retain the helper's skip-test-execution marker. Default/Test Warehouse
friend stripping and dependency floor are untouched.

The request contains `context` (run, attempt, sourceCommit, checkoutSha, mode),
`artifacts` keyed Apps/TestApps (archive path and provenance fields repository,
sourceSha, run, attempt, artifactId, archiveSha256, expired, conclusion), and
optional explicit local-file arrays `otherApps`/`otherTestApps`. This is a
caller-provided provenance contract checked against the immutable pins, not an
independent live API or signature-trust attestation. Pipeline owner must supply
actual authorized API metadata and current run identity.

`validate --input consumed.json --destination <staged-dir>` rehashes actual
`installApps` and `installTestApps` arrays against the current-context receipt
and both archives. Optional `symbols` verifies the exact Foundation consumed
by compilation. Call validation before helper installation and again with real
compiler inputs. Changing a package, omitting/reordering/substituting an input,
wrong provenance or stale/missing receipt fails. `rejected-input.json` captures
allowlisted on-disk hashes/identity before the existing precompile failure;
it does not convert a failed gate into success.

AL-Go v9.2's `Resolve-DependencyFiles` extracts/copies both archives into one
folder before RunPipeline. RunPipeline reads both JSON arrays before calling
Run-AlPipeline. Helper initialization precedes dependency installation, but
cannot recover overwritten signed bytes without separately retained Apps.
Alpaca publication also scans `.dependencies` independently of compiler symbols.
A compiler-folder copy alone cannot certify install/probing inputs. Integration
must preserve isolated archives and replace the actual arrays before these
consumers; the review-only owner patch documents that boundary. No supported
whole-hook runtime integration has been established or applied. Workspace compilation remains blocked separately.

Run `Test-FoundationStaging.ps1` with both genuine archive paths available under
its artifact folder and the compiler-produced fixture folder. Fixture tests
prove utility selection and refusal behavior, not product compile/runtime,
signature trust, live runner arrays or independent review acceptance.

Callback and symbol boundary checks (#78 continuation):
`tools/Test-AppSourceCallback.ps1` invokes the actual PowerShell callback and
collector with a native Python verifier and controlled compiler. It checks the
one-package return, original output forwarding, cloned parameters, isolated
logs, native refusal before compile, compiler exceptions and module-scope
installation/foreign-override refusal. These language fixtures do not run AL.

BeforeCompile records both the cache (at most 128 packages) and
`compilerFolder/symbols` (at most 256 packages), with at most 128 MiB on disk per
package and the resource profiles below. PostCompile rehashes both:
pre-existing cache entries and compiler-folder entries must remain identical;
new cache dependencies must match exact pre-observed compiler-folder entries.
Exactly one new output entry must match the returned package identity and hash.
Missing/duplicate/substituted paths, inputs or output copies fail acceptance.
Translation observations cannot replace final snapshots. The exact Apps530 pin
below requires zero friends; dependency floor, analyzers and failure policy remain
unchanged.
Receipts set `consumedInputsCertified=false`: boundary observations cannot prove
transient alc inputs, installed/probed dependencies, real helper timing or trust.
Actual helper6.1.18/Alpaca runtime and infrastructure integration remain blocked.

## Rejected precompile inputs

A refused precompile records both the app cache (`symbolsFolder`) and compiler
folder (`compilerSymbolsFolder`) in `rejected-input.json`. Each observed input
has source-folder attribution, presence, disk byte count and SHA256 when within
the existing 128 MiB per-package bound. Malformed manifests still retain the disk
hash; missing folders are explicitly recorded. The combined inventory retains
at most 128 inputs, cache first and compiler second, with top-level `truncated`
when inputs exceed that count or a package exceeds the byte bound. Oversized
packages record their byte count and truncation without reading/hashing them.
Thus an offending input appears when within these bounds; overflow evidence is
explicitly incomplete. Context and manifest metadata remain allowlisted, and
unrecognized build URLs remain redacted. Receipt collection or writing failures
preserve the original gate exception. These failure observations certify neither
transient compiler consumption nor signature trust.


## Separate compiler catalog and actual app cache (#78)

The complete compiler catalog is measured independently from the actual
`appSymbolsFolder` package cache. The genuine helper receives its original
folders and parameters. Equivalent compiler-catalog filename aliases are removed before that
measurement so the inventory counts one package. A byte-identical copy, the
same zip entry content, a ReadyToRun wrapper whose embedded app has that
content, and the same app id and version with the same `SymbolReference.json`
and canonical compiler manifest are one package. The versioned filename is
kept. Build timestamps and `TRANSLATIONFILE` / `LCGTRANSLATIONFILE` packaging
flags are not compiler conflicts. The same app id with a different symbol
reference or compiler manifest, or two versions of that id, fails and no alias
is removed. The app-symbol cache still rejects every duplicate app id and
version. No other package is pruned and no private compiler view is used.
The catalog limit is 256 packages and 1 GiB aggregate on disk; the app cache limit is
128 packages and 512 MiB aggregate, including preexisting inputs and the output
copy. Each package is limited to 128 MiB on disk and a 16 MiB manifest. The generic
profile permits 128 MiB expanded content and 4096 ZIP entries; only the exact
measured Base identity/hash below permits 512 MiB expanded content and 16384
entries. The catalog has a separate 4 GiB expanded-work bound; the app cache keeps
its 512 MiB expanded bound. The retained BC29 sample requires 1,863,664,153 bytes
of wrapper plus embedded-app expansion. These finite bounds do not certify the
complete runner catalog.
The compiler catalog has a finite 180 second elapsed budget, including alias normalization. Every individual package and the app-cache inventory retain their 60 second budgets, with checks between 1 MiB reads. Alias normalization also enforces the existing 4 GiB catalog expanded-work bound before removing any alias. The BC28.5 runner catalog contains 178 packages / 407,716,896 disk bytes; the rejected Windows run exhausted the former 60 second catalog window. The exact public-artifact reconstruction matches every one of the 124 captured runner hashes. After three equivalent aliases are removed, its 175 packages account for 3,983,563,745 expanded bytes; the normalized inventory hash is unchanged by the deadline separation.
These finite design limits are **not validated Windows runner capacity**. Actual
catalog/cache metadata, bytes, hashes, exact folders and dependency resolution
must be measured on a current successful Default/Test runner before acceptance.

The NAVX reader streams package and expanded-entry hashes, validates CRCs, rejects
path symlinks, case-insensitive filename collisions and conflicting duplicate
AppId/version content,
and compares the input hash and stable file metadata before/after measurement.
It records dependency, Application, Platform and PropagateDependencies metadata.
The bounded resolver observes helper6.1.18 semantics: an existing highest
compatible version wins; otherwise every compatible catalog version is copied.
Existing packages propagate dependencies only when configured; copied packages
follow their dependencies and implicit Application/System inputs. Identity,
minimum-version and overwrite ambiguities fail closed. This comparison does not
replace the helper or establish equivalence/actual transient consumption.

`symbol-measurements.json` retains complete sanitized boundary metadata before
later Foundation pin or resolution failures. Failure receipts retain bounded
samples, explicit truncation, folder counts/bytes and incomplete-enumeration flags.
Final helper additions must equal the predicted full copy set, and the exact
output-copy delta is required. `consumedInputsCertified` and
`runnerCapacityValidated` stay false; real helper/runner evidence is a separate gate.
The exact Apps530 candidate is required by current precompile checks; 523 remains
a distinct controlled fixture. Candidate content approval does not approve signature
trust.


## Internally reviewed exact candidate and measured profile

Internal technical decisions on 2026-10-07 approve one exact BC29 Base Application
profile: identity `437dbf0e-84ff-417a-965d-ed2bb9650972`, Microsoft,
Base Application29.0.54011.55935, SHA256
`10ebba923b6f8d3b6d676cc1f1db16a8a5d4519ff8ca4f45bbd2e778b52d289c`.
The original embedded source has8665entries/379592378expanded bytes. For these
exact bytes and identity only, the bound is16384entries/512MiBexpanded. The Current
build's Base Application wrapper `a2e638554f9c97d37f760d6ab42703e1ed136fd229676e79bb1d1a8224a23d23`
(Microsoft Base Application 28.5.54151.55751, 98891185 disk bytes) is the same kind of
exact profile: 9 outer entries, 261371054 outer expanded bytes, and an embedded app of
8602 entries and 373064901 expanded bytes. That outer hash lifts the embedded app to
16384 entries and 512 MiB expanded. A compiler-catalog copy of a package already measured
under the catalog budget is not charged again against the app-cache 512 MiB expanded bound.
The copy still counts toward the cache package count and disk-byte bound. Any other cache
package still counts. Generic
4096entries/128MiBexpanded and128MiBdisk limits remain; any changed or converted
package hash needs its own measured technical disposition. Full CRC/hash reads
under the deadline are still required. Folder aggregate budgets stay unchanged;
proposed2GiBexpanded inventory capacity is not approved as validated capacity.

Current compilation-boundary candidate Foundation is exactly28.0.3.530 from
main`8ec074f4ac69ac9bde15807cf16d21bee045332f`, run37679390622/attempt1,
Apps artifact11508979803, archive SHA256
`21c6331c47d3134d1f3c8c77f240d021fa47710f6fbdebc974b733e0b708bad8`,
package SHA256`b95e0eccf7a4038531cea08f0441e757ac176c7c4ff06b1b8eb9d25ac0dd3a88`,
compiler18.1.43.7601 and zero friend grants. All identity, source, build and byte
fields are required, including presence of the original signature content.
Presence is not Windows signature trust. Candidate approval does not release
actual runner equality, runtime or signing acceptance. When AL-Go extracts the
Foundation TestApps package onto the same filename as the approved Apps package,
BeforeCompile puts the pinned Apps bytes back before the symbol cache is read.
Any other Foundation hash still fails and is not replaced.

Staging defaults to the explicit `candidate530` profile, receipt schema2. It
verifies both complete archives/provenance, preserves Apps bytes and excludes
only the exact same-AppId TestApps collision (artifact11510930013, archive
SHA256`0a4a24e4fa1afc56e60c00ea807d8cd9a91f55f21f144c81f458e14521bd0e73`,
package SHA256`391ba3df7917913ce4fd932096e0f8d5e474d45d0ee78c090f5abee37b1fbfe7`,
with Foundation Tests friend).523remains the explicit `controlled523` staging
fixture; it cannot satisfy the current compilation-boundary530candidate check.
Unknown profiles, changed archives/provenance, swapped Test inputs, missing or
extra same-AppId inputs and mutations fail closed. Returned helper arrays must
actually be wired by the existing pipeline owner; no workflow is changed here.

Run staging tests with the genuine archives for both profiles:
`Test-FoundationStaging.ps1 -ArtifactFolder <controlled523archives> -FixtureFolder <fixtures> -CandidateArtifactFolder <candidate530archives>`.
This executes collector/staging tests, not a mock runner or signature approval.

## Native completion and rejected-input custody

The PowerShell collector requires both native exit zero and exactly one
case-sensitive `AppSource gate: <action> passed` line. Definitions without an
entry point, a marker for another action, extra output and native failures refuse
compilation; request cleanup and the original compiler return/exception remain.
The marker detects an inert script, not independent validation or BC acceptance.

When package parsing rejects a compiler/cache input, its path is attached to the
original error and prioritized in the bounded rejected-input receipt. A malformed
package after the 128-item diagnostic cap therefore retains its disk hash and
folder attribution within the existing byte/time bounds. Truncation remains
explicit and never certifies a complete inventory. The 129-distinct-package
regression mutates genuine compiler fixtures; it is diagnostic test evidence.

The approved `latestBuild` workflow-artifact pin `1.0.3.530` (containing app
`28.0.3.530`) is applied in settings. The user-authorized completion also applies
failure-only upload of bounded rejected-input receipts. The artifact pin does not
replace any exact candidate checks. Historical run37697457309 package bytes were not retained;
its manifest layout cannot be inferred from source samples. Fresh runner capture
must preserve exact run/source identity and rejected/consumed bytes in protected
custody before a format-policy change is considered.

## ReadyToRun dependency envelopes

Dependency inventories accept a ReadyToRun envelope only when its explicit
manifest identifies one bounded embedded NAVX package. The envelope and embedded
package retain separate hashes; their identities must match, both expansions
consume the finite inventory budget, and duplicate/ambiguous/nested/injected
inputs are rejected. This does not accept ReadyToRun shipping output or certify
signature trust. The retained Microsoft Any and Base Application wrappers are
genuine regression fixtures, not substitutes for a fresh complete runner capture.

`Test-AppSourceBuildGate.ps1` also requires `ReadyToRunAnyPackage`,
`EmbeddedAnyPackage`, and `ReadyToRunBasePackage`; it runs the envelope regressions
alongside the original gate and symbol-policy suites. The combined exact-source
tooling run passed 92 tests (45 gate, 10 policy, 15 envelopes, 22 staging), with
zero skips. Application CI and BC runtime verification remain separate.
