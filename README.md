# Bifrost Warehouse

Bifrost feature app for warehouse message types on Bifrost Foundation.

## Scope

The app provides warehouse message types for bin content, open warehouse activities, and the warehouse documents moved from Foundation:

- `Warehouse.BinContent.Get` reads bin content by item, location, bin, and variant, with paging.
- `Warehouse.Activity.Get` reads open warehouse activities, with optional line details and filters for activity type, source warehouse document, location, and assigned user.
- `Warehouse.Shipment.Create`, `Warehouse.Shipment.Post`, and `Warehouse.Shipment.PreviewPost`.
- `Warehouse.Receipt.Create`, `Warehouse.Receipt.Post`, and `Warehouse.Receipt.Post.Preview`.
- `Warehouse.Pick.Create` and `Warehouse.Pick.Register`.
- `Warehouse.Putaway.Create` and `Warehouse.Putaway.Register`.

Shipment post, receipt post, pick register, and put-away register require the assignable permission set `BIFROST WhsePost ori`. `Warehouse.Shipment.Post` with `invoice` true also requires `BIFROST WhseInv ori`. Neither set is included in the read or full extensions. Preview types do not consult the posting gate.

Warehouse movement message types are planned for a later phase.

## Object ID ranges

- App: `10078385–10078484`
- Tests: `97000–97099`

## Dependency

- Bifrost Foundation `28.0.0.0` (`7505e808-6e52-4b96-a328-82573391297a`)
