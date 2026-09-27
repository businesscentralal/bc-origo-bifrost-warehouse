# Bifrost Warehouse

- Namespace: `Origo.Bifrost.Warehouse`
- Test namespace: `Origo.Bifrost.Warehouse.Test`
- Foundation dependency: Bifrost Foundation `28.0.0.0`
- Permissions: PermissionSetExtensions onto `BIFROST Read ori` / `BIFROST Full ori`
- No own assignable permission set; no direct `Setup ori` tabledata access.
- P1 message types are read-only: `Warehouse.BinContent.Get` and `Warehouse.Activity.Get`.
- Warehouse Movement write message types are deferred to P2.

## Object ID Ledger

App range: `10036935–10036984`.

| ID(s) | Allocation |
|---|---|
| 10036935 | `Whse MsgType EnumExt ori` |
| 10036936 | `Warehouse.BinContent.Get` enum value |
| 10036937 | `Warehouse.Activity.Get` enum value |
| 10036938 | `Whse BinContent Get Impl ori` |
| 10036939 | `Whse BinContent Get Help ori` |
| 10036940 | `Whse Activity Get Impl ori` |
| 10036941 | `Whse Activity Get Help ori` |
| 10036942 | `Warehouse Install ori` |
| 10036943 | `Warehouse Upgrade ori` |
| 10036944 | `BIFROST Whse - Read ori` |
| 10036945 | `BIFROST Whse - Full ori` |
| 10036946–10036969 | Reserved for P2 Warehouse Movement objects |
| 10036970–10036984 | Free |

Test range: `97000–97099`.

| ID(s) | Allocation |
|---|---|
| 97000 | `Whse BinContent Get Tests ori` |
| 97001 | `Whse Activity Get Tests ori` |
| 97002 | `Whse Test Data ori` |
| 97003–97009 | Reserved for P2 Warehouse Movement tests |
| 97010–97099 | Free |