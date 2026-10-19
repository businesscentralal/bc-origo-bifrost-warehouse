namespace Origo.Bifrost.Warehouse.Test;

using Origo.Bifrost.Warehouse;

/// <summary>
/// Restrictive permission set that can run the warehouse Get implementations without table read permission.
/// </summary>
permissionset 97010 "Whse NoRead Test ori"
{
    Assignable = true;
    Caption = 'Whse Test No Read', MaxLength = 30;

    Permissions =
        codeunit "Whse Activity Get Impl ori" = X,
        codeunit "Whse BinContent Get Impl ori" = X,
        codeunit "Whse Bin Get Impl ori" = X,
        codeunit "Whse Bin Create Impl ori" = X,
        codeunit "Whse DefaultBin Set Impl ori" = X,
        codeunit "Whse Bin Repl Calc Impl ori" = X,
        codeunit "Whse Movement Create Impl ori" = X,
        codeunit "Whse Movement Reg Impl ori" = X,
        codeunit "Whse InvtPick Create Impl ori" = X,
        codeunit "Whse InvtPick Post Impl ori" = X,
        codeunit "Whse InvtPut Create Impl ori" = X,
        codeunit "Whse InvtPut Post Impl ori" = X,
        codeunit "Whse Pick Create Impl ori" = X,
        codeunit "Whse Putaway Create Impl ori" = X,
        codeunit "Whse Receipt Create Impl ori" = X,
        codeunit "Whse Receipt Post Impl ori" = X,
        codeunit "Whse Shipment Create Impl ori" = X,
        codeunit "Whse Shipment Post Impl ori" = X,
        codeunit "Whse Write Context ori" = X,
        codeunit "Whse Msg Values ori" = X,
        codeunit "Whse Journal Helper ori" = X,
        codeunit "Whse Journal Create Impl ori" = X,
        codeunit "Whse Journal Reg Impl ori" = X,
        codeunit "Whse PhysInvt Calc Impl ori" = X,
        codeunit "Whse PhysInvt Reg Impl ori" = X,
        codeunit "Whse Adjustment Calc Impl ori" = X,
        codeunit "Whse Worksheet Helper ori" = X,
        codeunit "Whse Wksh GetDocs Impl ori" = X,
        codeunit "Whse Wksh CreateAct Impl ori" = X,
        codeunit "Whse ActLine Helper ori" = X,
        codeunit "Whse ActLine Split Impl ori" = X,
        codeunit "Whse ActLine ChgBin Impl ori" = X,
        codeunit "Whse ActLine SetQty Impl ori" = X,
        codeunit "Whse ActLine Track Impl ori" = X;
}
