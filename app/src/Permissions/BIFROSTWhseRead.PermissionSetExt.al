namespace Origo.Bifrost.Warehouse;

using Origo.Bifrost;

/// <summary>
/// Extends Foundation read permissions with Warehouse message-type execution rights.
/// </summary>
permissionsetextension 10078394 "BIFROST Whse - Read ori" extends "BIFROST Read ori"
{
    Permissions =
        codeunit "Warehouse Install ori" = X,
        codeunit "Warehouse Upgrade ori" = X,
        codeunit "Whse BinContent Get Impl ori" = X,
        codeunit "Whse BinContent Get Help ori" = X,
        codeunit "Whse Activity Get Impl ori" = X,
        codeunit "Whse Activity Get Help ori" = X,
        codeunit "Whse Shipment Create Impl ori" = X,
        codeunit "Whse Shipment Create Help ori" = X,
        codeunit "Whse Shipment Post Impl ori" = X,
        codeunit "Whse Shipment Post Help ori" = X,
        codeunit "Whse Ship. Prev. Post Impl ori" = X,
        codeunit "Whse Ship. Prev. Post Help ori" = X,
        codeunit "Whse Receipt Create Impl ori" = X,
        codeunit "Whse Receipt Create Help ori" = X,
        codeunit "Whse Receipt Post Impl ori" = X,
        codeunit "Whse Receipt Post Help ori" = X,
        codeunit "Whse Rcpt Post Prev. Impl ori" = X,
        codeunit "Whse Rcpt Post Prev. Help ori" = X,
        codeunit "Whse Pick Create Impl ori" = X,
        codeunit "Whse Pick Create Process ori" = X,
        codeunit "Whse Pick Create Help ori" = X,
        codeunit "Whse Pick Register Impl ori" = X,
        codeunit "Whse Pick Register Help ori" = X,
        codeunit "Whse Putaway Create Impl ori" = X,
        codeunit "Whse Putaway Create Proc. ori" = X,
        codeunit "Whse Putaway Create Help ori" = X,
        codeunit "Whse Putaway Register Impl ori" = X,
        codeunit "Whse Putaway Register Help ori" = X,
        codeunit "Whse Data Restrict ori" = X;
}