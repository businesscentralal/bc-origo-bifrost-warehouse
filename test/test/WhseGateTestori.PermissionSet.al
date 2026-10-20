namespace Origo.Bifrost.Warehouse.Test;

using Microsoft.Warehouse.Activity;
using Microsoft.Warehouse.Activity.History;
using Microsoft.Warehouse.Document;
using Microsoft.Warehouse.InventoryDocument;
using Origo.Bifrost;
using Origo.Bifrost.Warehouse;
using System.Environment;
using System.Environment.Configuration;

/// <summary>
/// Document and argument permissions for the warehouse posting-gate tests.
/// Does not grant Whse Posting ori or Whse Invoice ori. Those sets are added only on the grant path.
/// The registered and posted headers are read only: Business Central's register and post codeunits write them (#70).
/// Grants indirect read on NAV App Setting for HTTP readiness; never settings-write permission.
/// Grants indirect read on Company. Dispatcher.Execute calls Foundation Eula Consent ori, which reads Company to build the consent key.
/// </summary>
permissionset 97025 "Whse Gate Test ori"
{
    Assignable = true;
    Caption = 'Whse Gate Test', MaxLength = 30;

    Permissions =
        tabledata Company = r,
        tabledata "NAV App Setting" = r,
        tabledata "Message Argument ori" = RIMD,
        tabledata "Warehouse Shipment Header" = RIMD,
        tabledata "Warehouse Receipt Header" = RIMD,
        tabledata "Warehouse Activity Header" = RIMD,
        tabledata "Warehouse Activity Line" = RIMD,
        tabledata "Registered Whse. Activity Hdr." = R,
        tabledata "Registered Invt. Movement Hdr." = R,
        tabledata "Posted Invt. Pick Header" = R,
        tabledata "Posted Invt. Put-away Header" = R,
        codeunit "Whse Posting Gate ori" = X,
        codeunit "Whse Shipment Post Impl ori" = X,
        codeunit "Whse Receipt Post Impl ori" = X,
        codeunit "Whse Pick Register Impl ori" = X,
        codeunit "Whse Putaway Register Impl ori" = X,
        codeunit "Whse Ship. Prev. Post Impl ori" = X,
        codeunit "Whse Rcpt Post Prev. Impl ori" = X,
        codeunit "Whse Movement Reg Impl ori" = X,
        codeunit "Whse InvtPick Post Impl ori" = X,
        codeunit "Whse InvtPut Post Impl ori" = X,
        codeunit "Whse InvtMove Reg Impl ori" = X,
        codeunit "Whse Write Context ori" = X;
}
