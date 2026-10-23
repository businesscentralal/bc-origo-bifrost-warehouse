# Warehouse PR85 acceptance matrix

Candidate: `e4a0701a2f8bcf53ca917e438e81b29bce32eb50` on `codex/worker4-warehouse83-setup`. Main `7a8c9317246e585356d12cb838d78c5511213194` merged normally. Retained source owner: Alvíss (worker-4).

| Acceptance / finding | Implemented | Current candidate verification | Remaining independent acceptance |
|---|---|---|---|
| AC01 registration | Existing Warehouse Extensions registration retained | Compile and source guards pass; full suite466/466/0/0; current-run UI14pass | Claude bc28-w1 registration before/after Finish |
| AC02 welcome / operations / docs | Direct modal operations call; business guidance unchanged | Compile passes; full suite466/466/0/0; current-run UI14pass | Claude EN/IS live modal/docs checks |
| AC03 HTTP / F1 / F4 | Modal Foundation call has no try scope; management has NAV App Setting read only; no settings fixture writes | New restrictive codeunit97004: 2 executed,2 passed,0 failed,0 skipped. Actual app HTTP status and real administrator-note control covered, no write permission. Full suite466/466/0/0 passes | Claude must exercise **Enable HTTP through Warehouse wizard**, then refresh in1033/1039; no old receipt carried forward |
| AC04 user access / F1 | Users and Permission Sets modal calls have no try scope; no assignments added | Compile passes; current-run UI14pass | Claude live modal actions in1033/1039 |
| AC05 Finish/cancel | Existing explicit completion semantics unchanged | Full native suite466/466/0/0 passes; existing original acceptance is historical only | Claude live current-head Finish/cancel |
| AC06 Icelandic / finding5 | Aðstoðuð uppsetning wording in help/docs; administrator note now names Warehouse | XLF generated from current source and synchronization guard passes; current-run UI14pass | Claude every new caption/instruction/action/tooltip in1039 plus1033 |
| AC07 compatibility / permissions | Released baseline28.3.0.36 preserved; no new public API break | Product/test compile CodeCop/UICop/AppSourceCop0errors0warnings; PermissionCoverage/IDs pass. Source Guards40004854413 green; PR Build40004854190 still running at final readback (Default succeeded; Test in progress) | Current-tip CI completion, Claude receipt, Grok clearance and eligible approval |
| AC08 help / CHANGELOG | Icelandic help corrected; Unreleased entry names objects10078385/10078386 and test97004 | Source changes present; separate docs repository unchanged by worker4 | Architect/Claude own external help publication (bifrost#121), release sequencing and genuine Gunnar H2 |

Owned runtime f00f227f7231 / alviss-worker4-warehouse79-20261023, Warehouse+Tests28.3.0.85 installed from this exact candidate; Foundation28.0.9.618. Previous original HTTP-enabled state is preserved; no replay of the original explicit Foundation administrator action, no backend/EULA/trial/licence writes. No message type changed against current main; no MCP message-type pass claimed. Full configured suite inventory:466tests/54codeunits; actual counts466executed/466passed/0failed/0skipped. Current-run own UI14passed/0failed/0skipped with six prior harness failures retained. Native fixture rollback probes2/2; no MCP fixtures created. Language1033 restored and existing completion/HTTP preserved.

Gunnar H2 for new wizard/permission sets/App Registry remains pending. Claude receipt, Grok exact-tip clearance, Architect merge/deploy, Tester UAT and final owned cleanup remain required. This matrix is a verification request, not PR readiness or issue completion.

Live Enable HTTP-through-Warehouse action remains **pending Claude**: this owned container already has HTTP enabled by the recorded original explicit Foundation action, so the action is correctly hidden. No replay, flag reset, settings fixture, skip or UI completion waiver is claimed. Stock Microsoft Users title remains English under1039 in this W1 image; own Warehouse controls/actions were checked in Icelandic.
