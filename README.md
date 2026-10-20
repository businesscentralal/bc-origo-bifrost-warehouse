# Bifrost Warehouse

**App name:** Bifrost Warehouse  
**Publisher:** Origo — **Version:** 28.1.0.0 — **Target:** Cloud (BC 28.3 or later, runtime 17.0)  
**App ID:** `47acac54-3873-496f-9e88-157f36413e89` — **Test app ID:** `6ae41d19-d457-4d62-bd87-0413ff18de75`  
**Object ID ranges:** 10078385–10078484 (tests 97000–97099) — **Namespace:** `Origo.Bifrost.Warehouse`  
**Environments:** Business Central online (SaaS) and the COSMO Alpaca development containers `bc28-is` (CRONUS IS) and `bc28-w1` (CRONUS International Ltd.)

---

## Overview

Bifrost Warehouse is the warehouse module of the Bifröst platform. It publishes thirty-one Bifröst
message types for warehouse work that Bifrost Foundation does not cover: bin content, bin and open
warehouse activity reads, warehouse requests and history reads, bins and default bins, warehouse
shipments and receipts (create, get source documents, release and reopen, preview, post with per-line
quantities), picks, put-aways and movements (create, register), inventory picks, put-aways and movements
for basic warehouse locations, and bin replenishment. An agent or an integration calls them through the same
Queue → Task → Data API as the rest of Bifröst.

Every write goes through Microsoft's own reports and codeunits (Get Source Documents,
Whse.-Source - Create Document, warehouse shipment and receipt posting, Whse.-Activity-Register).
The app reimplements none of that logic. The app has no pages of its own and no setup page: it is
configured through Bifröst Setup in Foundation and through permission sets.

### Message types

The list is the enum extension `Whse MsgType EnumExt ori` in
`app/src/MessageTypes/WhseMsgTypeEnumExt.EnumExt.al`. `Help.Bifrost.Get` and
`Help.Implementation.Get` return the same list and each type's contract at runtime.

