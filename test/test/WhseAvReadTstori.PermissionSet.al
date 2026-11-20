namespace Origo.Bifrost.Warehouse.Test;

using Microsoft.Inventory.Item;
using Microsoft.Inventory.Item.Catalog;
using Microsoft.Inventory.Ledger;
using Microsoft.Inventory.Location;
using Microsoft.Inventory.Tracking;
using Microsoft.Warehouse.Activity;
using Microsoft.Warehouse.Document;
using Microsoft.Warehouse.Ledger;
using Microsoft.Warehouse.Structure;
using Microsoft.Warehouse.Tracking;

/// <summary>
/// Plain read access to the warehouse and item tables a reader needs next to BIFROST Read ori. No SUPER and no write access.
/// </summary>
permissionset 97007 "Whse AvRead Tst ori"
{
    Assignable = true;
    Caption = 'Whse Avail Read Test', MaxLength = 30;

    Permissions =
        tabledata "Bin Content" = R,
        tabledata "Bin" = R,
        tabledata "Bin Type" = R,
        tabledata "Zone" = R,
        tabledata "Warehouse Entry" = R,
        tabledata "Warehouse Activity Line" = R,
        tabledata "Whse. Item Tracking Line" = R,
        tabledata "Reservation Entry" = R,
        tabledata "Item Ledger Entry" = R,
        tabledata "Location" = R,
        tabledata "Item" = R,
        tabledata "Item Variant" = R,
        tabledata "Item Unit of Measure" = R,
        tabledata "Item Tracking Code" = R,
        tabledata "Lot No. Information" = R,
        tabledata "Serial No. Information" = R,
        tabledata "Package No. Information" = R,
        tabledata "Warehouse Shipment Line" = r,
        tabledata "Warehouse Receipt Line" = r,
        tabledata "Warehouse Activity Header" = r;
}
