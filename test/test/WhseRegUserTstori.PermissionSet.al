namespace Origo.Bifrost.Warehouse.Test;

using Microsoft.Warehouse.Activity.History;
using Microsoft.Warehouse.History;
using Microsoft.Warehouse.Journal;
using Microsoft.Warehouse.InventoryDocument;
using Microsoft.Warehouse.Ledger;
using Microsoft.Warehouse.Structure;
using Microsoft.Warehouse.Tracking;
using System.Security.AccessControl;

/// <summary>
/// A Business Central warehouse user for the #70 register tests: Business Central's warehouse edit set and read access.
/// The registered movement headers and lines are read directly and inserted only through Business Central's register
/// codeunit (indirect), so the caller has no direct write on them. The other tables the register codeunits write
/// are granted indirectly, as their Permissions properties expect. Used with BIFROST Full ori, Whse Gate Test ori and
/// BIFROST WhsePost ori.
/// </summary>
permissionset 97064 "Whse RegUser Tst ori"
{
    Assignable = true;
    Caption = 'Whse Register User Test', MaxLength = 30;
    IncludedPermissionSets = "D365 WHSE, EDIT", "D365 READ";

    Permissions =
        tabledata "Registered Whse. Activity Hdr." = Ri,
        tabledata "Registered Whse. Activity Line" = Ri,
        tabledata "Registered Invt. Movement Hdr." = Ri,
        tabledata "Registered Invt. Movement Line" = Ri,
        tabledata "Warehouse Entry" = Rimd,
        tabledata "Warehouse Register" = Rimd,
        tabledata "Warehouse Journal Batch" = Rimd,
        tabledata "Posted Whse. Receipt Header" = Rm,
        tabledata "Posted Whse. Receipt Line" = Rm,
        tabledata Bin = Rm,
        tabledata "Bin Content" = RIMD,
        tabledata "Whse. Item Tracking Line" = RIMD;
}