| Type | Direction | Purpose | Permission |
|------|-----------|---------|------------|
| `Warehouse.BinContent.Get` | Outbound | Read bin content by item, location, bin and variant, with paging | `BIFROST Read ori` |
| `Warehouse.Activity.Get` | Outbound | Read open warehouse activities, optionally with lines, filtered by type, source document, location or assigned user | `BIFROST Read ori` |
| `Warehouse.Shipment.Create` | Inbound | Create a warehouse shipment from released source documents | `BIFROST Full ori` |
| `Warehouse.Shipment.PreviewPost` | Outbound | Preview posting a warehouse shipment (ship and invoice), rolled back | `BIFROST Read ori` |
| `Warehouse.Shipment.Post` | Inbound | Post a warehouse shipment, optionally with a quantity to ship per line and optionally invoicing its source documents | `BIFROST WhsePost ori`; `BIFROST WhseInv ori` when `invoice` is true |
| `Warehouse.Receipt.Create` | Inbound | Create a warehouse receipt from released source documents | `BIFROST Full ori` |
| `Warehouse.Receipt.PreviewPost` | Outbound | Preview posting a warehouse receipt, rolled back | `BIFROST Read ori` |
| `Warehouse.Receipt.Post` | Inbound | Post a warehouse receipt (received, not invoiced), optionally with a quantity to receive per line | `BIFROST WhsePost ori` |
| `Warehouse.Pick.Create` | Inbound | Create a pick for a warehouse shipment | `BIFROST Full ori` |
| `Warehouse.Pick.Register` | Inbound | Register a pick | `BIFROST WhsePost ori` |
| `Warehouse.Putaway.Create` | Inbound | Create (or return the open) put-away for a posted warehouse receipt | `BIFROST Full ori` |
| `Warehouse.Putaway.Register` | Inbound | Register a put-away | `BIFROST WhsePost ori` |
| `Warehouse.Bin.Get` | Outbound | Read bins at a location, optionally with their content, with paging | `BIFROST Read ori` |
| `Warehouse.Bin.Create` | Inbound | Create one or more bins at a location, all or nothing | `BIFROST Full ori` |
| `Warehouse.DefaultBin.Set` | Inbound | Set the default bin for an item at a location | `BIFROST Full ori` |
| `Warehouse.Movement.Create` | Inbound | Create a warehouse movement at a directed location from a movement worksheet or inline lines | `BIFROST Full ori` |
| `Warehouse.Movement.Register` | Inbound | Register a warehouse movement, fully or partially | `BIFROST WhsePost ori` |
| `Warehouse.InventoryPick.Create` | Inbound | Create an inventory pick for a released outbound source document | `BIFROST Full ori` |
| `Warehouse.InventoryPick.Post` | Inbound | Post an inventory pick, optionally invoicing a sales order | `BIFROST WhsePost ori`; `BIFROST WhseInv ori` when `invoice` is true |
| `Warehouse.InventoryPutAway.Create` | Inbound | Create an inventory put-away for a released inbound source document | `BIFROST Full ori` |
| `Warehouse.InventoryPutAway.Post` | Inbound | Post an inventory put-away, optionally invoicing a purchase order | `BIFROST WhsePost ori`; `BIFROST WhseInv ori` when `invoice` is true |
| `Warehouse.InventoryMovement.Create` | Inbound | Create an inventory movement at a basic warehouse location with bins | `BIFROST Full ori` |
| `Warehouse.InventoryMovement.Register` | Inbound | Register an inventory movement, fully or partially | `BIFROST WhsePost ori` |
| `Warehouse.BinReplenishment.Calculate` | Inbound | Calculate bin replenishment into a movement worksheet at a directed location | `BIFROST Full ori` |
| `Warehouse.Receipt.GetSourceDocuments` | Inbound | Add lines from released purchase orders, sales return orders or inbound transfers to a warehouse receipt, or to a new one at a location; source lines already on another receipt are listed as skipped | `BIFROST Full ori` |
| `Warehouse.Shipment.GetSourceDocuments` | Inbound | Add lines from released sales orders, purchase return orders or outbound transfers to an open warehouse shipment, or to a new one at a location | `BIFROST Full ori` |
| `Warehouse.Shipment.Release` | Inbound | Release a warehouse shipment so picks can be created | `BIFROST Full ori` |
| `Warehouse.Shipment.Reopen` | Inbound | Reopen a released warehouse shipment; refused while open picks exist | `BIFROST Full ori` |
| `Warehouse.Request.Get` | Outbound | Read the warehouse requests at a location (source documents waiting for a receipt or shipment), with paging | `BIFROST Read ori` |
| `Warehouse.PostedDocument.Get` | Outbound | Read posted warehouse receipts or shipments, optionally with lines, with paging | `BIFROST Read ori` |
| `Warehouse.RegisteredActivity.Get` | Outbound | Read registered picks, put-aways or movements, optionally with lines, with paging | `BIFROST Read ori` |
| `Warehouse.Journal.Create` | Inbound | Insert warehouse item or reclassification journal lines (with lot, serial or package numbers) at a directed location | `BIFROST Full ori` |
| `Warehouse.Journal.Register` | Inbound | Register a warehouse item or reclassification journal batch; answers the warehouse register and entry range | `BIFROST WhsePost ori` |
| `Warehouse.PhysInventory.Calculate` | Inbound | Calculate a warehouse physical inventory into a physical inventory journal batch | `BIFROST Full ori` |
| `Warehouse.PhysInventory.Register` | Inbound | Write counted quantities and register the physical inventory batch | `BIFROST WhsePost ori` |
| `Warehouse.Adjustment.Calculate` | Inbound | Calculate the warehouse adjustment into an empty item journal batch (post it with `Inventory.ItemJournal.Post`) | `BIFROST Full ori` |
| `Warehouse.Worksheet.GetDocuments` | Inbound | Fill a pick or put-away worksheet from released shipments or posted receipts | `BIFROST Full ori` |
| `Warehouse.Worksheet.CreateActivities` | Inbound | Create picks or put-aways from a worksheet, with quantities to handle and grouping; zero lines are skipped | `BIFROST Full ori` |
| `Warehouse.ActivityLine.Split` | Inbound | Split a warehouse activity line | `BIFROST Full ori` |
| `Warehouse.ActivityLine.ChangeBin` | Inbound | Change the bin of a warehouse activity line | `BIFROST Full ori` |
| `Warehouse.ActivityLine.SetQtyToHandle` | Inbound | Set, fill or clear the quantity to handle on warehouse activity lines | `BIFROST Full ori` |
| `Warehouse.ActivityLine.AssignTracking` | Inbound | Assign lot, serial and package numbers on warehouse activity lines, splitting a line per entry | `BIFROST Full ori` |

