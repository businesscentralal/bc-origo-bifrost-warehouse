namespace Origo.Bifrost.Warehouse.Test;

using Microsoft.Inventory.Item;
using Microsoft.Inventory.Journal;
using Microsoft.Inventory.Ledger;
using Microsoft.Inventory.Location;
using Microsoft.Inventory.Setup;
using Microsoft.Warehouse.Activity;
using Microsoft.Warehouse.InternalDocument;
using Microsoft.Warehouse.Setup;
using Microsoft.Warehouse.Structure;
using Origo.Bifrost;
using Origo.Bifrost.Warehouse;
using System.TestLibraries.Utilities;

/// <summary>
/// Tests Warehouse.InventoryMovement.Create through the public dispatcher and the permission denial path.
/// </summary>
codeunit 97089 "Whse InvtMove Create Tests ori"
{
    Subtype = Test;
    TestPermissions = Disabled;

    var
        Assert: Codeunit "Library Assert";
        LibraryInventory: Codeunit "Library - Inventory";
        LibraryUtility: Codeunit "Library - Utility";
        LibraryWarehouse: Codeunit "Library - Warehouse";

    /// <summary>A basic bin location moves stock from one bin to another and returns the inventory movement.</summary>
    [Test]
    procedure Create_InlineLine_CreatesMovement()
    var
        Location: Record Location;
        Item: Record Item;
        FromBin: Record Bin;
        ToBin: Record Bin;
        ActivityHeader: Record "Warehouse Activity Header";
        ResponseJson: JsonObject;
    begin
        PrepareBasicStock(Location, Item, FromBin, ToBin, 5);

        Run(LineRequest(Location.Code, Item."No.", 1, FromBin.Code, ToBin.Code), '', ResponseJson);

        Assert.AreEqual('Success', TextValue(ResponseJson, 'status'), ResponseText(ResponseJson));
        Assert.AreEqual(Location.Code, TextValue(ResponseJson, 'locationCode'), 'The location should be returned.');
        Assert.AreEqual(1, IntegerValue(ResponseJson, 'lineCount'), 'One take and place pair should be counted.');
        Assert.IsTrue(ActivityHeader.Get(ActivityHeader.Type::"Invt. Movement", CopyStr(TextValue(ResponseJson, 'movementNo'), 1, MaxStrLen(ActivityHeader."No."))), 'The inventory movement should exist.');
        Assert.AreEqual(FromBin.Code, TextValue(FirstLine(ResponseJson), 'fromBin'), 'The from-bin should be returned.');
        Assert.AreEqual(ToBin.Code, TextValue(FirstLine(ResponseJson), 'toBin'), 'The to-bin should be returned.');
    end;

    /// <summary>A directed location is refused and writes nothing.</summary>
    [Test]
    procedure Create_DirectedLocation_IsRefused()
    var
        Location: Record Location;
        InternalHeader: Record "Internal Movement Header";
        ResponseJson: JsonObject;
    begin
        LibraryWarehouse.CreateFullWMSLocation(Location, 2);

        Run(LineRequest(Location.Code, 'ITEM', 1, 'A-01', 'B-01'), '', ResponseJson);

        Assert.AreEqual('PreconditionFailed', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));
        Assert.AreEqual('Use Warehouse.Movement.Create.', TextValue(ResponseJson, 'nextStep'), 'The next step should name Warehouse.Movement.Create.');
        InternalHeader.SetRange("Location Code", Location.Code);
        Assert.AreEqual(0, InternalHeader.Count(), 'A directed location must not get an internal movement.');
    end;

    /// <summary>A location without bins is refused and writes nothing.</summary>
    [Test]
    procedure Create_LocationWithoutBins_IsRefused()
    var
        Location: Record Location;
        InternalHeader: Record "Internal Movement Header";
        ResponseJson: JsonObject;
    begin
        LibraryWarehouse.CreateLocationWMS(Location, false, false, false, false, false);

        Run(LineRequest(Location.Code, 'ITEM', 1, 'A-01', 'B-01'), '', ResponseJson);

        Assert.AreEqual('PreconditionFailed', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));
        Assert.AreEqual('Moves between bins need Bin Mandatory on the location.', TextValue(ResponseJson, 'nextStep'), 'The next step should name Bin Mandatory.');
        InternalHeader.SetRange("Location Code", Location.Code);
        Assert.AreEqual(0, InternalHeader.Count(), 'A location without bins must not get an internal movement.');
    end;

    /// <summary>The same from-bin and to-bin is refused and writes nothing.</summary>
    [Test]
    procedure Create_SameBin_IsRefused()
    var
        Location: Record Location;
        Item: Record Item;
        FromBin: Record Bin;
        ToBin: Record Bin;
        InternalHeader: Record "Internal Movement Header";
        ResponseJson: JsonObject;
    begin
        PrepareBasicStock(Location, Item, FromBin, ToBin, 5);

        Run(LineRequest(Location.Code, Item."No.", 1, FromBin.Code, FromBin.Code), '', ResponseJson);

        Assert.AreEqual('InvalidLine', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));
        Assert.AreEqual('lines[0].toBin', TextValue(ResponseJson, 'parameter'), 'The error should name the line.');
        Assert.AreEqual('Send a toBin that is different from fromBin.', TextValue(ResponseJson, 'nextStep'), 'The next step should say the bins must differ.');
        InternalHeader.SetRange("Location Code", Location.Code);
        Assert.AreEqual(0, InternalHeader.Count(), 'The same bin must not write an internal movement.');
    end;

    /// <summary>More than the bin contains is refused and writes nothing.</summary>
    [Test]
    procedure Create_QuantityAboveBinContent_IsRefused()
    var
        Location: Record Location;
        Item: Record Item;
        FromBin: Record Bin;
        ToBin: Record Bin;
        InternalHeader: Record "Internal Movement Header";
        ResponseJson: JsonObject;
    begin
        PrepareBasicStock(Location, Item, FromBin, ToBin, 5);

        Run(LineRequest(Location.Code, Item."No.", 99, FromBin.Code, ToBin.Code), '', ResponseJson);

        Assert.AreEqual('InvalidLine', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));
        Assert.AreEqual('Read Warehouse.BinContent.Get and lower the quantity.', TextValue(ResponseJson, 'nextStep'), 'The next step should name BinContent.Get.');
        InternalHeader.SetRange("Location Code", Location.Code);
        Assert.AreEqual(0, InternalHeader.Count(), 'A short bin must not write an internal movement.');
    end;

    /// <summary>A request with neither lines nor a source document is refused.</summary>
    [Test]
    procedure Create_MissingChoice_IsRefused()
    var
        ResponseJson: JsonObject;
    begin
        Run('{}', '', ResponseJson);

        Assert.AreEqual('MissingParameter', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));
        Assert.AreEqual('lines', TextValue(ResponseJson, 'parameter'), 'The error should name lines.');
    end;

    /// <summary>An unknown key is refused and writes nothing.</summary>
    [Test]
    procedure Create_UnknownKey_IsRefused()
    var
        Location: Record Location;
        Item: Record Item;
        FromBin: Record Bin;
        ToBin: Record Bin;
        InternalHeader: Record "Internal Movement Header";
        ResponseJson: JsonObject;
    begin
        PrepareBasicStock(Location, Item, FromBin, ToBin, 5);

        Run('{"note":"nope",' + CopyStr(LineRequest(Location.Code, Item."No.", 1, FromBin.Code, ToBin.Code), 2), '', ResponseJson);

        Assert.AreEqual('UnknownParameter', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));
        Assert.AreEqual('note', TextValue(ResponseJson, 'parameter'), 'The error should name the unknown key.');
        InternalHeader.SetRange("Location Code", Location.Code);
        Assert.AreEqual(0, InternalHeader.Count(), 'An unknown key must not write an internal movement.');
    end;

    /// <summary>Create is disabled and returns PermissionDenied without write permission.</summary>
    [Test]
    [TestPermissions(TestPermissions::Restrictive)]
    procedure Create_WithoutPermission_ReturnsPermissionDenied()
    var
        TempArgument: Record "Message Argument ori";
        CreateImpl: Codeunit "Whse InvtMove Create Impl ori";
        LibraryLowerPermissions: Codeunit "Library - Lower Permissions";
        MessageTypeInterface: Interface "Msg Interface ori";
        ResponseJson: JsonObject;
    begin
        LibraryLowerPermissions.PushPermissionSetWithoutDefaults('Whse NoRead Test ori');
        LibraryLowerPermissions.AddPermissionSet('Whse Gate Test ori');
        MessageTypeInterface := Enum::"Message Type ori"::"Warehouse.InventoryMovement.Create";
        Assert.IsFalse(MessageTypeInterface.IsEnabled(), 'Create must be disabled without write permission.');

        TempArgument.Init();
        TempArgument.Version := "Message Version ori"::"1.0";
        TempArgument.Insert(true);
        CreateImpl.ExecuteBifrostTask(TempArgument);
        ResponseJson := TempArgument.GetResponseJson();
        Assert.AreEqual('PermissionDenied', TextValue(ResponseJson, 'code'), 'The denial must use PermissionDenied.');
        Assert.AreEqual('Ask an administrator to assign BIFROST Whse - Full ori.', TextValue(ResponseJson, 'nextStep'), 'The next step must name the full permission set.');
    end;

    local procedure PrepareBasicStock(var Location: Record Location; var Item: Record Item; var FromBin: Record Bin; var ToBin: Record Bin; Quantity: Decimal)
    begin
        EnsureInventoryMovementNos();
        LibraryWarehouse.CreateLocationWMS(Location, true, false, false, false, false);
        EnsureWarehouseEmployee(Location.Code);
        LibraryWarehouse.CreateBin(FromBin, Location.Code, 'FROM-01', '', '');
        LibraryWarehouse.CreateBin(ToBin, Location.Code, 'TO-01', '', '');
        LibraryInventory.CreateItem(Item);
        PostAdjustment(Item."No.", Location.Code, FromBin.Code, Quantity);
    end;

    local procedure EnsureInventoryMovementNos()
    var
        InventorySetup: Record "Inventory Setup";
        SeriesCode: Code[20];
    begin
        InventorySetup.Get();
        SeriesCode := LibraryUtility.GetGlobalNoSeriesCode();
        if InventorySetup."Internal Movement Nos." = '' then
            InventorySetup.Validate("Internal Movement Nos.", SeriesCode);
        if InventorySetup."Inventory Movement Nos." = '' then
            InventorySetup.Validate("Inventory Movement Nos.", SeriesCode);
        if InventorySetup."Registered Invt. Movement Nos." = '' then
            InventorySetup.Validate("Registered Invt. Movement Nos.", SeriesCode);
        InventorySetup.Modify(true);
    end;

    local procedure EnsureWarehouseEmployee(LocationCode: Code[10])
    var
        WarehouseEmployee: Record "Warehouse Employee";
        UserCode: Code[50];
    begin
        UserCode := CopyStr(UserId(), 1, MaxStrLen(UserCode));
        if UserCode = '' then
            exit;
        if WarehouseEmployee.Get(UserCode, LocationCode) then
            exit;
        WarehouseEmployee.Init();
        WarehouseEmployee."User ID" := UserCode;
        WarehouseEmployee."Location Code" := LocationCode;
        WarehouseEmployee.Default := false;
        WarehouseEmployee.Insert(true);
    end;

    local procedure PostAdjustment(ItemNo: Code[20]; LocationCode: Code[10]; BinCode: Code[20]; Quantity: Decimal)
    var
        ItemJournalLine: Record "Item Journal Line";
        ItemJournalTemplate: Record "Item Journal Template";
        ItemJournalBatch: Record "Item Journal Batch";
    begin
        LibraryInventory.SelectItemJournalTemplateName(ItemJournalTemplate, ItemJournalTemplate.Type::Item);
        LibraryInventory.SelectItemJournalBatchName(ItemJournalBatch, ItemJournalTemplate.Type::Item, ItemJournalTemplate.Name);
        LibraryInventory.ClearItemJournal(ItemJournalTemplate, ItemJournalBatch);
        LibraryInventory.CreateItemJournalLine(ItemJournalLine, ItemJournalTemplate.Name, ItemJournalBatch.Name, "Item Ledger Entry Type"::"Positive Adjmt.", ItemNo, Quantity);
        ItemJournalLine.Validate("Location Code", LocationCode);
        ItemJournalLine.Validate("Bin Code", BinCode);
        ItemJournalLine.Modify(true);
        LibraryInventory.PostItemJournalLine(ItemJournalTemplate.Name, ItemJournalBatch.Name);
    end;

    local procedure LineRequest(LocationCode: Code[10]; ItemNo: Code[20]; Quantity: Decimal; FromBin: Code[20]; ToBin: Code[20]): Text
    begin
        exit('{"locationCode":"' + LocationCode + '","lines":[{"itemNo":"' + ItemNo + '","quantity":' + Format(Quantity, 0, 9) + ',"fromBin":"' + FromBin + '","toBin":"' + ToBin + '"}]}');
    end;

    local procedure Run(RequestText: Text; Subject: Text; var ResponseJson: JsonObject)
    var
        Helper: Codeunit "Whse Receipt Test Helper ori";
    begin
        Assert.IsTrue(Helper.RunMessage(Enum::"Message Type ori"::"Warehouse.InventoryMovement.Create", Subject, RequestText, ResponseJson), 'The response should be JSON.');
    end;

    local procedure FirstLine(ResponseJson: JsonObject): JsonObject
    var
        Token: JsonToken;
        Lines: JsonArray;
    begin
        Assert.IsTrue(ResponseJson.Get('lines', Token), 'The response should list lines.');
        Lines := Token.AsArray();
        Lines.Get(0, Token);
        exit(Token.AsObject());
    end;

    local procedure ResponseText(ResponseJson: JsonObject): Text
    var
        Written: Text;
    begin
        ResponseJson.WriteTo(Written);
        exit(Written);
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

    local procedure IntegerValue(Parent: JsonObject; Name: Text): Integer
    var
        Token: JsonToken;
    begin
        if not Parent.Get(Name, Token) then
            exit(-1);
        if not Token.IsValue() then
            exit(-1);
        exit(Token.AsValue().AsInteger());
    end;
}
