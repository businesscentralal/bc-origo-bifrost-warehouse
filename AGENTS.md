# Bifrost Warehouse

- Namespace: `Origo.Bifrost.Warehouse` / `Origo.Bifrost.Warehouse.Test`
- Follow OrigoSoftwareSolutions/bc-dev-standards.
- Feature app: extend Foundation permission sets; do not add an assignable permission set.
- Do not grant or read Foundation's `Setup ori` table directly.
- Warehouse message types are read-only in P1; Warehouse movement writes are deferred to P2.
- App ID range: `10036935–10036984`; test ID range: `97000–97099`.