Update this table in the same change as any new or renamed message type.

---

## Functional Flow

1. An external caller (an agent through the Bifröst MCP server, an integration, or Business Central
   itself) posts a message to Foundation's Queue → Task → Data route with a `Warehouse.*` type.
2. Foundation resolves the type to its implementation codeunit in this app through the
   `Message Type ori` enum and the `Msg Interface ori` interface.
3. Posting and registering types ask `Whse Posting Gate ori` whether the caller holds
   `BIFROST WhsePost ori`; `Warehouse.Shipment.Post`, `Warehouse.InventoryPick.Post` and
   `Warehouse.InventoryPutAway.Post` with `invoice` true also need `BIFROST WhseInv ori`. Preview
   types do not consult the gate.
4. The implementation reads the request, resolves the document, calls the matching Microsoft report
   or codeunit and writes a JSON response, or a structured error (`MissingParameter`,
   `InvalidParameterFormat`, `RecordNotFound`, `PermissionDenied`, …) through the Foundation
   argument.
5. Discovery (`Help.Bifrost.Get`) lists the types, and each type answers its contract chapters,
   including the inbound (receipt → post → put-away → register) and outbound
   (shipment → pick → register → post) workflow, through `Help.Implementation.Get`.

---

## Benefits

- **One governed API for warehouse work.** Receiving, put-away, picking, shipping, bin adjustments, counts and worksheet planning can be run
  without opening the Business Central client.
- **Microsoft logic, not a copy.** Every write goes through the standard reports and codeunits, so
  validation, posting and ledger entries are exactly what a warehouse worker would get.
- **Posting is separate from writing.** Creating documents needs Foundation's full role; posting and
  registering need `BIFROST WhsePost ori`, and invoicing a shipment needs `BIFROST WhseInv ori`, so an
  integration can prepare documents without being able to post them.
- **Preview before posting.** Shipment and receipt previews show the entries that posting would
  create and roll everything back.
- **Safe generic writes.** Warehouse shipment, receipt, activity and journal line tables are closed to
  `Data.Records.Set`, so callers use the typed message types that keep Microsoft's validation.
- **Self-describing.** Every type publishes its parameters, response, errors, effect and related
  types at runtime, in English and Icelandic.

---

## Logic Flow

| Step | Object | What happens |
| --- | --- | --- |
| Install / upgrade | `Warehouse Install ori` (10078392), `Warehouse Upgrade ori` (10078393) | Set the initial-release upgrade tag per company. |
| Posting gate | `Whse Posting Gate ori` (10078453), `Whse Posting ori` (10078452), `Whse Invoice ori` (10078456) | Write permission on the token table `Whse Posting ori` is the posting permission (only `BIFROST WhsePost ori` grants it); write permission on `Whse Invoice ori` is the invoicing permission (only `BIFROST WhseInv ori` grants it). |
| Record lookup | `Whse Record Lookup ori` (10078455) | Resolves document numbers and `id` / `recordSystemId` aliases and refuses conflicting identifiers. |
| Contracts | `Whse Contract Parts ori` (10078459) | Shared contract chapters (effects, workflows) used by the implementation codeunits. |
| Write isolation | `Whse Write Context ori` (10078430) | The write types of bins, default bins, movements, inventory documents, bin replenishment, get source documents, shipment release and reopen, and shipment and receipt posting, warehouse journals, worksheets and activity lines store the validated request here and run their own `OnRun` through `Codeunit.Run` (without a return value under Omit Commit), so a failure leaves nothing written. |
| Journals | `Whse Journal Helper ori` (10078451) | Reads and checks the journal batch keys, the directed location and the template type, and registers a batch through `Whse. Jnl.-Register Batch` for the journal and physical inventory types. |
| Worksheets | `Whse Worksheet Helper ori` (10078468) | Reads and checks a pick or put-away worksheet for the two worksheet types. |
| Activity lines | `Whse ActLine Helper ori` (10078466) | Resolves the activity and its lines (a line of another activity is `ConflictingIdentifiers`) for the four activity line types. |
| Readers | `Whse Msg Values ori` (10078467) | Shared JSON readers, date and array readers, unknown-key refusal and declared-error entries of the #48-#57 types. |
| Write restriction | `Whse Data Restrict ori` (10078458) | Subscribes to Foundation's `OnAfterIsTableWriteRestrictedForDataRecords` and closes the Warehouse Shipment, Receipt, Activity and Journal header and line tables and the Bin table to `Data.Records.Set`; field blocks cover Bin Content Default, the worksheet quantity and bins, the warehouse shipment status, the receipt and shipment quantities to handle, the counted quantity and the activity line quantity, bin, zone and tracking fields. |
| Per-line quantities | `Whse Doc Line Qty ori` (10078438) | Reads and checks `lines[]` for receipt and shipment posting and previews, validates Qty. to Receive or Qty. to Ship, and summarises posted and remaining quantity per line. The previews bind it so the quantities are set inside Business Central's preview run and rolled back with it. |

