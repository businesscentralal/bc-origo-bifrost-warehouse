# Bifrost Warehouse

- Namespace: `Origo.Bifrost.Warehouse`
- Test namespace: `Origo.Bifrost.Warehouse.Test`
- Foundation dependency: Bifrost Foundation `28.0.3.530` (release `28.0.3`); app and test app compile against it with CodeCop/UICop/AppSourceCop at 0 warnings (19.10.2026). `application` floor 28.3.0.0.
- Permissions: PermissionSetExtensions onto `BIFROST Read ori` / `BIFROST Full ori`
- Own permission sets only for the posting and invoicing gates (`BIFROST WhsePost ori`, `BIFROST WhseInv ori`). Both are `Assignable = true` on purpose: they are the only grants of the gate token tables (`Whse Posting ori`, `Whse Invoice ori`) and must stay out of the read/full extensions. No direct `Setup ori` tabledata access.
- No pages; context-sensitive help base `https://docs.bifrost.origo.is/{0}/help/warehouse/`.
- AppSource build gate: see `tools/AppSourceBuildGate.md` (ported from Bifrost Inventory / Attachments). Build runs with `failOn: warning`.
- Message types: all twenty-four `Warehouse.*` types in `app/src/MessageTypes/`.
- One Impl codeunit per message type. The write types of #41-#47 run their own `OnRun` in
  `Codeunit.Run` isolation and share `Whse Write Context ori` for payload, result and request readers;
  do not add a Proc or Context codeunit per type. Their enum values reuse the Impl codeunit number.
- Post and register types go through `Whse Posting Gate ori` (`BIFROST WhsePost ori`; `BIFROST WhseInv ori`
  for invoice = true).

## Object ID Ledger

App range: `10078385–10078484` (private block, 100 IDs).

| ID(s) | Allocation |
|---|---|
| 10078385 | `Whse MsgType EnumExt ori` (enum values 10078386–10078387, 10078396–10078405) |
| 10078388 | `Whse BinContent Get Impl ori` |
| 10078390 | `Whse Activity Get Impl ori` |
| 10078392 | `Warehouse Install ori` |
| 10078393 | `Warehouse Upgrade ori` |
| 10078394 | `BIFROST Whse - Read ori` |
| 10078395 | `BIFROST Whse - Full ori` |
| 10078406–10078417 | Impl and process codeunits of the ten moved `Warehouse.*` types (warehouse#4) |
| 10078418 | `Whse Bin Get Impl ori` and enum value `Warehouse.Bin.Get` (#45) |
| 10078419 | `Whse Bin Create Impl ori` and enum value `Warehouse.Bin.Create` (#45) |
| 10078420 | `Whse DefaultBin Set Impl ori` and enum value `Warehouse.DefaultBin.Set` (#46) |
| 10078421 | `Whse Movement Create Impl ori` and enum value `Warehouse.Movement.Create` (#41) |
| 10078422 | `Whse Movement Reg Impl ori` and enum value `Warehouse.Movement.Register` (#41) |
| 10078423 | `Whse InvtPick Create Impl ori` and enum value `Warehouse.InventoryPick.Create` (#42) |
| 10078424 | `Whse InvtPick Post Impl ori` and enum value `Warehouse.InventoryPick.Post` (#42) |
| 10078425 | `Whse InvtPut Create Impl ori` and enum value `Warehouse.InventoryPutAway.Create` (#43) |
| 10078426 | `Whse InvtPut Post Impl ori` and enum value `Warehouse.InventoryPutAway.Post` (#43) |
| 10078427 | `Whse InvtMove Create Impl ori` and enum value `Warehouse.InventoryMovement.Create` (#44) |
| 10078428 | `Whse InvtMove Reg Impl ori` and enum value `Warehouse.InventoryMovement.Register` (#44) |
| 10078429 | `Whse Bin Repl Calc Impl ori` and enum value `Warehouse.BinReplenishment.Calculate` (#47) |
| 10078430 | `Whse Write Context ori` (shared by the #41-#47 write types) |
| 10078452 | table `Whse Posting ori` |
| 10078453 | `Whse Posting Gate ori` |
| 10078454 | permission set `BIFROST WhsePost ori` |
| 10078455 | `Whse Record Lookup ori` |
| 10078456 | table `Whse Invoice ori` |
| 10078457 | permission set `BIFROST WhseInv ori` |
| 10078458 | `Whse Data Restrict ori` |
| 10078459 | `Whse Contract Parts ori` (warehouse#10) |
| 10078389, 10078391 | Reserved (do not use) |
| 10078431–10078451, 10078460–10078484 | Free (46 IDs; reserved for #48-#58) |

Test range: `97000–97099`.

| ID(s) | Allocation |
|---|---|
| 97000 | `Whse BinContent Get Tests ori` |
| 97001 | `Whse Activity Get Tests ori` |
| 97002 | `Whse Test Data ori` |
| 97003–97009 | Free (the P2 Warehouse Movement tests use 97080–97091) |
| 97010 | permission set `Whse NoRead Test ori` |
| 97011–97020 | Test codeunits of the ten moved `Warehouse.*` types |
| 97021–97022 | `Whse Shipment Test Helper ori`, `Whse Receipt Test Helper ori` |
| 97023–97024 | `Whse Posting Gate Tests ori`, `Whse Post Gate Grant Tests ori` |
| 97025 | permission set `Whse Gate Test ori` |
| 97026 | `Whse Write Restrict Tests ori` |
| 97027 | `Whse Msg Contract Tests ori` (warehouse#10) |
| 97028 | `Whse Omit Commit Tests ori` (#18) |
| 97029 | `Whse Id Format Tests ori` (#21) |
| 97030–97079 | Free |
| 97080–97091 | Tests of #41-#47: `Whse Bin Get Tests ori`, `Whse Bin Create Tests ori`, `Whse DefBin Set Tests ori`, `Whse Movement Create Tests ori`, `Whse Movement Reg Tests ori`, `Whse InvtPick Create Tests ori`, `Whse InvtPick Post Tests ori`, `Whse InvtPut Create Tests ori`, `Whse InvtPut Post Tests ori`, `Whse InvtMove Create Tests ori`, `Whse InvtMove Reg Tests ori`, `Whse Bin Repl Tests ori` |
| 97092–97099 | Free |
