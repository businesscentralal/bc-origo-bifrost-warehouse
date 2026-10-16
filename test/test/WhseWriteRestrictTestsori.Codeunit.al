namespace Origo.Bifrost.Warehouse.Test;

using Microsoft.Inventory.Item;
using Microsoft.Warehouse.Activity;
using Microsoft.Warehouse.Document;
using Microsoft.Warehouse.Structure;
using Microsoft.Warehouse.Worksheet;
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

    /// <summary>Bin writes are refused, including a forced call, and the hint names the bin message types.</summary>
    [Test]
    procedure GenericWrite_Bin_IsRefusedAndHinted()
    var
        TempArgument: Record "Message Argument ori";
        Assert: Codeunit "Library Assert";
    begin
        TempArgument.Init();
        TempArgument.Insert(true);

        Assert.IsTrue(TempArgument.IsTableWriteRestrictedForDataRecords(Database::Bin, false), 'Bin must be write-restricted.');
        Assert.IsTrue(TempArgument.IsTableWriteRestrictedForDataRecords(Database::Bin, true), 'Force must not reopen Bin.');
        Assert.IsFalse(TempArgument.IsTableReadRestrictedForDataRecords(Database::Bin), 'Bin reads stay allowed.');
        Assert.AreEqual('Warehouse.Bin.Create, Warehouse.Bin.Get', TempArgument.GetDedicatedMessageTypeHintForWrite(Database::Bin), 'Bin write hint.');
        AssertGenericSetRefused('Bin', '{"tableName":"Bin","force":true,"data":[{"primaryKey":{"Location Code":"LOC","Code":"A-01"},"fields":{"Description":"Nope"}}]}', 'Warehouse.Bin.Create, Warehouse.Bin.Get');
    end;

    /// <summary>A generic write of Bin Content Default is refused, including force, and the hint names Warehouse.DefaultBin.Set.</summary>
    [Test]
    procedure GenericWrite_BinContentDefault_IsRefusedAndHinted()
    var
        BinContent: Record "Bin Content";
        TempArgument: Record "Message Argument ori";
        Assert: Codeunit "Library Assert";
    begin
        TempArgument.Init();
        TempArgument.Insert(true);

        Assert.AreEqual('Warehouse.DefaultBin.Set', TempArgument.GetDedicatedMessageTypeHintForField(Database::"Bin Content", BinContent.FieldNo(Default)), 'Default field hint.');
        AssertGenericSetRefused('Bin Content', '{"tableName":"Bin Content","force":true,"data":[{"primaryKey":{"Location Code":"LOC","Bin Code":"A-01","Item No.":"ITEM","Variant Code":"","Unit of Measure Code":"PCS"},"fields":{"Default":true}}]}', 'Warehouse.DefaultBin.Set');
    end;

    /// <summary>Movement worksheet quantity and bin fields point at Warehouse.Movement.Create.</summary>
    [Test]
    procedure GenericWrite_MovementWorksheetFields_IsRefusedAndHinted()
    var
        WorksheetLine: Record "Whse. Worksheet Line";
        TempArgument: Record "Message Argument ori";
        Assert: Codeunit "Library Assert";
    begin
        TempArgument.Init();
        TempArgument.Insert(true);

        Assert.AreEqual('Warehouse.Movement.Create', TempArgument.GetDedicatedMessageTypeHintForField(Database::"Whse. Worksheet Line", WorksheetLine.FieldNo("From Bin Code")), 'From Bin Code hint.');
        Assert.AreEqual('Warehouse.Movement.Create', TempArgument.GetDedicatedMessageTypeHintForField(Database::"Whse. Worksheet Line", WorksheetLine.FieldNo("To Bin Code")), 'To Bin Code hint.');
        Assert.AreEqual('Warehouse.Movement.Create', TempArgument.GetDedicatedMessageTypeHintForField(Database::"Whse. Worksheet Line", WorksheetLine.FieldNo("Qty. to Handle")), 'Qty. to Handle hint.');
        AssertGenericSetRefused('Whse. Worksheet Line', '{"tableName":"Whse. Worksheet Line","force":true,"data":[{"primaryKey":{"Worksheet Template Name":"MOVE","Name":"DEFAULT","Location Code":"LOC","Line No.":10000},"fields":{"From Bin Code":"A-01"}}]}', 'Warehouse.Movement.Create');
    end;

    /// <summary>Activity quantity and bin point at movement and inventory pick. Zone stays on movement. Lot and serial point at inventory pick.</summary>
    [Test]
    procedure GenericWrite_MovementActivityFields_IsHinted()
    var
        ActivityLine: Record "Warehouse Activity Line";
        TempArgument: Record "Message Argument ori";
        Assert: Codeunit "Library Assert";
    begin
        TempArgument.Init();
        TempArgument.Insert(true);

        Assert.AreEqual('Warehouse.Movement.Register, Warehouse.InventoryPick.Create, Warehouse.InventoryPick.Post, Warehouse.InventoryPutAway.Create, Warehouse.InventoryPutAway.Post', TempArgument.GetDedicatedMessageTypeHintForField(Database::"Warehouse Activity Line", ActivityLine.FieldNo("Qty. to Handle")), 'Qty. to Handle hint.');
        Assert.AreEqual('Warehouse.Movement.Register, Warehouse.InventoryPick.Create, Warehouse.InventoryPick.Post, Warehouse.InventoryPutAway.Create, Warehouse.InventoryPutAway.Post', TempArgument.GetDedicatedMessageTypeHintForField(Database::"Warehouse Activity Line", ActivityLine.FieldNo("Bin Code")), 'Bin Code hint.');
        Assert.AreEqual('Warehouse.Movement.Register', TempArgument.GetDedicatedMessageTypeHintForField(Database::"Warehouse Activity Line", ActivityLine.FieldNo("Zone Code")), 'Zone Code hint.');
        Assert.AreEqual('Warehouse.InventoryPick.Create, Warehouse.InventoryPick.Post, Warehouse.InventoryPutAway.Create, Warehouse.InventoryPutAway.Post', TempArgument.GetDedicatedMessageTypeHintForField(Database::"Warehouse Activity Line", ActivityLine.FieldNo("Lot No.")), 'Lot No. hint.');
        Assert.AreEqual('Warehouse.InventoryPick.Create, Warehouse.InventoryPick.Post, Warehouse.InventoryPutAway.Create, Warehouse.InventoryPutAway.Post', TempArgument.GetDedicatedMessageTypeHintForField(Database::"Warehouse Activity Line", ActivityLine.FieldNo("Serial No.")), 'Serial No. hint.');
        Assert.AreEqual('Warehouse.InventoryPutAway.Create, Warehouse.InventoryPutAway.Post', TempArgument.GetDedicatedMessageTypeHintForField(Database::"Warehouse Activity Line", ActivityLine.FieldNo("Expiration Date")), 'Expiration Date hint.');
        Assert.AreEqual('Warehouse.Pick.Register, Warehouse.Putaway.Register, Warehouse.Movement.Register, Warehouse.InventoryPick.Create, Warehouse.InventoryPick.Post, Warehouse.InventoryPutAway.Create, Warehouse.InventoryPutAway.Post', TempArgument.GetDedicatedMessageTypeHintForWrite(Database::"Warehouse Activity Line"), 'Activity line write hint.');
        Assert.IsTrue(TempArgument.IsTableWriteRestrictedForDataRecords(Database::"Warehouse Activity Line", true), 'The activity line table stays closed, including force.');
        AssertGenericSetRefused('Warehouse Activity Line', '{"tableName":"Warehouse Activity Line","force":true,"data":[{"primaryKey":{"Activity Type":"Invt. Put-away","No.":"IPU","Line No.":10000},"fields":{"Expiration Date":"2026-10-16"}}]}', 'Warehouse.Pick.Register, Warehouse.Putaway.Register, Warehouse.Movement.Register, Warehouse.InventoryPick.Create, Warehouse.InventoryPick.Post, Warehouse.InventoryPutAway.Create, Warehouse.InventoryPutAway.Post');
    end;

    local procedure AssertGenericSetRefused(Subject: Text; RequestText: Text; ExpectedHint: Text)
    var
        Helper: Codeunit "Whse Receipt Test Helper ori";
        Assert: Codeunit "Library Assert";
        ResponseJson: JsonObject;
        ResponseText: Text;
    begin
        Assert.IsTrue(Helper.RunMessage(Enum::"Message Type ori"::"Data.Records.Set", Subject, RequestText, ResponseJson), 'Data.Records.Set should return JSON.');
        ResponseJson.WriteTo(ResponseText);
        Assert.AreEqual('Error', TextValue(ResponseJson, 'status'), ResponseText);
        Assert.AreEqual('PermissionDenied', TextValue(ResponseJson, 'code'), ResponseText);
        Assert.AreEqual(ExpectedHint, TextValue(ResponseJson, 'nextStep'), ResponseText);
    end;

    local procedure TextValue(Parent: JsonObject; Name: Text): Text
    var
        Token: JsonToken;
    begin
        if not Parent.Get(Name, Token) then
            exit('');
        if not Token.IsValue() then
            exit('');
        exit(Token.AsValue().AsText());
    end;
}
