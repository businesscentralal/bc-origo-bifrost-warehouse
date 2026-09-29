namespace Origo.Bifrost.Warehouse;

/// <summary>
/// Grants invoicing through Warehouse.Shipment.Post.
/// Assign explicitly. Not included in BIFROST Whse - Read ori or BIFROST Whse - Full ori.
/// This is the app-owned replacement for Foundation's G/L posting gate on the invoice path.
/// The name is BIFROST WhseInv ori because an assignable permission set name is limited to 20 characters.
/// </summary>
permissionset 10078457 "BIFROST WhseInv ori"
{
    Assignable = true;
    Caption = 'Whse Invoice Gate', MaxLength = 30, Comment = 'is-IS=Reikningshlið vörugeymslu';

    Permissions =
        tabledata "Whse Invoice ori" = RIMD;
}
