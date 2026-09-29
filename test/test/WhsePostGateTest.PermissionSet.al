namespace Origo.Bifrost.Warehouse.Test;

using Microsoft.Warehouse.Activity;
using Microsoft.Warehouse.Document;
using Origo.Bifrost;
using Origo.Bifrost.Warehouse;

/// <summary>
/// Document and argument permissions for the warehouse posting-gate tests.
/// Does not grant Whse Posting ori or Whse Invoice ori. Those sets are added only on the grant path.
/// </summary>
permissionset 97025 "Whse Gate Test ori"
{
    Assignable = true;
    Caption = 'Whse Gate Test', MaxLength = 30;

    Permissions =
        tabledata "Message Argument ori" = RIMD,
        tabledata "Warehouse Shipment Header" = RIMD,
        tabledata "Warehouse Receipt Header" = RIMD,
        tabledata "Warehouse Activity Header" = RIMD,
        codeunit "Whse Posting Gate ori" = X,
        codeunit "Whse Shipment Post Impl ori" = X,
        codeunit "Whse Receipt Post Impl ori" = X,
        codeunit "Whse Pick Register Impl ori" = X,
        codeunit "Whse Putaway Register Impl ori" = X,
        codeunit "Whse Ship. Prev. Post Impl ori" = X,
        codeunit "Whse Rcpt Post Prev. Impl ori" = X;
}
