namespace Origo.Bifrost.Warehouse.Test;

using Microsoft.Inventory.Item;
using Microsoft.Inventory.Location;
using Microsoft.Inventory.Setup;
using Microsoft.Sales.Customer;
using Microsoft.Sales.Document;
using Microsoft.Warehouse.Activity;
using Origo.Bifrost;
using Origo.Bifrost.Warehouse;
using System.TestLibraries.Utilities;

/// <summary>
/// Tests Warehouse.InventoryPick.Create through the public dispatcher and the permission denial path.
/// </summary>
codeunit 97085 "Whse InvtPick Create Tests ori"
{
    Subtype = Test;
    TestPermissions = Disabled;

    var
        Assert: Codeunit "Library Assert";
        LibraryInventory: Codeunit "Library - Inventory";
        LibrarySales: Codeunit "Library - Sales";
        LibraryUtility: Codeunit "Library - Utility";
        LibraryWarehouse: Codeunit "Library - Warehouse";
        NotReleasedNextStepTxt: Label 'Release the document with Sales.Document.Release, or post the document directly.', Locked = true;
        ShipmentNextStepTxt: Label 'Use Warehouse.Shipment.Create and Warehouse.Pick.Create instead.', Locked = true;
        ExistsNextStepTxt: Label 'Use Warehouse.InventoryPick.Post for the existing inventory pick.', Locked = true;

    /// <summary>A released sales order at a require-pick location returns one inventory pick.</summary>
    [Test]
    procedure Create_ReleasedSalesOrder_CreatesPick()
    var
        Location: Record Location;
        Item: Record Item;
        SalesHeader: Record "Sales Header";
        ActivityHeader: Record "Warehouse Activity Header";
        ResponseJson: JsonObject;
        PickJson: JsonObject;
    begin
        PrepareSalesOrder(Location, Item, SalesHeader, true);

        Run(SalesRequest(SalesHeader."No."), '', ResponseJson);

        Assert.AreEqual('Success', TextValue(ResponseJson, 'status'), ResponseText(ResponseJson));
        Assert.AreEqual('Sales Order', TextValue(ResponseJson, 'sourceDocument'), 'The source document should be returned.');
        Assert.AreEqual(SalesHeader."No.", TextValue(ResponseJson, 'sourceNo'), 'The source number should be returned.');
        Assert.AreEqual(1, IntegerValue(ResponseJson, 'pickCount'), 'One inventory pick should be created.');
        PickJson := FirstPick(ResponseJson);
        Assert.AreEqual(Item."No.", TextValue(FirstLine(PickJson), 'itemNo'), 'The pick line should name the item.');
        Assert.IsTrue(ActivityHeader.Get(ActivityHeader.Type::"Invt. Pick", CopyStr(TextValue(PickJson, 'pickNo'), 1, MaxStrLen(ActivityHeader."No."))), 'The inventory pick should exist.');
    end;

    /// <summary>An unreleased sales order is refused and writes nothing.</summary>
    [Test]
    procedure Create_UnreleasedSalesOrder_IsRefused()
    var
        Location: Record Location;
        Item: Record Item;
        SalesHeader: Record "Sales Header";
        ResponseJson: JsonObject;
    begin
        PrepareSalesOrder(Location, Item, SalesHeader, false);

        Run(SalesRequest(SalesHeader."No."), '', ResponseJson);

        Assert.AreEqual('PreconditionFailed', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));
        Assert.AreEqual(NotReleasedNextStepTxt, TextValue(ResponseJson, 'nextStep'), 'The next step should name release or direct post.');
        Assert.AreEqual(0, CountPicks(SalesHeader."No."), 'An unreleased order must not get an inventory pick.');
    end;

    /// <summary>A location that requires shipment is refused and writes nothing.</summary>
    [Test]
    procedure Create_RequireShipmentLocation_IsRefused()
    var
        Location: Record Location;
        Item: Record Item;
        SalesHeader: Record "Sales Header";
        ResponseJson: JsonObject;
    begin
        PrepareSalesOrderOnLocation(Location, Item, SalesHeader, true, true, true);

        Run(SalesRequest(SalesHeader."No."), '', ResponseJson);

        Assert.AreEqual('PreconditionFailed', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));
        Assert.AreEqual(ShipmentNextStepTxt, TextValue(ResponseJson, 'nextStep'), 'The next step should name the shipment and pick types.');
        Assert.AreEqual(0, CountPicks(SalesHeader."No."), 'A shipment location must not get an inventory pick.');
    end;

    /// <summary>A location that does not require pick is refused and writes nothing.</summary>
    [Test]
    procedure Create_LocationWithoutPick_IsRefused()
    var
        Location: Record Location;
        Item: Record Item;
        SalesHeader: Record "Sales Header";
        ResponseJson: JsonObject;
    begin
        PrepareSalesOrderOnLocation(Location, Item, SalesHeader, true, false, false);

        Run(SalesRequest(SalesHeader."No."), '', ResponseJson);

        Assert.AreEqual('PreconditionFailed', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));
        Assert.AreEqual(NotReleasedNextStepTxt, TextValue(ResponseJson, 'nextStep'), 'The next step should name release or direct post.');
        Assert.AreEqual(0, CountPicks(SalesHeader."No."), 'A location without pick must not get an inventory pick.');
    end;

    /// <summary>A missing source document is refused.</summary>
    [Test]
    procedure Create_MissingSourceDocument_IsRefused()
    var
        ResponseJson: JsonObject;
    begin
        Run('{"sourceNo":"1001"}', '', ResponseJson);

        Assert.AreEqual('MissingParameter', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));
        Assert.AreEqual('sourceDocument', TextValue(ResponseJson, 'parameter'), 'The error should name sourceDocument.');
    end;

    /// <summary>An unknown key is refused and writes nothing.</summary>
    [Test]
    procedure Create_UnknownKey_IsRefused()
    var
        Location: Record Location;
        Item: Record Item;
        SalesHeader: Record "Sales Header";
        ResponseJson: JsonObject;
    begin
        PrepareSalesOrder(Location, Item, SalesHeader, true);

        Run('{"sourceDocument":"Sales Order","sourceNo":"' + SalesHeader."No." + '","note":"nope"}', '', ResponseJson);

        Assert.AreEqual('UnknownParameter', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));
        Assert.AreEqual('note', TextValue(ResponseJson, 'parameter'), 'The error should name the unknown key.');
        Assert.AreEqual(0, CountPicks(SalesHeader."No."), 'An unknown key must not create an inventory pick.');
    end;

    /// <summary>A source document sent as a number is refused.</summary>
    [Test]
    procedure Create_WrongSourceDocumentType_IsRefused()
    var
        ResponseJson: JsonObject;
    begin
        Run('{"sourceDocument":1,"sourceNo":"1001"}', '', ResponseJson);

        Assert.AreEqual('InvalidParameterFormat', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));
        Assert.AreEqual('sourceDocument', TextValue(ResponseJson, 'parameter'), 'The error should name sourceDocument.');
    end;

    /// <summary>An unknown document number is refused.</summary>
    [Test]
    procedure Create_UnknownSourceNo_IsRefused()
    var
        ResponseJson: JsonObject;
    begin
        Run('{"sourceDocument":"Sales Order","sourceNo":"MISSING-SO"}', '', ResponseJson);

        Assert.AreEqual('RecordNotFound', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));
        Assert.AreEqual('sourceNo', TextValue(ResponseJson, 'parameter'), 'The error should name sourceNo.');
    end;

    /// <summary>A number and a different SystemId are refused and write nothing.</summary>
    [Test]
    procedure Create_ConflictingIdentifiers_IsRefused()
    var
        Location: Record Location;
        Item: Record Item;
        SalesHeader: Record "Sales Header";
        ResponseJson: JsonObject;
    begin
        PrepareSalesOrder(Location, Item, SalesHeader, true);

        Run('{"sourceDocument":"Sales Order","sourceNo":"' + SalesHeader."No." + '","systemId":"00000000-0000-0000-0000-000000000099"}', '', ResponseJson);

        Assert.AreEqual('ConflictingIdentifiers', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));
        Assert.AreEqual(0, CountPicks(SalesHeader."No."), 'Conflicting identifiers must not create an inventory pick.');
    end;

    /// <summary>A second create returns the open inventory pick and a warning.</summary>
    [Test]
    procedure Create_ExistingPick_ReturnsItWithWarning()
    var
        Location: Record Location;
        Item: Record Item;
        SalesHeader: Record "Sales Header";
        ResponseJson: JsonObject;
        FirstPickNo: Text;
    begin
        PrepareSalesOrder(Location, Item, SalesHeader, true);
        Run(SalesRequest(SalesHeader."No."), '', ResponseJson);
        Assert.AreEqual('Success', TextValue(ResponseJson, 'status'), ResponseText(ResponseJson));
        FirstPickNo := TextValue(FirstPick(ResponseJson), 'pickNo');

        Run(SalesRequest(SalesHeader."No."), '', ResponseJson);

        Assert.AreEqual('Success', TextValue(ResponseJson, 'status'), ResponseText(ResponseJson));
        Assert.AreEqual(FirstPickNo, TextValue(FirstPick(ResponseJson), 'pickNo'), 'The existing pick should be returned.');
        Assert.AreEqual('PreconditionFailed', TextValue(FirstWarning(ResponseJson), 'code'), ResponseText(ResponseJson));
        Assert.AreEqual(ExistsNextStepTxt, TextValue(FirstWarning(ResponseJson), 'nextStep'), 'The warning should name inventory pick post.');
        Assert.AreEqual(1, CountPicks(SalesHeader."No."), 'A second create must not add another inventory pick.');
    end;

    /// <summary>Create is disabled and returns PermissionDenied without activity write permission.</summary>
    [Test]
    [TestPermissions(TestPermissions::Restrictive)]
    procedure Create_WithoutPermission_ReturnsPermissionDenied()
    var
        TempArgument: Record "Message Argument ori" temporary;
        CreateImpl: Codeunit "Whse InvtPick Create Impl ori";
        LibraryLowerPermissions: Codeunit "Library - Lower Permissions";
        MessageTypeInterface: Interface "Msg Interface ori";
        ResponseJson: JsonObject;
    begin
        LibraryLowerPermissions.PushPermissionSetWithoutDefaults('Whse NoRead Test ori');
        LibraryLowerPermissions.AddPermissionSet('Whse Gate Test ori');
        MessageTypeInterface := Enum::"Message Type ori"::"Warehouse.InventoryPick.Create";
        Assert.IsFalse(MessageTypeInterface.IsEnabled(), 'Create must be disabled without activity write permission.');

        TempArgument.Init();
        TempArgument.Version := "Message Version ori"::"1.0";
        TempArgument.Insert(true);
        CreateImpl.ExecuteBifrostTask(TempArgument);
        ResponseJson := TempArgument.GetResponseJson();
        Assert.AreEqual('PermissionDenied', TextValue(ResponseJson, 'code'), 'The denial must use PermissionDenied.');
        Assert.AreEqual('Ask an administrator to assign BIFROST Whse - Full ori.', TextValue(ResponseJson, 'nextStep'), 'The next step must name the full permission set.');
    end;

    local procedure PrepareSalesOrder(var Location: Record Location; var Item: Record Item; var SalesHeader: Record "Sales Header"; ReleaseDocument: Boolean)
    begin
        PrepareSalesOrderOnLocation(Location, Item, SalesHeader, ReleaseDocument, true, false);
    end;

    local procedure PrepareSalesOrderOnLocation(var Location: Record Location; var Item: Record Item; var SalesHeader: Record "Sales Header"; ReleaseDocument: Boolean; RequirePick: Boolean; RequireShipment: Boolean)
    var
        Customer: Record Customer;
        SalesLine: Record "Sales Line";
        ShipmentHelper: Codeunit "Whse Shipment Test Helper ori";
        ReleaseSalesDocument: Codeunit "Release Sales Document";
    begin
        LibraryWarehouse.CreateLocationWMS(Location, false, false, RequirePick, false, RequireShipment);
        EnsureInventoryPickNos();
        ShipmentHelper.RegisterCurrentUserAsWarehouseEmployee(Location.Code);
        LibraryInventory.CreateItem(Item);
        ShipmentHelper.CreatePositiveAdjustment(Item."No.", Location.Code, 5);
        LibrarySales.CreateCustomer(Customer);
        LibrarySales.CreateSalesHeader(SalesHeader, SalesHeader."Document Type"::Order, Customer."No.");
        SalesHeader.Validate("Location Code", Location.Code);
        SalesHeader.Modify(true);
        LibrarySales.CreateSalesLine(SalesLine, SalesHeader, SalesLine.Type::Item, Item."No.", 1);
        SalesLine.Validate("Location Code", Location.Code);
        SalesLine.Validate("Unit Price", 100);
        SalesLine.Modify(true);
        if not ReleaseDocument then
            exit;
        ReleaseSalesDocument.Run(SalesHeader);
        SalesHeader.Get(SalesHeader."Document Type"::Order, SalesHeader."No.");
    end;

    local procedure EnsureInventoryPickNos()
    var
        InventorySetup: Record "Inventory Setup";
    begin
        InventorySetup.Get();
        if InventorySetup."Inventory Pick Nos." = '' then
            InventorySetup.Validate("Inventory Pick Nos.", LibraryUtility.GetGlobalNoSeriesCode());
        if InventorySetup."Posted Invt. Pick Nos." = '' then
            InventorySetup.Validate("Posted Invt. Pick Nos.", LibraryUtility.GetGlobalNoSeriesCode());
        InventorySetup.Modify(true);
    end;

    local procedure SalesRequest(SourceNo: Code[20]): Text
    begin
        exit('{"sourceDocument":"Sales Order","sourceNo":"' + SourceNo + '"}');
    end;

    local procedure CountPicks(SourceNo: Code[20]): Integer
    var
        ActivityHeader: Record "Warehouse Activity Header";
    begin
        ActivityHeader.SetRange(Type, ActivityHeader.Type::"Invt. Pick");
        ActivityHeader.SetRange("Source No.", SourceNo);
        exit(ActivityHeader.Count());
    end;

    local procedure Run(RequestText: Text; Subject: Text; var ResponseJson: JsonObject)
    var
        Helper: Codeunit "Whse Receipt Test Helper ori";
    begin
        Assert.IsTrue(Helper.RunMessage(Enum::"Message Type ori"::"Warehouse.InventoryPick.Create", Subject, RequestText, ResponseJson), 'The response should be JSON.');
    end;

    local procedure FirstPick(ResponseJson: JsonObject): JsonObject
    var
        Token: JsonToken;
        Picks: JsonArray;
    begin
        Assert.IsTrue(ResponseJson.Get('picks', Token), 'The response should list picks.');
        Picks := Token.AsArray();
        Picks.Get(0, Token);
        exit(Token.AsObject());
    end;

    local procedure FirstLine(PickJson: JsonObject): JsonObject
    var
        Token: JsonToken;
        Lines: JsonArray;
    begin
        Assert.IsTrue(PickJson.Get('lines', Token), 'The pick should list lines.');
        Lines := Token.AsArray();
        Lines.Get(0, Token);
        exit(Token.AsObject());
    end;

    local procedure FirstWarning(ResponseJson: JsonObject): JsonObject
    var
        Token: JsonToken;
        Warnings: JsonArray;
    begin
        Assert.IsTrue(ResponseJson.Get('warnings', Token), 'The response should list warnings.');
        Warnings := Token.AsArray();
        Warnings.Get(0, Token);
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
