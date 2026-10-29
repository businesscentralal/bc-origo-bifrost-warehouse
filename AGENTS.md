# Bifrost Warehouse

- Namespace: `Origo.Bifrost.Warehouse` / `Origo.Bifrost.Warehouse.Test`
- Follow OrigoSoftwareSolutions/bc-dev-standards.
- Permissions: reads and document creation extend Foundation's `BIFROST Read ori` /
  `BIFROST Full ori` (`BIFROST Whse - Read ori`, `BIFROST Whse - Full ori`). The two assignable
  sets are the gates: `BIFROST WhsePost ori` (10078454; `Whse Posting Gate ori` checks write
  permission on the token table `Whse Posting ori`) for shipment/receipt posting and pick/put-away
  registering, and `BIFROST WhseInv ori` (10078457; token table `Whse Invoice ori`) for
  `Warehouse.Shipment.Post` with `invoice` true. Both must stay assignable and stay out of the
  read/full extensions: nothing else grants posting or invoicing. Add no other assignable set.
- Product Foundation floor remains 28.0.3.530; the test app and CI use Foundation
  28.0.10.632 (release `28.0.10`) for the restricted licence-admin role regression;
  `application` floor 28.3.0.0. CodeCop, UICop and AppSourceCop run on app and test app with
  `failOn: warning`.
- No pages: `contextSensitiveHelpUrl` is `https://docs.bifrost.origo.is/{0}/help/warehouse/`; a new
  page needs a `ContextSensitiveHelpPage` slug and both locale pages in businesscentralal/bifrost.
- Do not grant or read Foundation's `Setup ori` table directly.
- App ID range: `10078385–10078484` (100 IDs; the warehouse#4 move and P2 Warehouse Movement both fit); test ID range: `97000–97099`.

## AppSource build gate

`tools/Assert-AppSourceBuild.ps1` runs from `.AL-Go/PipelineInitialize.ps1`,
`.AL-Go/CompileAppWithBcCompilerFolder.ps1`, `.AL-Go/PostCompileApp.ps1`,
`.AL-Go/PipelineFinalize.ps1` and the Pipeline stage step in `_BuildALGoProject.yaml`. It was
ported from Bifrost Inventory / Bifrost Attachments; see `tools/AppSourceBuildGate.md`. The Signed
stage is deferred (no NAVX trust on hosted runners). Changing the Foundation floor or the BC
artifact needs the pins in `tools/appsource_gate.py`, `tools/stage_foundation_inputs.py` and
`tools/check_build_inputs.py` reviewed together.

## Preserve the Bifrost build pipeline during system updates

Run `tools/Test-BifrostPipeline.ps1` and `tools/Test-SharedAlpacaContainer.ps1` before
opening a pipeline PR; the independent **Bifrost Pipeline Guards** workflow runs both.
AL-Go and Alpaca updates must retain sequential Default/Test builds, filtered container
creation, physical container identity, Test production-app republishing, Default internals
stripping, signing requests, deferred cleanup, merged settings before secrets, and Test-only
upgrade skipping. Keep this repository's app IDs, action versions, dependency settings and
deployment variables. Apply compatible upstream updates and reapply the Bifrost custom blocks
before pushing; do not disable the guard or exclude generated workflows from future updates.

## Message type names

Shipped message type names have exactly three nonempty dot-separated parts: `Domain.Entity.Action`.
Run `tools/Test-MessageTypeNames.ps1 -SelfTest` and `tools/Test-MessageTypeNames.ps1 -AppFolder ./app`.
The shared guard is adopted from Foundation core#1037; test apps are exempt from this naming rule.
