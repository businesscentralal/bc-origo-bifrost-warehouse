# Bifrost Warehouse

- Namespace: `Origo.Bifrost.Warehouse`
- Test namespace: `Origo.Bifrost.Warehouse.Test`
- Foundation dependency: Bifrost Foundation `28.0.0.0`
- Permissions: PermissionSetExtensions onto `BIFROST Read ori` / `BIFROST Full ori`
- No own assignable permission set; no direct `Setup ori` tabledata access.
- Message types: `Warehouse.BinContent.Get` and `Warehouse.Activity.Get`.
- The 100-ID range fits the warehouse#4 move (~32 objects) and P2 Warehouse Movement.

## Object ID Ledger

App range: `10078385–10078484` (private block, 100 IDs).

| ID(s) | Allocation |
|---|---|
| 10078385 | `Whse MsgType EnumExt ori` |
| 10078386 | `Warehouse.BinContent.Get` enum value |
| 10078387 | `Warehouse.Activity.Get` enum value |
| 10078388 | `Whse BinContent Get Impl ori` |
| 10078389 | `Whse BinContent Get Help ori` |
| 10078390 | `Whse Activity Get Impl ori` |
| 10078391 | `Whse Activity Get Help ori` |
| 10078392 | `Warehouse Install ori` |
| 10078393 | `Warehouse Upgrade ori` |
| 10078394 | `BIFROST Whse - Read ori` |
| 10078395 | `BIFROST Whse - Full ori` |
| 10078396–10078427 | Reserved for warehouse#4 (move of the Foundation `Warehouse.*` message types, ~32 objects) |
| 10078428–10078451 | Reserved for P2 Warehouse Movement objects |
| 10078452–10078484 | Free |

Test range: `97000–97099`.

| ID(s) | Allocation |
|---|---|
| 97000 | `Whse BinContent Get Tests ori` |
| 97001 | `Whse Activity Get Tests ori` |
| 97002 | `Whse Test Data ori` |
| 97003–97009 | Reserved for P2 Warehouse Movement tests |
| 97010 | `Whse No Read ori` |
| 97011–97099 | Free |
