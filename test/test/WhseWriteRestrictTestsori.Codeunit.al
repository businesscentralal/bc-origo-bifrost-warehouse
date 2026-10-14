namespace Origo.Bifrost.Warehouse.Test;

using Microsoft.Inventory.Item;
using Microsoft.Warehouse.Activity;
using Microsoft.Warehouse.Document;
using Origo.Bifrost;
using System.TestLibraries.Utilities;

/// <summary>
/// Proves generic data-record writes are refused for warehouse document tables, reads stay allowed, and other tables are left open.
/// </summary>
codeunit 97026 "Whse Write Restrict Tests ori"
{
    Subtype = Test;
    TestPermissions = Disabled;

    /// <summary>Generic writes to the warehouse document tables owned by this app are refused.</summary>
    [Test]
    procedure GenericWrite_WarehouseDocumentTables_IsRefused()
    var
        TempArgument: Record "Message Argument ori";
        Assert: Codeunit "Library Assert";
    begin
        TempArgument.Init();
        TempArgument.Insert(true);

        Assert.IsTrue(TempArgument.IsTableWriteRestrictedForDataRecords(Database::"Warehouse Shipment Header", false), 'Warehouse Shipment Header');
        Assert.IsTrue(TempArgument.IsTableWriteRestrictedForDataRecords(Database::"Warehouse Shipment Line", false), 'Warehouse Shipment Line');
        Assert.IsTrue(TempArgument.IsTableWriteRestrictedForDataRecords(Database::"Warehouse Receipt Header", false), 'Warehouse Receipt Header');
        Assert.IsTrue(TempArgument.IsTableWriteRestrictedForDataRecords(Database::"Warehouse Receipt Line", false), 'Warehouse Receipt Line');
        Assert.IsTrue(TempArgument.IsTableWriteRestrictedForDataRecords(Database::"Warehouse Activity Header", false), 'Warehouse Activity Header');
        Assert.IsTrue(TempArgument.IsTableWriteRestrictedForDataRecords(Database::"Warehouse Activity Line", false), 'Warehouse Activity Line');
    end;

    /// <summary>A table outside the warehouse document set is not write-restricted by this subscriber.</summary>
    [Test]
    procedure GenericWrite_NonWarehouseTable_IsNotRestricted()
    var
        TempArgument: Record "Message Argument ori";
        Assert: Codeunit "Library Assert";
    begin
        TempArgument.Init();
        TempArgument.Insert(true);

        Assert.IsFalse(TempArgument.IsTableWriteRestrictedForDataRecords(Database::Item, false), 'Item must not be restricted by the warehouse subscriber.');
    end;

    /// <summary>Generic reads of the warehouse document tables stay allowed.</summary>
    [Test]
    procedure GenericRead_WarehouseDocumentTables_StaysAllowed()
    var
        TempArgument: Record "Message Argument ori";
        Assert: Codeunit "Library Assert";
    begin
        TempArgument.Init();
        TempArgument.Insert(true);

        Assert.IsFalse(TempArgument.IsTableReadRestrictedForDataRecords(Database::"Warehouse Shipment Header"), 'Warehouse Shipment Header');
        Assert.IsFalse(TempArgument.IsTableReadRestrictedForDataRecords(Database::"Warehouse Shipment Line"), 'Warehouse Shipment Line');
        Assert.IsFalse(TempArgument.IsTableReadRestrictedForDataRecords(Database::"Warehouse Receipt Header"), 'Warehouse Receipt Header');
        Assert.IsFalse(TempArgument.IsTableReadRestrictedForDataRecords(Database::"Warehouse Receipt Line"), 'Warehouse Receipt Line');
        Assert.IsFalse(TempArgument.IsTableReadRestrictedForDataRecords(Database::"Warehouse Activity Header"), 'Warehouse Activity Header');
        Assert.IsFalse(TempArgument.IsTableReadRestrictedForDataRecords(Database::"Warehouse Activity Line"), 'Warehouse Activity Line');
    end;
}
