---
title: Collect Warehouse release evidence
audience: release-owner
keywords: AppSource, Warehouse, Partner Center, release gates
locale: en-US
---

# Collect Warehouse release evidence

**Preparation, not release certification.** Final release evidence must identify one signed
candidate built from a named main commit; a merged PR, a compile pass or a successful deployment
alone is not enough.

## Select and prove the candidate

- [ ] Choose the main commit. Default and Test builds are green with nonzero executed tests, zero
      failures and skips, and a signed Default Apps artifact without `internalsVisibleTo`. Record
      full SHA, run/attempt/artifact IDs, package version and SHA256.
- [ ] The AppSource build gate (`tools/AppSourceBuildGate.md`) passed in that run: final compile
      receipts for Default and Test, CodeCop/UICop/AppSourceCop on, `failOn: warning`, Foundation
      28.0.3.530 from the pinned release.
- [ ] Signature trust of the Default `.app` is checked on a Windows machine with NAVX trust
      (`Get-AuthenticodeSignature` returns `Valid`). The CI Signed stage is deferred, so this is a
      manual step.
- [ ] Source guards green on that commit, including the open items #24–#27 if they are wired by then.
- [ ] Unit tests executed on `bc28-w1` and `bc28-is`; message types smoke-tested through the MCP
      server in LCIDs 1033 and 1039.

## Confirm identity, markets and dependencies

| Item | Source value | Evidence / owner |
|---|---|---|
| Identity | Bifrost Warehouse; Origo; `47acac54-3873-496f-9e88-157f36413e89` | Release owner: signed manifest and listing agree |
| Version | Source 28.1.0.0 (the pipeline stamps the build number; UAT holds 28.0.19.x) | Release owner: actual packaged version, never inferred from source |
| BC floor | `application` 28.3.0.0, `platform` 28.0.0.0, runtime 17.0, Cloud | Compiled against BC 28.3 symbols (local) and the BC 28.5 sandbox artifact (CI). Release owner decides whether a 28.3 runtime install test is needed |
| Foundation | `7505e808-6e52-4b96-a328-82573391297a`, Origo, minimum 28.0.3.530 | Foundation must be published on AppSource at 28.0.3.530 or later before this app is submitted |
| Markets | IS, GB, DK, NO, SE, FI, DE, FR, NL, AT, CH, IE, PT, ES | Offer owner: compare with Foundation's markets in Partner Center ([csv](partner-center-markets.csv)) |
| Languages | en-US, is-IS | Release owner: UI and catalogue checked in both |
| Suffix and range | `ori`; 10078385–10078484 | Registration owner: allocation evidence |
| Offer and product ID | No offer yet | Gunnar / offer owner: separately authorized offer creation and ID mapping |

## Collect operator materials

| Material | Working input | Acceptance / owner |
|---|---|---|
| Listing text | [listing/description.md](listing/description.md) | Offer owner approves name, summary, description, categories and keywords |
| Logo | `listing/logo-216.png` (216 × 216, scaled from `app/assets/Logo250x250.png`) | Offer owner: rights and branding |
| Screenshots | None yet; the list is in [listing/screenshots/README.md](listing/screenshots/README.md) | Capture in a demo company with demo data; remove names, e-mail addresses and IDs |
| Product sheet | Missing | Marketing: one-page PDF covering the whole app |
| Help | `https://docs.bifrost.origo.is/en-us/warehouse/` (no context-sensitive help pages: the app has no pages) | Documentation owners: page live in en-US and is-IS (businesscentralal/bifrost#109, branch `docs/publish-warehouse`) |
| Legal | Shared `/en-us/licensing/eula/` and `/en-us/licensing/privacy/` | Gunnar / legal owner: coverage of this app |
| Support | `https://www.origo.is/` | Support owner: contact and process |

## Submit

- [ ] Partner Center fields entered from [listing/README.md](listing/README.md).
- [ ] Upload the signed Default `.app`; dependency Bifrost Foundation.
- [ ] Gunnar approves the publish.
