# Bifrost Warehouse

- Namespace: `Origo.Bifrost.Warehouse`
- Test namespace: `Origo.Bifrost.Warehouse.Test`
- Foundation dependency: Bifrost Foundation `28.0.0.0`
- Permissions: PermissionSetExtensions onto `BIFROST Read ori` / `BIFROST Full ori`
- No own assignable permission set; no direct `Setup ori` tabledata access.
- No message types are included in the scaffold-only change; Warehouse Movement is P2.

## Object ID Ledger

App range: `10036935–10036984`.

| ID(s) | Allocation |
|---|---|
| 10036935 | Message Type enum extension (reserved for issue #1) |
| 10036936–10036937 | `Warehouse.BinContent.Get`, `Warehouse.Activity.Get` values (reserved for issue #1) |
| 10036938–10036941 | Get implementations and help codeunits (reserved for issue #1) |
| 10036942 | `Warehouse Install ori` |
| 10036943 | `Warehouse Upgrade ori` |
| 10036944 | `BIFROST Whse - Read ori` |
| 10036945 | `BIFROST Whse - Full ori` |
| 10036946–10036969 | Reserved for P2 Warehouse Movement objects |
| 10036970–10036984 | Free |

Test range: `97000–97099`.

| ID(s) | Allocation |
|---|---|
| 97000 | Warehouse smoke test; reserved for Bin Content tests in issue #1 |
| 97001 | Warehouse Activity tests (reserved for issue #1) |
| 97002 | Shared Warehouse test data (reserved for issue #1) |
| 97003–97009 | Reserved for P2 Warehouse Movement tests |
| 97010–97099 | Free |