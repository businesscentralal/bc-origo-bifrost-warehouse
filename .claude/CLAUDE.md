# Bifrost Warehouse

- Namespace: `Origo.Bifrost.Warehouse`
- Test namespace: `Origo.Bifrost.Warehouse.Test`
- Foundation dependency: Bifrost Foundation `28.0.0.0`
- Permissions: PermissionSetExtensions onto `BIFROST Read ori` / `BIFROST Full ori`
- No own assignable permission set; no direct `Setup ori` tabledata access.
- No message types are included in the scaffold-only change. The 100-ID range fits the warehouse#4 move (~32 objects) and P2 Warehouse Movement.

## Object ID Ledger

App range: `10078385–10078484` (private block, 100 IDs).

| ID(s) | Allocation |
|---|---|
| 10078385 | Message Type enum extension (reserved for issue #1) |
| 10078386–10078387 | `Warehouse.BinContent.Get`, `Warehouse.Activity.Get` values (reserved for issue #1) |
| 10078388–10078391 | Get implementations and help codeunits (reserved for issue #1) |
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
| 97000 | Warehouse smoke test; reserved for Bin Content tests in issue #1 |
| 97001 | Warehouse Activity tests (reserved for issue #1) |
| 97002 | Shared Warehouse test data (reserved for issue #1) |
| 97003–97009 | Reserved for P2 Warehouse Movement tests |
| 97010–97099 | Free |