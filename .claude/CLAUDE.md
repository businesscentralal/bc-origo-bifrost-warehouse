# Bifrost Warehouse

- Namespace: `Origo.Bifrost.Warehouse`
- Test namespace: `Origo.Bifrost.Warehouse.Test`
- Foundation dependency: Bifrost Foundation `28.0.1.0`
- Permissions: PermissionSetExtensions onto `BIFROST Read ori` / `BIFROST Full ori`
- Own permission sets only for the posting and invoicing gates (`BIFROST WhsePost ori`, `BIFROST WhseInv ori`); no direct `Setup ori` tabledata access.
- Message types: all twelve `Warehouse.*` types in `app/src/MessageTypes/`.
- The 100-ID range fits the warehouse#4 move (~32 objects) and P2 Warehouse Movement.

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
| 10078428–10078451 | Reserved for P2 Warehouse Movement objects |
| 10078452 | table `Whse Posting ori` |
| 10078453 | `Whse Posting Gate ori` |
| 10078454 | permission set `BIFROST WhsePost ori` |
| 10078455 | `Whse Record Lookup ori` |
| 10078456 | table `Whse Invoice ori` |
| 10078457 | permission set `BIFROST WhseInv ori` |
| 10078458 | `Whse Data Restrict ori` |
| 10078459 | `Whse Contract Parts ori` (warehouse#10) |
| 10078389, 10078391, 10078418–10078427 | Freed: the markdown help codeunits deleted by warehouse#10 |
| 10078460–10078484 | Free |

Test range: `97000–97099`.

| ID(s) | Allocation |
|---|---|
| 97000 | `Whse BinContent Get Tests ori` |
| 97001 | `Whse Activity Get Tests ori` |
| 97002 | `Whse Test Data ori` |
| 97003–97009 | Reserved for P2 Warehouse Movement tests |
| 97010 | permission set `Whse NoRead Test ori` |
| 97011–97020 | Test codeunits of the ten moved `Warehouse.*` types |
| 97021–97022 | `Whse Shipment Test Helper ori`, `Whse Receipt Test Helper ori` |
| 97023–97024 | `Whse Posting Gate Tests ori`, `Whse Post Gate Grant Tests ori` |
| 97025 | permission set `Whse Gate Test ori` |
| 97026 | `Whse Write Restrict Tests ori` |
| 97027 | `Whse Msg Contract Tests ori` (warehouse#10) |
| 97028–97099 | Free |
