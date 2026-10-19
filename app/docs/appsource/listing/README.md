# AppSource offer: Bifrost Warehouse

Everything to enter in Partner Center for this offer, page by page, as Microsoft's offer pages ask
for it (Business Central offer). Built from the app's main branch and the documentation. No message
type names, as on the public site. Review before publishing.

## Files in this folder

| File | Use | Partner Center page | State |
|---|---|---|---|
| `logo-216.png` | Large logo, 216 × 216 PNG, scaled from the app logo `app/assets/Logo250x250.png` | Offer listing › Logos | New |
| `screenshots/*.png` | Screenshots, 1280 × 720 PNG (3 to 5 required) | Offer listing › Screenshots | **Missing** - none taken yet, see [screenshots/README.md](screenshots/README.md) |
| `description.html` | Description with the allowed HTML tags | Offer listing › Description | New, whole app |
| `description.md` | The same as plain text | (for review) | New, whole app |
| `product-sheet.pdf` | One-page marketing sheet (1 to 3 PDFs required) | Offer listing › Supporting documents | **Missing** |

## 1. Offer setup

| Field | Value |
|---|---|
| Offer alias | Bifrost Warehouse |
| Customer leads / listing option | Same as Bifrost Foundation |

## 2. Properties

| Field | Value | Subcategories |
|---|---|---|
| Primary category | Operations & Supply Chain | Inventory Management; Information Management & Connectivity |
| Secondary category | Commerce | Product Information & Content Management |
| Industry | Distribution | — |
| Industry | Retail & Consumer Goods | Retailers |
| App version | The version of the `.app` you upload (the pipeline sets it) | |
| Terms and conditions (URL) | https://docs.bifrost.origo.is/en-us/licensing/eula/ | |

Check the subcategory names against the current Partner Center list before entering them.

## 3. Offer listing

| Field | Value | Length / limit |
|---|---|---|
| Name | Bifrost Warehouse | 17 / 200 |
| Search results summary | Run receipts, put-aways, picks and shipments in Business Central from other systems. | 84 / 100 |
| Description | `description.html` | about 2,200 / 5,000 |
| Search keywords | Warehouse, Warehouse integration, Scanner | 3 / 3 |
| Products your app works with | Dynamics 365 Business Central | 1 / 3 |
| Help link | https://docs.bifrost.origo.is/en-us/warehouse/ | must differ from Support URL |
| Privacy policy link | https://docs.bifrost.origo.is/en-us/licensing/privacy/ | |
| Support contact (name, e-mail, phone, URL) | Same as Bifrost Foundation; Support URL https://www.origo.is/ | not shown to customers |
| Engineering contact | Same as Bifrost Foundation | not shown to customers |
| Supporting documents | `product-sheet.pdf` (to be made) | 1 to 3 PDFs |
| Logo | `logo-216.png` | PNG |
| Screenshots | see [screenshots/README.md](screenshots/README.md) | 3 to 5, 1280 × 720 PNG |
| Videos | optional; none yet | up to 4 |

Links use the documentation's own domain, docs.bifrost.origo.is, the same addresses as the app's
`app.json`. The Warehouse pages on the site are added on branch `docs/publish-warehouse` in
businesscentralal/bifrost; check that they are live before submitting.

Microsoft's logo guidance says no text on the logo; Bifrost Foundation's logo has text, so this one
follows Foundation for a consistent family.

### Screenshots and captions

The app has no pages of its own, so the screenshots show standard Business Central warehouse pages
after a connected system has done the work. None are taken yet; the list and the capture rules are
in [screenshots/README.md](screenshots/README.md).

## 4. Availability

Markets: the same as Bifrost Foundation. The fourteen countries declared in `app/AppSourceCop.json`
are in [`../partner-center-markets.csv`](../partner-center-markets.csv).

## 5. Technical configuration

Upload the app's `.app` file from the release build. Dependency: Bifrost Foundation 28.0.3.530 or
later.

## 6. Supplemental content

| Field | Value |
|---|---|
| Supported editions | Essentials and Premium |
| Key usage scenario, test accounts, test app | No longer used in validation (Microsoft); leave empty unless Partner Center requires it |

---
Drafted with the help of Claude (Anthropic); review before publishing. Origo's AI policy (STE-0002):
the person who publishes is responsible for the content.