Types that need the posting permission: `Warehouse.Shipment.Post`, `Warehouse.Receipt.Post`,
`Warehouse.Pick.Register`, `Warehouse.Putaway.Register`, `Warehouse.Movement.Register`,
`Warehouse.InventoryPick.Post`, `Warehouse.InventoryPutAway.Post`,
`Warehouse.InventoryMovement.Register`, `Warehouse.Journal.Register` and
`Warehouse.PhysInventory.Register`.

---

## Setup & Configuration

1. Install Bifrost Foundation 28.0.3.530 or later and complete its setup (Bifröst Setup).
2. Install Bifrost Warehouse. There is no app setup page; the message types are available as soon
   as the app is installed.
3. Grant permissions:
   - Foundation's `BIFROST Read ori` and `BIFROST Full ori` roles are extended by
     `BIFROST Whse - Read ori` and `BIFROST Whse - Full ori`; no separate assignment is needed for
     reads and document creation.
   - Assign **`BIFROST WhsePost ori`** (*Warehouse Posting Gate*) to users or service principals that
     may post shipments and receipts or register picks and put-aways.
   - Assign **`BIFROST WhseInv ori`** (*Whse Invoice Gate*) as well when they may post a shipment with
     `invoice` true.
4. The underlying Business Central setup still applies: locations with Require Receive, Require
   Shipment, Require Put-away and Require Pick as needed, bins and bin contents, warehouse employees,
   and posting setup for the source documents.

---

## Example Scenario

A warehouse system ships a released sales order:

1. `Warehouse.Shipment.Create` with the sales order creates a warehouse shipment.
2. `Warehouse.Pick.Create` creates the pick for that shipment, and `Warehouse.Activity.Get` returns
   it with its lines for the handheld scanner.
3. A service principal with `BIFROST WhsePost ori` calls `Warehouse.Pick.Register` when the items
   are picked.
4. `Warehouse.Shipment.PreviewPost` shows the entries that posting would create.
5. `Warehouse.Shipment.Post` posts the shipment. With `invoice` true the caller also needs
   `BIFROST WhseInv ori`; without it the call returns `PermissionDenied` and nothing is posted.

---

## Objects

### Tables

| ID | Name | Purpose |
| --- | --- | --- |
| 10078452 | `Whse Posting ori` | Permission token for the posting gate; stores no records |
| 10078456 | `Whse Invoice ori` | Permission token for the invoicing gate; stores no records |

### Pages

None. The app has no pages or page extensions.

### Enum extensions

| ID | Name | Purpose |
| --- | --- | --- |
| 10078385 | `Whse MsgType EnumExt ori` | The forty-two `Warehouse.*` values on Foundation's `Message Type ori` |

### Codeunits

