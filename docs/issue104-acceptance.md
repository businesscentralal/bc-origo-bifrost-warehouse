# Warehouse.Document.Get — issue #104

https://github.com/businesscentralal/bc-origo-bifrost-warehouse/issues/104

Gunnar approved wave 1 on 20 November 2026. Implementation and own-tenant verification are complete. The PR's Current state comment records the exact candidate SHA and paired CI run.

| Criterion | Implementation | Verification |
|---|---|---|
| AC01 Receipt lines and quantities after partial posting | Implemented | AL and MCP: own purchase receipt, 10 outstanding → 4 received / 6 outstanding |
| AC02 Released shipment with registered pick | Implemented | AL: own sales shipment, real registered pick, picked quantities and completelyPicked |
| AC03 Paging, filters, empty results | Implemented | AL and MCP: same-line source filters, dates, location, assigned user, status, identifiers and paging |
| AC04 Structured refusals and error entries | Implemented | AL: refusal status/code/nextStep and persisted Foundation response, both languages |
| AC05 Permission denial | Implemented | AL: test permission set without read access returns PermissionDenied |
| AC06 English help, bilingual discovery and refusals | Implemented | AL and MCP in 1033/1039; English chapters and translated discovery/refusals |
| AC07 W1 and IS tests | Implemented | 95 passed / 0 failed / 0 skipped on each of w129-18 and is29-18, including 27 new tests |

The IS lane had a pre-existing Bifröst default-language override of ENU. Clearing it for the existing company-language tests produces the same 95 passing tests as W1; the override is restored afterward. Open documents have no put-away-progress field, so `putAwayQty` is documented as zero; put-away progress belongs to posted receipts.

No UI changes; no clips required by the issue. Licence paths: NOT_RUN, verified before release.
