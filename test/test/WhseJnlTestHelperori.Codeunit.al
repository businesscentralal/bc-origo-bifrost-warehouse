namespace Origo.Bifrost.Warehouse.Test;

using Microsoft.Inventory.Item;
using Microsoft.Inventory.Location;
using Microsoft.Purchases.Document;
using Microsoft.Sales.Document;
using Microsoft.Warehouse.Activity;
using Microsoft.Warehouse.Document;
using Microsoft.Warehouse.History;
using Microsoft.Warehouse.Journal;
using Microsoft.Warehouse.Setup;
using Microsoft.Warehouse.Structure;
using Microsoft.Warehouse.Worksheet;
using Origo.Bifrost;
using System.TestLibraries.Utilities;

/// <summary>
/// Shared fixtures and JSON readers for the journal, worksheet and activity line tests (#48-#50, #55-#57).
/// </summary>
codeunit 97050 "Whse Jnl Test Helper ori"
{
    Access = Internal;

    var
        Assert: Codeunit "Library Assert";
        LibraryInventory: Codeunit "Library - Inventory";
        LibraryWarehouse: Codeunit "Library - Warehouse";
        LibraryUtility: Codeunit "Library - Utility";

    /// <summary>Dispatches a message through the public dispatcher in the caller's transaction.</summary>
    /// <param name="MessageType">The message type.</param>
    /// <param name="Subject">The subject.</param>
    /// <param name="RequestText">The request JSON.</param>
    /// <returns>The parsed response.</returns>
    internal procedure RunType(MessageType: Enum "Message Type ori"; Subject: Text; RequestText: Text) ResponseJson: JsonObject
    var
        ReceiptHelper: Codeunit "Whse Receipt Test Helper ori";
    begin
        Assert.IsTrue(ReceiptHelper.RunMessage(MessageType, Subject, RequestText, ResponseJson), 'The response should be JSON.');
    end;

    /// <summary>Asserts a successful response.</summary>
    /// <param name="ResponseJson">The response.</param>
    internal procedure AssertSuccess(ResponseJson: JsonObject)
    begin
        Assert.AreEqual('Success', TextValue(ResponseJson, 'status'), ResponseText(ResponseJson));
    end;

    /// <summary>Asserts an error response with its code and, when given, its next step.</summary>
    /// <param name="ResponseJson">The response.</param>
    /// <param name="ExpectedCode">The error code.</param>
    /// <param name="ExpectedNextStep">The next step, or empty to only require one.</param>
    internal procedure ExpectError(ResponseJson: JsonObject; ExpectedCode: Text; ExpectedNextStep: Text)
    begin
        Assert.AreEqual('Error', TextValue(ResponseJson, 'status'), ResponseText(ResponseJson));
        Assert.AreEqual(ExpectedCode, TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));
        if ExpectedNextStep <> '' then
            Assert.AreEqual(ExpectedNextStep, TextValue(ResponseJson, 'nextStep'), ResponseText(ResponseJson))
        else
            Assert.AreNotEqual('', TextValue(ResponseJson, 'nextStep'), 'Every refusal carries a next step. ' + ResponseText(ResponseJson));
    end;

    /// <summary>Creates a directed put-away and pick location and makes the user its default warehouse employee.</summary>
    /// <param name="Location">Receives the location.</param>
    internal procedure CreateDirectedLocation(var Location: Record Location)
    begin
        LibraryWarehouse.CreateFullWMSLocation(Location, 3);
        EnsureDefaultEmployee(Location.Code);
    end;

    /// <summary>Creates a basic location without bins or directed put-away and pick.</summary>
    /// <param name="Location">Receives the location.</param>
    internal procedure CreateBasicLocation(var Location: Record Location)
    begin
        LibraryWarehouse.CreateLocationWMS(Location, false, false, false, false, false);
    end;

    /// <summary>Finds a bin of the pick zone of a directed location.</summary>
    /// <param name="LocationCode">The location.</param>
    /// <param name="BinIndex">1-based index of the bin.</param>
    /// <param name="Bin">Receives the bin.</param>
    internal procedure FindPickBin(LocationCode: Code[10]; BinIndex: Integer; var Bin: Record Bin)
    var
        Zone: Record Zone;
    begin
        LibraryWarehouse.FindZone(Zone, LocationCode, LibraryWarehouse.SelectBinType(false, false, true, true), false);
        LibraryWarehouse.FindBin(Bin, LocationCode, Zone.Code, BinIndex);
    end;

    /// <summary>Creates a warehouse journal template of a type and a batch at a location.</summary>
    /// <param name="TemplateType">Item, Physical Inventory or Reclassification.</param>
    /// <param name="LocationCode">The batch location.</param>
    /// <param name="WarehouseJournalBatch">Receives the batch.</param>
    internal procedure CreateWhseJournalBatch(TemplateType: Enum "Warehouse Journal Template Type"; LocationCode: Code[10]; var WarehouseJournalBatch: Record "Warehouse Journal Batch")
    var
        WarehouseJournalTemplate: Record "Warehouse Journal Template";
    begin
        LibraryWarehouse.CreateWhseJournalTemplate(WarehouseJournalTemplate, TemplateType);
        LibraryWarehouse.CreateWhseJournalBatch(WarehouseJournalBatch, WarehouseJournalTemplate.Name, LocationCode);
    end;

    /// <summary>Registers stock into a bin through the warehouse item journal and posts the item adjustment.</summary>
    /// <param name="Bin">The bin.</param>
    /// <param name="ItemNo">The item.</param>
    /// <param name="Quantity">The quantity.</param>
    internal procedure StockBin(Bin: Record Bin; ItemNo: Code[20]; Quantity: Decimal)
    begin
        LibraryWarehouse.UpdateInventoryInBinUsingWhseJournal(Bin, ItemNo, Quantity, false);
    end;

    /// <summary>Creates an item.</summary>
    /// <param name="Item">Receives the item.</param>
    internal procedure CreateItem(var Item: Record Item)
    begin
        LibraryInventory.CreateItem(Item);
    end;

    /// <summary>Returns a new unique code.</summary>
    /// <returns>A code of up to 10 characters.</returns>
    internal procedure NewCode(): Code[10]
    begin
        exit(CopyStr(LibraryUtility.GenerateGUID(), 1, 10));
    end;

    /// <summary>Creates a warehouse movement through Warehouse.Movement.Create.</summary>
    /// <param name="LocationCode">Directed location.</param>
    /// <param name="ItemNo">Item.</param>
    /// <param name="FromBin">Bin the quantity is taken from.</param>
    /// <param name="ToBin">Bin the quantity is placed in.</param>
    /// <param name="Quantity">Quantity.</param>
    /// <returns>The movement number.</returns>
    internal procedure CreateMovement(LocationCode: Code[10]; ItemNo: Code[20]; FromBin: Code[20]; ToBin: Code[20]; Quantity: Decimal): Code[20]
    var
        ResponseJson: JsonObject;
    begin
        EnsureMovementWorksheetTemplate();
        ResponseJson := RunType(Enum::"Message Type ori"::"Warehouse.Movement.Create", '', '{"locationCode":"' + LocationCode + '","lines":[{"itemNo":"' + ItemNo + '","quantity":' + Format(Quantity, 0, 9) + ',"fromBin":"' + FromBin + '","toBin":"' + ToBin + '"}]}');
        AssertSuccess(ResponseJson);
        exit(CopyStr(TextValue(ResponseJson, 'movementNo'), 1, 20));
    end;

    /// <summary>Finds the first line of an activity with an action type.</summary>
    /// <param name="ActivityType">The activity type.</param>
    /// <param name="ActivityNo">The activity number.</param>
    /// <param name="ActionType">The action type.</param>
    /// <param name="ActivityLine">Receives the line.</param>
    internal procedure FindLine(ActivityType: Enum "Warehouse Activity Type"; ActivityNo: Code[20]; ActionType: Enum "Warehouse Action Type"; var ActivityLine: Record "Warehouse Activity Line")
    begin
        ActivityLine.SetRange("Activity Type", ActivityType);
        ActivityLine.SetRange("No.", ActivityNo);
        ActivityLine.SetRange("Action Type", ActionType);
        ActivityLine.FindFirst();
    end;

    /// <summary>Creates an open activity header and one line with every quantity field set, without Business Central logic.</summary>
    /// <param name="ActivityType">The activity type.</param>
    /// <param name="ActionType">The action type of the line.</param>
    /// <param name="LocationCode">The location.</param>
    /// <param name="ItemNo">The item; its base unit of measure is used.</param>
    /// <param name="ZoneCode">The zone of the line.</param>
    /// <param name="BinCode">The bin of the line.</param>
    /// <param name="Quantity">The quantity, outstanding quantity and quantity to handle.</param>
    /// <returns>The activity number; the line number is 10000.</returns>
    internal procedure CreateRawActivity(ActivityType: Enum "Warehouse Activity Type"; ActionType: Enum "Warehouse Action Type"; LocationCode: Code[10]; ItemNo: Code[20]; ZoneCode: Code[10]; BinCode: Code[20]; Quantity: Decimal) ActivityNo: Code[20]
    var
        TestData: Codeunit "Whse Test Data ori";
    begin
        ActivityNo := NewCode();
        TestData.CreateActivityHeader(ActivityType, ActivityNo, LocationCode, '');
        AddRawLine(ActivityType, ActivityNo, 10000, ActionType, LocationCode, ItemNo, ZoneCode, BinCode, Quantity);
    end;

    /// <summary>Adds a raw activity line with every quantity field set.</summary>
    /// <param name="ActivityType">The activity type.</param>
    /// <param name="ActivityNo">The activity number.</param>
    /// <param name="LineNo">The line number.</param>
    /// <param name="ActionType">The action type.</param>
    /// <param name="LocationCode">The location.</param>
    /// <param name="ItemNo">The item.</param>
    /// <param name="ZoneCode">The zone.</param>
    /// <param name="BinCode">The bin.</param>
    /// <param name="Quantity">The quantity.</param>
    internal procedure AddRawLine(ActivityType: Enum "Warehouse Activity Type"; ActivityNo: Code[20]; LineNo: Integer; ActionType: Enum "Warehouse Action Type"; LocationCode: Code[10]; ItemNo: Code[20]; ZoneCode: Code[10]; BinCode: Code[20]; Quantity: Decimal)
    var
        Item: Record Item;
        ActivityLine: Record "Warehouse Activity Line";
    begin
        Item.Get(ItemNo);
        ActivityLine.Init();
        ActivityLine."Activity Type" := ActivityType;
        ActivityLine."No." := ActivityNo;
        ActivityLine."Line No." := LineNo;
        ActivityLine."Action Type" := ActionType;
        ActivityLine."Location Code" := LocationCode;
        ActivityLine."Item No." := ItemNo;
        ActivityLine."Unit of Measure Code" := Item."Base Unit of Measure";
        ActivityLine."Qty. per Unit of Measure" := 1;
        ActivityLine."Zone Code" := ZoneCode;
        ActivityLine."Bin Code" := BinCode;
        ActivityLine.Quantity := Quantity;
        ActivityLine."Qty. (Base)" := Quantity;
        ActivityLine."Qty. Outstanding" := Quantity;
        ActivityLine."Qty. Outstanding (Base)" := Quantity;
        ActivityLine."Qty. to Handle" := Quantity;
        ActivityLine."Qty. to Handle (Base)" := Quantity;
        ActivityLine."Whse. Document No." := ActivityNo;
        ActivityLine."Whse. Document Line No." := 10000;
        ActivityLine.Insert(false);
    end;

    /// <summary>Makes the current user the default warehouse employee of a location.</summary>
    /// <param name="LocationCode">The location.</param>
    internal procedure EnsureDefaultEmployee(LocationCode: Code[10])
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

    /// <summary>Creates a movement worksheet template when none exists.</summary>
    internal procedure EnsureMovementWorksheetTemplate()
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

    /// <summary>Creates a location with pick and shipment, stock, and a released warehouse shipment for a sales order.</summary>
    /// <param name="Location">Receives the location.</param>
    /// <param name="ShipmentHeader">Receives the released shipment.</param>
    /// <param name="Quantity">The sales quantity.</param>
    internal procedure CreateReleasedShipment(var Location: Record Location; var ShipmentHeader: Record "Warehouse Shipment Header"; Quantity: Decimal)
    var
        Item: Record Item;
        ShipmentHelper: Codeunit "Whse Shipment Test Helper ori";
    begin
        ShipmentHelper.SetupPickLocationAndItem(Location, Item, 20);
        AddReleasedShipment(Location.Code, Item."No.", Quantity, ShipmentHeader);
    end;

    /// <summary>Adds a released warehouse shipment for a new sales order at a location.</summary>
    /// <param name="LocationCode">The location.</param>
    /// <param name="ItemNo">The item.</param>
    /// <param name="Quantity">The quantity.</param>
    /// <param name="ShipmentHeader">Receives the shipment.</param>
    internal procedure AddReleasedShipment(LocationCode: Code[10]; ItemNo: Code[20]; Quantity: Decimal; var ShipmentHeader: Record "Warehouse Shipment Header")
    var
        SalesHeader: Record "Sales Header";
        ShipmentHelper: Codeunit "Whse Shipment Test Helper ori";
    begin
        ShipmentHelper.CreateReleasedSalesOrder(SalesHeader, ItemNo, LocationCode, Quantity);
        ShipmentHelper.CreateWhseShipmentFromSalesOrder(ShipmentHeader, SalesHeader);
        LibraryWarehouse.ReleaseWarehouseShipment(ShipmentHeader);
    end;

    /// <summary>Creates a receive and put-away location and a posted warehouse receipt.</summary>
    /// <param name="Location">Receives the location.</param>
    /// <param name="PostedReceiptHeader">Receives the posted receipt.</param>
    /// <param name="Quantity">The purchase quantity.</param>
    internal procedure CreatePostedReceipt(var Location: Record Location; var PostedReceiptHeader: Record "Posted Whse. Receipt Header"; Quantity: Decimal)
    var
        Item: Record Item;
        PurchaseHeader: Record "Purchase Header";
        ReceiptHeader: Record "Warehouse Receipt Header";
        ReceiptHelper: Codeunit "Whse Receipt Test Helper ori";
    begin
        ReceiptHelper.SetupReceivePutawayLocationAndItem(Location, Item, 0);
        ReceiptHelper.CreateReleasedPurchaseOrder(PurchaseHeader, Item."No.", Location.Code, Quantity);
        ReceiptHelper.CreateWhseReceiptFromPurchaseOrder(ReceiptHeader, PurchaseHeader);
        ReceiptHelper.PostWhseReceipt(ReceiptHeader, PostedReceiptHeader);
    end;

    /// <summary>Creates a worksheet name of a template type at a location.</summary>
    /// <param name="TemplateType">Pick or Put-away.</param>
    /// <param name="LocationCode">The location.</param>
    /// <param name="WorksheetName">Receives the worksheet name.</param>
    internal procedure CreateWorksheetName(TemplateType: Enum "Warehouse Worksheet Template Type"; LocationCode: Code[10]; var WorksheetName: Record "Whse. Worksheet Name")
    var
        WorksheetTemplate: Record "Whse. Worksheet Template";
    begin
        LibraryWarehouse.SelectWhseWorksheetTemplate(WorksheetTemplate, TemplateType);
        LibraryWarehouse.CreateWhseWorksheetName(WorksheetName, WorksheetTemplate.Name, LocationCode);
    end;

    /// <summary>Builds a worksheet request.</summary>
    /// <param name="WorksheetType">pick or putAway.</param>
    /// <param name="WorksheetName">The worksheet name.</param>
    /// <param name="Extra">More keys, starting with a comma.</param>
    /// <returns>The request.</returns>
    internal procedure WorksheetRequest(WorksheetType: Text; WorksheetName: Record "Whse. Worksheet Name"; Extra: Text): Text
    begin
        exit('{"worksheetType":"' + WorksheetType + '","worksheetTemplateName":"' + WorksheetName."Worksheet Template Name" + '","worksheetName":"' + WorksheetName.Name + '","locationCode":"' + WorksheetName."Location Code" + '"' + Extra + '}');
    end;

    /// <summary>Reads a text value.</summary>
    /// <param name="Parent">The object.</param>
    /// <param name="Name">The key.</param>
    /// <returns>The text, or empty.</returns>
    internal procedure TextValue(Parent: JsonObject; Name: Text): Text
    var
        Token: JsonToken;
    begin
        if not Parent.Get(Name, Token) then
            exit('');
        if not Token.IsValue() then
            exit('');
        if Token.AsValue().IsNull() then
            exit('');
        exit(Token.AsValue().AsText());
    end;

    /// <summary>Reads a decimal value.</summary>
    /// <param name="Parent">The object.</param>
    /// <param name="Name">The key.</param>
    /// <returns>The number, or -1.</returns>
    internal procedure DecimalValue(Parent: JsonObject; Name: Text): Decimal
    var
        Token: JsonToken;
    begin
        if not Parent.Get(Name, Token) then
            exit(-1);
        if not Token.IsValue() then
            exit(-1);
        exit(Token.AsValue().AsDecimal());
    end;

    /// <summary>Reads an integer value.</summary>
    /// <param name="Parent">The object.</param>
    /// <param name="Name">The key.</param>
    /// <returns>The integer, or -1.</returns>
    internal procedure IntegerValue(Parent: JsonObject; Name: Text): Integer
    var
        Token: JsonToken;
    begin
        if not Parent.Get(Name, Token) then
            exit(-1);
        if not Token.IsValue() then
            exit(-1);
        exit(Token.AsValue().AsInteger());
    end;

    /// <summary>Reads a boolean value.</summary>
    /// <param name="Parent">The object.</param>
    /// <param name="Name">The key.</param>
    /// <returns>The boolean, or false.</returns>
    internal procedure BooleanValue(Parent: JsonObject; Name: Text): Boolean
    var
        Token: JsonToken;
    begin
        if not Parent.Get(Name, Token) then
            exit(false);
        if not Token.IsValue() then
            exit(false);
        exit(Token.AsValue().AsBoolean());
    end;

    /// <summary>Reads an array.</summary>
    /// <param name="Parent">The object.</param>
    /// <param name="Name">The key.</param>
    /// <returns>The array, or an empty one.</returns>
    internal procedure ArrayValue(Parent: JsonObject; Name: Text): JsonArray
    var
        Token: JsonToken;
        Empty: JsonArray;
    begin
        if not Parent.Get(Name, Token) then
            exit(Empty);
        if not Token.IsArray() then
            exit(Empty);
        exit(Token.AsArray());
    end;

    /// <summary>Reads an object.</summary>
    /// <param name="Parent">The object.</param>
    /// <param name="Name">The key.</param>
    /// <returns>The object, or an empty one.</returns>
    internal procedure ObjectValue(Parent: JsonObject; Name: Text): JsonObject
    var
        Token: JsonToken;
        Empty: JsonObject;
    begin
        if not Parent.Get(Name, Token) then
            exit(Empty);
        if not Token.IsObject() then
            exit(Empty);
        exit(Token.AsObject());
    end;

    /// <summary>Returns the object at an array index.</summary>
    /// <param name="Items">The array.</param>
    /// <param name="Index">Zero-based index.</param>
    /// <returns>The object.</returns>
    internal procedure ItemAt(Items: JsonArray; Index: Integer): JsonObject
    var
        Token: JsonToken;
    begin
        Items.Get(Index, Token);
        exit(Token.AsObject());
    end;

    /// <summary>Writes a JSON object as text for assertion messages.</summary>
    /// <param name="ResponseJson">The object.</param>
    /// <returns>The text.</returns>
    internal procedure ResponseText(ResponseJson: JsonObject): Text
    var
        Written: Text;
    begin
        ResponseJson.WriteTo(Written);
        exit(Written);
    end;
}