| IDs | Area | Codeunits |
| --- | --- | --- |
| 10078388, 10078390 | Reads | `Whse BinContent Get Impl ori`, `Whse Activity Get Impl ori` |
| 10078406–10078408 | Shipments | `Whse Shipment Create Impl ori`, `Whse Shipment Post Impl ori`, `Whse Ship. Prev. Post Impl ori` |
| 10078409–10078411 | Receipts | `Whse Receipt Create Impl ori`, `Whse Receipt Post Impl ori`, `Whse Rcpt Post Prev. Impl ori` |
| 10078412–10078414 | Picks | `Whse Pick Create Impl ori`, `Whse Pick Create Process ori`, `Whse Pick Register Impl ori` |
| 10078415–10078417 | Put-aways | `Whse Putaway Create Impl ori`, `Whse Putaway Create Proc. ori`, `Whse Putaway Register Impl ori` |
| 10078418–10078420 | Bins | `Whse Bin Get Impl ori`, `Whse Bin Create Impl ori`, `Whse DefaultBin Set Impl ori` |
| 10078421–10078422 | Movements | `Whse Movement Create Impl ori`, `Whse Movement Reg Impl ori` |
| 10078423–10078428 | Inventory documents | `Whse InvtPick Create Impl ori`, `Whse InvtPick Post Impl ori`, `Whse InvtPut Create Impl ori`, `Whse InvtPut Post Impl ori`, `Whse InvtMove Create Impl ori`, `Whse InvtMove Reg Impl ori` |
| 10078429 | Replenishment | `Whse Bin Repl Calc Impl ori` |
| 10078446–10078451 | Journals | `Whse Journal Create Impl ori`, `Whse Journal Reg Impl ori`, `Whse PhysInvt Calc Impl ori`, `Whse PhysInvt Reg Impl ori`, `Whse Adjustment Calc Impl ori`, `Whse Journal Helper ori` |
| 10078460–10078461, 10078468 | Worksheets | `Whse Wksh GetDocs Impl ori`, `Whse Wksh CreateAct Impl ori`, `Whse Worksheet Helper ori` |
| 10078462–10078466 | Activity lines | `Whse ActLine Split Impl ori`, `Whse ActLine ChgBin Impl ori`, `Whse ActLine SetQty Impl ori`, `Whse ActLine Track Impl ori`, `Whse ActLine Helper ori` |
| 10078467 | Readers | `Whse Msg Values ori` |
| 10078430 | Write isolation | `Whse Write Context ori` |
| 10078431–10078434, 10078438 | Document flow | `Whse Rcpt GetSrcDocs Impl ori`, `Whse Ship GetSrcDocs Impl ori`, `Whse Shipment Release Impl ori`, `Whse Shipment Reopen Impl ori`, `Whse Doc Line Qty ori` |
| 10078435–10078437 | Requests and history | `Whse Request Get Impl ori`, `Whse PostedDoc Get Impl ori`, `Whse RegActivity Get Impl ori` |
| 10078392, 10078393, 10078458 | Lifecycle | `Warehouse Install ori`, `Warehouse Upgrade ori`, `Whse Data Restrict ori` |
| 10078453, 10078455, 10078459 | Shared | `Whse Posting Gate ori`, `Whse Record Lookup ori`, `Whse Contract Parts ori` |

### Permission sets

| ID | Name | Assignable | Purpose |
| --- | --- | --- | --- |
| 10078454 | `BIFROST WhsePost ori` | Yes | Posting gate: post shipments, receipts and inventory picks and put-aways; register picks, put-aways, movements, inventory movements, warehouse journals and warehouse physical inventories |
| 10078457 | `BIFROST WhseInv ori` | Yes | Invoicing gate: `Warehouse.Shipment.Post`, `Warehouse.InventoryPick.Post` and `Warehouse.InventoryPutAway.Post` with `invoice` true |
| 10078394 | `BIFROST Whse - Read ori` (extension) | — | Extends Foundation's `BIFROST Read ori` |
| 10078395 | `BIFROST Whse - Full ori` (extension) | — | Extends Foundation's `BIFROST Full ori` |

---

## Dependencies

| App | ID | Publisher | Version |
| --- | --- | --- | --- |
| Bifrost Foundation | `7505e808-6e52-4b96-a328-82573391297a` | Origo | 28.0.3.530 |
| Base Application (via `application`) | — | Microsoft | 28.3.0.0 |

