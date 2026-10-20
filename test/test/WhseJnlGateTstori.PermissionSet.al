namespace Origo.Bifrost.Warehouse.Test;

using Microsoft.Warehouse.Journal;
using Microsoft.Warehouse.Ledger;
using Origo.Bifrost;
using Origo.Bifrost.Warehouse;
using System.Environment;
using System.Environment.Configuration;

/// <summary>
/// Journal and argument permissions for the posting-gate tests of Warehouse.Journal.Register and
/// Warehouse.PhysInventory.Register. Does not grant Whse Posting ori, so the gate refuses.
/// </summary>
permissionset 97063 "Whse JnlGate Tst ori"
{
    Assignable = true;
    Caption = 'Whse Jnl Gate Test', MaxLength = 30;

    Permissions =
        tabledata Company = r,
        tabledata "NAV App Setting" = r,
        tabledata "Message Argument ori" = RIMD,
        tabledata "Warehouse Journal Line" = RIMD,
        tabledata "Warehouse Entry" = R,
        tabledata "Warehouse Register" = R,
        codeunit "Whse Posting Gate ori" = X,
        codeunit "Whse Journal Reg Impl ori" = X,
        codeunit "Whse PhysInvt Reg Impl ori" = X,
        codeunit "Whse Journal Helper ori" = X,
        codeunit "Whse Msg Values ori" = X,
        codeunit "Whse Write Context ori" = X;
}
