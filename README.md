# Bifrost Warehouse

Bifrost feature app for warehouse message types on Bifrost Foundation.

## Scope

The app provides warehouse message types for bin content and open warehouse activities:

- `Warehouse.BinContent.Get` reads bin content by item, location, bin, and variant, with paging.
- `Warehouse.Activity.Get` reads open warehouse activities, with optional line details and filters for activity type, source warehouse document, location, and assigned user.

Warehouse movement message types are planned for a later phase.

## Object ID ranges

- App: `10078385–10078484`
- Tests: `97000–97099`

## Dependency

- Bifrost Foundation `28.0.0.0` (`7505e808-6e52-4b96-a328-82573391297a`)
