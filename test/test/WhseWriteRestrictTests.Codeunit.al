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
        Argument: Record "Message Argument ori";
        Assert: Codeunit "Library Assert";
    begin
        Argument.Init();
        Argument.Insert(true);

        Assert.IsTrue(Argument.IsTableWriteRestrictedForDataRecords(Database::"Warehouse Shipment Header"), 'Warehouse Shipment Header');
        Assert.IsTrue(Argument.IsTableWriteRestrictedForDataRecords(Database::"Warehouse Shipment Line"), 'Warehouse Shipment Line');
        Assert.IsTrue(Argument.IsTableWriteRestrictedForDataRecords(Database::"Warehouse Receipt Header"), 'Warehouse Receipt Header');
        Assert.IsTrue(Argument.IsTableWriteRestrictedForDataRecords(Database::"Warehouse Receipt Line"), 'Warehouse Receipt Line');
        Assert.IsTrue(Argument.IsTableWriteRestrictedForDataRecords(Database::"Warehouse Activity Header"), 'Warehouse Activity Header');
        Assert.IsTrue(Argument.IsTableWriteRestrictedForDataRecords(Database::"Warehouse Activity Line"), 'Warehouse Activity Line');
    end;

    /// <summary>A table outside the warehouse document set is not write-restricted by this subscriber.</summary>
    [Test]
    procedure GenericWrite_NonWarehouseTable_IsNotRestricted()
    var
        Argument: Record "Message Argument ori";
        Assert: Codeunit "Library Assert";
    begin
        Argument.Init();
        Argument.Insert(true);

        Assert.IsFalse(Argument.IsTableWriteRestrictedForDataRecords(Database::Item), 'Item must not be restricted by the warehouse subscriber.');
    end;

    /// <summary>Generic reads of the warehouse document tables stay allowed.</summary>
    [Test]
    procedure GenericRead_WarehouseDocumentTables_StaysAllowed()
    var
        Argument: Record "Message Argument ori";
        Assert: Codeunit "Library Assert";
    begin
        Argument.Init();
        Argument.Insert(true);

        Assert.IsFalse(Argument.IsTableReadRestrictedForDataRecords(Database::"Warehouse Shipment Header"), 'Warehouse Shipment Header');
        Assert.IsFalse(Argument.IsTableReadRestrictedForDataRecords(Database::"Warehouse Shipment Line"), 'Warehouse Shipment Line');
        Assert.IsFalse(Argument.IsTableReadRestrictedForDataRecords(Database::"Warehouse Receipt Header"), 'Warehouse Receipt Header');
        Assert.IsFalse(Argument.IsTableReadRestrictedForDataRecords(Database::"Warehouse Receipt Line"), 'Warehouse Receipt Line');
        Assert.IsFalse(Argument.IsTableReadRestrictedForDataRecords(Database::"Warehouse Activity Header"), 'Warehouse Activity Header');
        Assert.IsFalse(Argument.IsTableReadRestrictedForDataRecords(Database::"Warehouse Activity Line"), 'Warehouse Activity Line');
    end;
}
