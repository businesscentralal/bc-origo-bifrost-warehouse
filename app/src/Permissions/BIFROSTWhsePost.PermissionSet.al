namespace Origo.Bifrost.Warehouse;

/// <summary>
/// Grants Bifrost Warehouse posting.
/// Assign explicitly. Not included in BIFROST Whse - Read ori or BIFROST Whse - Full ori.
/// Does not grant invoicing. Warehouse.Shipment.Post with invoice = true also needs BIFROST WhseInv ori.
/// </summary>
permissionset 10078454 "BIFROST WhsePost ori"
{
    Assignable = true;
    Caption = 'Warehouse Posting Gate', MaxLength = 30, Comment = 'is-IS=Bókunarhlið vörugeymslu';

    Permissions =
        tabledata "Whse Posting ori" = RIMD;
}
