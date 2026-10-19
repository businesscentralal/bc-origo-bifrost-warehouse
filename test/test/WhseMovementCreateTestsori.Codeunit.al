namespace Origo.Bifrost.Warehouse.Test;

using Microsoft.Inventory.Item;
using Microsoft.Inventory.Location;
using Microsoft.Warehouse.Activity;
using Microsoft.Warehouse.Setup;
using Microsoft.Warehouse.Structure;
using Microsoft.Warehouse.Worksheet;
using Origo.Bifrost;
using Origo.Bifrost.Warehouse;
using System.TestLibraries.Utilities;

/// <summary>
/// Tests Warehouse.Movement.Create through the public dispatcher and the permission denial path.
/// </summary>
codeunit 97083 "Whse Movement Create Tests ori"
{
    Subtype = Test;
    TestPermissions = Disabled;

    var
        Assert: Codeunit "Library Assert";
        LibraryInventory: Codeunit "Library - Inventory";
        LibraryWarehouse: Codeunit "Library - Warehouse";

    /// <summary>A directed location moves stock from one bin to another and returns the movement.</summary>
    [Test]
    procedure Create_InlineLine_CreatesMovement()
    var
        Location: Record Location;
        Item: Record Item;
        FromBin: Record Bin;
        ToBin: Record Bin;
        ActivityHeader: Record "Warehouse Activity Header";
        WorksheetName: Record "Whse. Worksheet Name";
        ResponseJson: JsonObject;
        RequestText: Text;
    begin
        PrepareDirectedStock(Location, Item, FromBin, ToBin);

        RequestText := '{"locationCode":"' + Location.Code + '","lines":[{"itemNo":"' + Item."No." + '","quantity":1,"fromBin":"' + FromBin.Code + '","toBin":"' + ToBin.Code + '"}]}';
        Run(RequestText, '', ResponseJson);

        Assert.AreEqual('Success', TextValue(ResponseJson, 'status'), ResponseText(ResponseJson));
        Assert.AreEqual(Location.Code, TextValue(ResponseJson, 'locationCode'), 'The location should be returned.');
        Assert.AreEqual(1, IntegerValue(ResponseJson, 'lineCount'), 'One take and place pair should be counted.');
        Assert.IsTrue(ActivityHeader.Get(ActivityHeader.Type::Movement, CopyStr(TextValue(ResponseJson, 'movementNo'), 1, MaxStrLen(ActivityHeader."No."))), 'The movement should exist.');
        Assert.AreEqual(FromBin.Code, TextValue(FirstLine(ResponseJson), 'fromBin'), 'The from-bin should be returned.');
        Assert.AreEqual(ToBin.Code, TextValue(FirstLine(ResponseJson), 'toBin'), 'The to-bin should be returned.');
        WorksheetName.SetRange("Location Code", Location.Code);
        Assert.IsTrue(WorksheetName.IsEmpty(), 'The worksheet name generated for inline lines should be removed.');
    end;

    /// <summary>A location without directed put-away and pick is refused and writes nothing.</summary>
    [Test]
    procedure Create_BasicLocation_IsRefused()
    var
        Location: Record Location;
        WorksheetLine: Record "Whse. Worksheet Line";
        ResponseJson: JsonObject;
    begin
        LibraryWarehouse.CreateLocationWMS(Location, true, false, false, false, false);

        Run('{"locationCode":"' + Location.Code + '","lines":[{"itemNo":"ITEM","quantity":1,"fromBin":"A-01","toBin":"B-01"}]}', '', ResponseJson);

        Assert.AreEqual('PreconditionFailed', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));
        Assert.AreEqual('locationCode', TextValue(ResponseJson, 'parameter'), 'The error should name locationCode.');
        Assert.AreEqual('Use Warehouse.InventoryMovement.Create for basic warehouse locations.', TextValue(ResponseJson, 'nextStep'), 'The next step should name the inventory movement type.');
        WorksheetLine.SetRange("Location Code", Location.Code);
        Assert.AreEqual(0, WorksheetLine.Count(), 'A basic location must not get a worksheet line.');
    end;

    /// <summary>A missing location is refused before any worksheet line is written.</summary>
    [Test]
    procedure Create_MissingLocation_IsRefused()
    var
        ResponseJson: JsonObject;
    begin
        Run('{}', '', ResponseJson);

        Assert.AreEqual('MissingParameter', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));
        Assert.AreEqual('locationCode', TextValue(ResponseJson, 'parameter'), 'The error should name locationCode.');
    end;

    /// <summary>An unknown key is refused and writes nothing.</summary>
    [Test]
    procedure Create_UnknownKey_IsRefused()
    var
        Location: Record Location;
        Item: Record Item;
        FromBin: Record Bin;
        ToBin: Record Bin;
        WorksheetLine: Record "Whse. Worksheet Line";
        ResponseJson: JsonObject;
    begin
        PrepareDirectedStock(Location, Item, FromBin, ToBin);

        Run('{"locationCode":"' + Location.Code + '","note":"nope","lines":[{"itemNo":"' + Item."No." + '","quantity":1,"fromBin":"' + FromBin.Code + '","toBin":"' + ToBin.Code + '"}]}', '', ResponseJson);

        Assert.AreEqual('UnknownParameter', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));
        Assert.AreEqual('note', TextValue(ResponseJson, 'parameter'), 'The error should name the unknown key.');
        WorksheetLine.SetRange("Location Code", Location.Code);
        Assert.AreEqual(0, WorksheetLine.Count(), 'An unknown key must not write a worksheet line.');
    end;

    /// <summary>Zero quantity is refused and writes nothing.</summary>
    [Test]
    procedure Create_ZeroQuantity_IsRefused()
    var
        Location: Record Location;
        Item: Record Item;
        FromBin: Record Bin;
        ToBin: Record Bin;
        WorksheetLine: Record "Whse. Worksheet Line";
        ResponseJson: JsonObject;
    begin
        PrepareDirectedStock(Location, Item, FromBin, ToBin);

        Run('{"locationCode":"' + Location.Code + '","lines":[{"itemNo":"' + Item."No." + '","quantity":0,"fromBin":"' + FromBin.Code + '","toBin":"' + ToBin.Code + '"}]}', '', ResponseJson);

        Assert.AreEqual('InvalidParameter', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));
        Assert.AreEqual('lines[0].quantity', TextValue(ResponseJson, 'parameter'), 'The error should name the quantity.');
        WorksheetLine.SetRange("Location Code", Location.Code);
        Assert.AreEqual(0, WorksheetLine.Count(), 'A zero quantity must not write a worksheet line.');
    end;

    /// <summary>More than the bin contains is refused and writes nothing.</summary>
    [Test]
    procedure Create_QuantityAboveBinContent_IsRefused()
    var
        Location: Record Location;
        Item: Record Item;
        FromBin: Record Bin;
        ToBin: Record Bin;
        WorksheetLine: Record "Whse. Worksheet Line";
        ResponseJson: JsonObject;
    begin
        PrepareDirectedStock(Location, Item, FromBin, ToBin);

        Run('{"locationCode":"' + Location.Code + '","lines":[{"itemNo":"' + Item."No." + '","quantity":99,"fromBin":"' + FromBin.Code + '","toBin":"' + ToBin.Code + '"}]}', '', ResponseJson);

        Assert.AreEqual('InvalidLine', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));
        Assert.AreEqual('Read Warehouse.BinContent.Get for the bin and lower the quantity.', TextValue(ResponseJson, 'nextStep'), 'The next step should name BinContent.Get.');
        WorksheetLine.SetRange("Location Code", Location.Code);
        Assert.AreEqual(0, WorksheetLine.Count(), 'A short bin must not write a worksheet line.');
    end;

    /// <summary>An item that does not exist is RecordNotFound with the activity lookup next step, and nothing is written.</summary>
    [Test]
    procedure Create_UnknownItem_IsNotFound()
    var
        Location: Record Location;
        Item: Record Item;
        FromBin: Record Bin;
        ToBin: Record Bin;
        ActivityHeader: Record "Warehouse Activity Header";
        ResponseJson: JsonObject;
    begin
        PrepareDirectedStock(Location, Item, FromBin, ToBin);

        Run('{"locationCode":"' + Location.Code + '","lines":[{"itemNo":"BIFT-NOITEM","quantity":1,"fromBin":"' + FromBin.Code + '","toBin":"' + ToBin.Code + '"}]}', '', ResponseJson);

        Assert.AreEqual('RecordNotFound', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));
        Assert.AreEqual('lines[0].itemNo', TextValue(ResponseJson, 'parameter'), 'The error should name the line item.');
        Assert.AreEqual('Check the identifier with Warehouse.Activity.Get (activityType Movement).', TextValue(ResponseJson, 'nextStep'), 'The next step should name Activity.Get.');
        ActivityHeader.SetRange(Type, ActivityHeader.Type::Movement);
        ActivityHeader.SetRange("Location Code", Location.Code);
        Assert.IsTrue(ActivityHeader.IsEmpty(), 'No movement should be created.');
    end;

    /// <summary>Create is disabled and returns PermissionDenied without worksheet write permission.</summary>
    [Test]
    [TestPermissions(TestPermissions::Restrictive)]
    procedure Create_WithoutPermission_ReturnsPermissionDenied()
    var
        TempArgument: Record "Message Argument ori";
        CreateImpl: Codeunit "Whse Movement Create Impl ori";
        LibraryLowerPermissions: Codeunit "Library - Lower Permissions";
        MessageTypeInterface: Interface "Msg Interface ori";
        ResponseJson: JsonObject;
    begin
        LibraryLowerPermissions.PushPermissionSetWithoutDefaults('Whse NoRead Test ori');
        LibraryLowerPermissions.AddPermissionSet('Whse Gate Test ori');
        MessageTypeInterface := Enum::"Message Type ori"::"Warehouse.Movement.Create";
        Assert.IsFalse(MessageTypeInterface.IsEnabled(), 'Create must be disabled without worksheet write permission.');

        TempArgument.Init();
        TempArgument.Version := "Message Version ori"::"1.0";
        TempArgument.Insert(true);
        CreateImpl.ExecuteBifrostTask(TempArgument);
        ResponseJson := TempArgument.GetResponseJson();
        Assert.AreEqual('PermissionDenied', TextValue(ResponseJson, 'code'), 'The denial must use PermissionDenied.');
        Assert.AreEqual('Ask an administrator to assign BIFROST Whse - Full ori.', TextValue(ResponseJson, 'nextStep'), 'The next step must name the full permission set.');
    end;

    local procedure PrepareDirectedStock(var Location: Record Location; var Item: Record Item; var FromBin: Record Bin; var ToBin: Record Bin)
    var
        Zone: Record Zone;
    begin
        LibraryWarehouse.CreateFullWMSLocation(Location, 2);
        EnsureDefaultDirectedEmployee(Location.Code);
        EnsureMovementWorksheetTemplate();
        LibraryInventory.CreateItem(Item);
        LibraryWarehouse.UpdateInventoryOnLocationWithDirectedPutAwayAndPick(Item."No.", Location.Code, 5, false);
        LibraryWarehouse.FindZone(Zone, Location.Code, LibraryWarehouse.SelectBinType(false, false, true, true), false);
        LibraryWarehouse.FindBin(FromBin, Location.Code, Zone.Code, 1);
        LibraryWarehouse.FindBin(ToBin, Location.Code, Zone.Code, 2);
    end;

    local procedure EnsureDefaultDirectedEmployee(LocationCode: Code[10])
    var
        WarehouseEmployee: Record "Warehouse Employee";
        Existing: Record "Warehouse Employee";
        UserCode: Code[50];
    begin
        UserCode := CopyStr(UserId(), 1, MaxStrLen(UserCode));
        if UserCode = '' then
            exit;
        Existing.SetRange("User ID", UserCode);
        Existing.SetRange(Default, true);
        Existing.SetFilter("Location Code", '<>%1', LocationCode);
        while Existing.FindFirst() do begin
            Existing.Default := false;
            Existing.Modify(true);
        end;
        if WarehouseEmployee.Get(UserCode, LocationCode) then begin
            if not WarehouseEmployee.Default then begin
                WarehouseEmployee.Default := true;
                WarehouseEmployee.Modify(true);
            end;
            exit;
        end;
        WarehouseEmployee.Init();
        WarehouseEmployee."User ID" := UserCode;
        WarehouseEmployee."Location Code" := LocationCode;
        WarehouseEmployee.Default := true;
        WarehouseEmployee.Insert(true);
    end;

    local procedure EnsureMovementWorksheetTemplate()
    var
        WorksheetTemplate: Record "Whse. Worksheet Template";
    begin
        WorksheetTemplate.SetRange(Type, WorksheetTemplate.Type::Movement);
        if not WorksheetTemplate.IsEmpty() then
            exit;
        WorksheetTemplate.Init();
        WorksheetTemplate.Name := 'MOVEMENT';
        WorksheetTemplate.Validate(Type, WorksheetTemplate.Type::Movement);
        WorksheetTemplate.Description := 'Movement';
        WorksheetTemplate.Insert(true);
    end;

    local procedure Run(RequestText: Text; Subject: Text; var ResponseJson: JsonObject)
    var
        Helper: Codeunit "Whse Receipt Test Helper ori";
    begin
        Assert.IsTrue(Helper.RunMessage(Enum::"Message Type ori"::"Warehouse.Movement.Create", Subject, RequestText, ResponseJson), 'The response should be JSON.');
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
