namespace Origo.Bifrost.Warehouse;

using Origo.Bifrost;

/// <summary>
/// Extends Foundation full permissions with Warehouse message-type execution rights.
/// </summary>
permissionsetextension 10078395 "BIFROST Whse - Full ori" extends "BIFROST Full ori"
{
    Permissions =
        codeunit "Warehouse Install ori" = X,
        codeunit "Warehouse Upgrade ori" = X,
        codeunit "Whse BinContent Get Impl ori" = X,
        codeunit "Whse Activity Get Impl ori" = X,
        codeunit "Whse Shipment Create Impl ori" = X,
        codeunit "Whse Shipment Post Impl ori" = X,
        codeunit "Whse Ship. Prev. Post Impl ori" = X,
        codeunit "Whse Receipt Create Impl ori" = X,
        codeunit "Whse Receipt Post Impl ori" = X,
        codeunit "Whse Rcpt Post Prev. Impl ori" = X,
        codeunit "Whse Pick Create Impl ori" = X,
        codeunit "Whse Pick Create Process ori" = X,
        codeunit "Whse Pick Register Impl ori" = X,
        codeunit "Whse Putaway Create Impl ori" = X,
        codeunit "Whse Putaway Create Proc. ori" = X,
        codeunit "Whse Putaway Register Impl ori" = X,
        codeunit "Whse Bin Get Impl ori" = X,
        codeunit "Whse Bin Create Impl ori" = X,
        codeunit "Whse DefaultBin Set Impl ori" = X,
        codeunit "Whse Write Context ori" = X,
        codeunit "Whse Movement Create Impl ori" = X,
        codeunit "Whse Movement Reg Impl ori" = X,
        codeunit "Whse InvtPick Create Impl ori" = X,
        codeunit "Whse InvtPick Post Impl ori" = X,
        codeunit "Whse InvtPut Create Impl ori" = X,
        codeunit "Whse InvtPut Post Impl ori" = X,
        codeunit "Whse InvtMove Create Impl ori" = X,
        codeunit "Whse InvtMove Reg Impl ori" = X,
        codeunit "Whse Bin Repl Calc Impl ori" = X,
        codeunit "Whse Data Restrict ori" = X;
}