The Foundation floor is the Foundation release the app compiles against with CodeCop, UICop and
AppSourceCop at zero warnings (release `28.0.3`, package 28.0.3.530), the same floor as the sibling
Bifröst apps. The `application` floor 28.3.0.0 matches the siblings; the app is compiled locally
against BC 28.3 symbols and in CI against the BC 28.5 sandbox artifact. The test app additionally
depends on Bifrost Warehouse itself and on Microsoft's Tests-TestLibraries, Library Assert, Test
Runner, Any and Library Variable Storage.

---

## Repository layout

| Folder | Content |
| --- | --- |
| `app/` | The AppSource app (`Bifrost Warehouse`) |
| `app/src/MessageTypes/` | Message type enum extension, contract parts, record lookup and the implementation codeunits by area |
| `app/src/Posting/` | Posting and invoicing gate and their permission token tables |
| `app/src/Permissions/` | Permission sets and Foundation role extensions |
| `app/src/Lifecycle/` | Install, upgrade and warehouse document write restriction |
| `app/docs/appsource/` | AppSource listing text, market list and release checklist |
| `test/` | Test app (`Bifrost Warehouse - Tests`) |
| `tools/` | Source guards and the AppSource build gate ([tools/AppSourceBuildGate.md](tools/AppSourceBuildGate.md)) |
| `.AL-Go/`, `.github/` | AL-Go for GitHub / COSMO Alpaca pipeline configuration |

---

## Development

- Open `al.code-workspace` in VS Code.
- Development containers: COSMO Alpaca `bc28-is` and `bc28-w1`. Publish and run the unit tests on
  both.
- Compile locally with `alc.exe` plus CodeCop, UICop and AppSourceCop. The build is expected to be
  warning-free; CI runs the same analyzers on the app and the test app with `failOn: warning`.
  `app.json` suppresses only **AS0081**, for the `internalsVisibleTo` entry the test app needs; the
  Default build removes both before compiling.
- Command-line `alc` does not raise AS0011 (mandatory affix); AL-Go CI is the gate, so check the
  ` ori` suffix yourself.
- Source guards (`.github/workflows/SourceGuards.yaml`): no call stack in responses, validated
  `tableView`, nothing obsolete, permission coverage, Icelandic keyword counts, unique object and
  enum value IDs, build inputs (allocations and the Foundation floor) and the compiler symbol-alias
  gate, contract parameter keys (#24), mixed-language labels (#27) and three-part message type names. Open guard items:
  - #26 Icelandic translation: Source Guards run only the self-test. After a compile, run
    `tools/Update-IcelandicXlf.ps1`, check `tools/Test-IcelandicXlfInSync.ps1` and commit
    `app/Translations/Bifrost Warehouse.is-IS.xlf`.
  - #25 help links: not wired in. The app has no pages, and the documentation site creates no
    help folder for an app without pages, so `tools/Test-HelpLinks.ps1` would need to accept an
    app with zero pages.
- Standards: [Origo BC Development Standards](https://github.com/OrigoSoftwareSolutions/bc-dev-standards).
  Project rules are in `.claude/CLAUDE.md`; agent context is in [AGENTS.md](AGENTS.md).

---

## Documentation

All public documentation lives in the [businesscentralal/bifrost](https://github.com/businesscentralal/bifrost)
site repository and is published at <https://docs.bifrost.origo.is>.

| What | Where |
| --- | --- |
| Product documentation | <https://docs.bifrost.origo.is/en-us/warehouse/> |
| Privacy statement and EULA | <https://docs.bifrost.origo.is/en-us/licensing/privacy/>, <https://docs.bifrost.origo.is/en-us/licensing/eula/> |
| AppSource listing and release checklist | [app/docs/appsource/](app/docs/appsource/README.md) |
| Release notes | [CHANGELOG.md](CHANGELOG.md) |

Message-type contracts are also served by the app at runtime through `Help.Bifrost.Get` and
`Help.Implementation.Get`.

### Context-Sensitive Help

`app.json` declares `contextSensitiveHelpUrl` = `https://docs.bifrost.origo.is/{0}/help/warehouse/`
and `supportedLocales` `["en-US", "is-IS"]`. The app has no pages, so no page declares a
`ContextSensitiveHelpPage` slug, and the documentation site has no help instance for Warehouse (its
rules allow no help page without a Business Central page). A page added later needs a slug and both
locale pages in businesscentralal/bifrost.

---

© 2026 Origo ehf.
