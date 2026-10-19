namespace Origo.Bifrost.Warehouse.Test;

using Microsoft.Inventory.Item;
using Microsoft.Inventory.Location;
using Microsoft.Inventory.Setup;
using Microsoft.Purchases.Document;
using Microsoft.Purchases.Vendor;
using Microsoft.Warehouse.Activity;
using Microsoft.Warehouse.Structure;
using Origo.Bifrost;
using Origo.Bifrost.Warehouse;
using System.TestLibraries.Utilities;

/// <summary>
/// Tests Warehouse.InventoryPutAway.Create through the public dispatcher and the permission denial path.
/// </summary>
codeunit 97087 "Whse InvtPut Create Tests ori"
{
    Subtype = Test;
    TestPermissions = Disabled;

    var
        Assert: Codeunit "Library Assert";
        LibraryInventory: Codeunit "Library - Inventory";
        LibraryPurchase: Codeunit "Library - Purchase";
        LibraryUtility: Codeunit "Library - Utility";
        LibraryWarehouse: Codeunit "Library - Warehouse";
        NotReleasedNextStepTxt: Label 'Release the document first, or post it directly.', Locked = true;
        ReceiptNextStepTxt: Label 'Use Warehouse.Receipt.Create and Warehouse.Putaway.Create instead.', Locked = true;
        ExistsNextStepTxt: Label 'Use Warehouse.InventoryPutAway.Post for the existing inventory put-away.', Locked = true;

    /// <summary>A released purchase order at a require-put-away location returns one inventory put-away.</summary>
    [Test]
    procedure Create_ReleasedPurchaseOrder_CreatesPutAway()
    var
        Location: Record Location;
        Item: Record Item;
        PurchaseHeader: Record "Purchase Header";
        ActivityHeader: Record "Warehouse Activity Header";
        ResponseJson: JsonObject;
        PutawayJson: JsonObject;
    begin
        PreparePurchaseOrder(Location, Item, PurchaseHeader, true, true, false);

        Run(PurchaseRequest(PurchaseHeader."No."), '', ResponseJson);

        Assert.AreEqual('Success', TextValue(ResponseJson, 'status'), ResponseText(ResponseJson));
        Assert.AreEqual('Purchase Order', TextValue(ResponseJson, 'sourceDocument'), 'The source document should be returned.');
        Assert.AreEqual(PurchaseHeader."No.", TextValue(ResponseJson, 'sourceNo'), 'The source number should be returned.');
        Assert.AreEqual(1, IntegerValue(ResponseJson, 'putawayCount'), 'One inventory put-away should be created.');
        PutawayJson := FirstPutaway(ResponseJson);
        Assert.AreEqual(Item."No.", TextValue(FirstLine(PutawayJson), 'itemNo'), 'The put-away line should name the item.');
        Assert.AreEqual('PUT', TextValue(FirstLine(PutawayJson), 'binCode'), 'The put-away line should suggest the purchase bin.');
        Assert.IsTrue(ActivityHeader.Get(ActivityHeader.Type::"Invt. Put-away", CopyStr(TextValue(PutawayJson, 'putawayNo'), 1, MaxStrLen(ActivityHeader."No."))), 'The inventory put-away should exist.');
    end;

    /// <summary>An unreleased purchase order is refused and writes nothing.</summary>
    [Test]
    procedure Create_UnreleasedPurchaseOrder_IsRefused()
    var
        Location: Record Location;
        Item: Record Item;
        PurchaseHeader: Record "Purchase Header";
        ResponseJson: JsonObject;
    begin
        PreparePurchaseOrder(Location, Item, PurchaseHeader, false, true, false);

        Run(PurchaseRequest(PurchaseHeader."No."), '', ResponseJson);

        Assert.AreEqual('PreconditionFailed', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));
        Assert.AreEqual(NotReleasedNextStepTxt, TextValue(ResponseJson, 'nextStep'), 'The next step should name release or direct post.');
        Assert.AreEqual(0, CountPutaways(PurchaseHeader."No."), 'An unreleased order must not get an inventory put-away.');
    end;

    /// <summary>A location that requires a warehouse receipt is refused and writes nothing.</summary>
    [Test]
    procedure Create_RequireReceiptLocation_IsRefused()
    var
        Location: Record Location;
        Item: Record Item;
        PurchaseHeader: Record "Purchase Header";
        ResponseJson: JsonObject;
    begin
        PreparePurchaseOrder(Location, Item, PurchaseHeader, true, true, true);

        Run(PurchaseRequest(PurchaseHeader."No."), '', ResponseJson);

        Assert.AreEqual('PreconditionFailed', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));
        Assert.AreEqual(ReceiptNextStepTxt, TextValue(ResponseJson, 'nextStep'), 'The next step should name the receipt and put-away types.');
        Assert.AreEqual(0, CountPutaways(PurchaseHeader."No."), 'A receipt location must not get an inventory put-away.');
    end;

    /// <summary>A location that does not require put-away is refused and writes nothing.</summary>
    [Test]
    procedure Create_LocationWithoutPutAway_IsRefused()
    var
        Location: Record Location;
        Item: Record Item;
        PurchaseHeader: Record "Purchase Header";
        ResponseJson: JsonObject;
    begin
        PreparePurchaseOrder(Location, Item, PurchaseHeader, true, false, false);

        Run(PurchaseRequest(PurchaseHeader."No."), '', ResponseJson);

        Assert.AreEqual('PreconditionFailed', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));
        Assert.AreEqual(NotReleasedNextStepTxt, TextValue(ResponseJson, 'nextStep'), 'The next step should name release or direct post.');
        Assert.AreEqual(0, CountPutaways(PurchaseHeader."No."), 'A location without put-away must not get an inventory put-away.');
    end;

    /// <summary>A missing source document is refused.</summary>
    [Test]
    procedure Create_MissingSourceDocument_IsRefused()
    var
        ResponseJson: JsonObject;
    begin
        Run('{"sourceNo":"106001"}', '', ResponseJson);

        Assert.AreEqual('MissingParameter', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));
        Assert.AreEqual('sourceDocument', TextValue(ResponseJson, 'parameter'), 'The error should name sourceDocument.');
    end;

    /// <summary>An unknown key is refused and writes nothing.</summary>
    [Test]
    procedure Create_UnknownKey_IsRefused()
    var
        Location: Record Location;
        Item: Record Item;
        PurchaseHeader: Record "Purchase Header";
        ResponseJson: JsonObject;
    begin
        PreparePurchaseOrder(Location, Item, PurchaseHeader, true, true, false);

        Run('{"sourceDocument":"Purchase Order","sourceNo":"' + PurchaseHeader."No." + '","note":"nope"}', '', ResponseJson);

        Assert.AreEqual('UnknownParameter', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));
        Assert.AreEqual('note', TextValue(ResponseJson, 'parameter'), 'The error should name the unknown key.');
        Assert.AreEqual(0, CountPutaways(PurchaseHeader."No."), 'An unknown key must not create an inventory put-away.');
    end;

    /// <summary>A source document sent as a number is refused.</summary>
    [Test]
    procedure Create_WrongSourceDocumentType_IsRefused()
    var
        ResponseJson: JsonObject;
    begin
        Run('{"sourceDocument":1,"sourceNo":"106001"}', '', ResponseJson);

        Assert.AreEqual('InvalidParameterFormat', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));
        Assert.AreEqual('sourceDocument', TextValue(ResponseJson, 'parameter'), 'The error should name sourceDocument.');
    end;

    /// <summary>An unknown document number is refused.</summary>
    [Test]
    procedure Create_UnknownSourceNo_IsRefused()
    var
        ResponseJson: JsonObject;
    begin
        Run('{"sourceDocument":"Purchase Order","sourceNo":"MISSING-PO"}', '', ResponseJson);

        Assert.AreEqual('RecordNotFound', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));
        Assert.AreEqual('sourceNo', TextValue(ResponseJson, 'parameter'), 'The error should name sourceNo.');
    end;

    /// <summary>A number and a different SystemId are refused and write nothing.</summary>
    [Test]
    procedure Create_ConflictingIdentifiers_IsRefused()
    var
        Location: Record Location;
        Item: Record Item;
        PurchaseHeader: Record "Purchase Header";
        ResponseJson: JsonObject;
    begin
        PreparePurchaseOrder(Location, Item, PurchaseHeader, true, true, false);

        Run('{"sourceDocument":"Purchase Order","sourceNo":"' + PurchaseHeader."No." + '","systemId":"00000000-0000-0000-0000-000000000099"}', '', ResponseJson);

        Assert.AreEqual('ConflictingIdentifiers', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));
        Assert.AreEqual(0, CountPutaways(PurchaseHeader."No."), 'Conflicting identifiers must not create an inventory put-away.');
    end;

    /// <summary>A second create returns the open inventory put-away and a warning.</summary>
    [Test]
    procedure Create_ExistingPutAway_ReturnsItWithWarning()
    var
        Location: Record Location;
        Item: Record Item;
        PurchaseHeader: Record "Purchase Header";
        ResponseJson: JsonObject;
        FirstNo: Text;
    begin
        PreparePurchaseOrder(Location, Item, PurchaseHeader, true, true, false);
        Run(PurchaseRequest(PurchaseHeader."No."), '', ResponseJson);
        Assert.AreEqual('Success', TextValue(ResponseJson, 'status'), ResponseText(ResponseJson));
        FirstNo := TextValue(FirstPutaway(ResponseJson), 'putawayNo');

        Run(PurchaseRequest(PurchaseHeader."No."), '', ResponseJson);

        Assert.AreEqual('Success', TextValue(ResponseJson, 'status'), ResponseText(ResponseJson));
        Assert.AreEqual(FirstNo, TextValue(FirstPutaway(ResponseJson), 'putawayNo'), 'The existing put-away should be returned.');
        Assert.AreEqual('PreconditionFailed', TextValue(FirstWarning(ResponseJson), 'code'), ResponseText(ResponseJson));
        Assert.AreEqual(ExistsNextStepTxt, TextValue(FirstWarning(ResponseJson), 'nextStep'), 'The warning should name inventory put-away post.');
        Assert.AreEqual(1, CountPutaways(PurchaseHeader."No."), 'A second create must not add another inventory put-away.');
    end;

    /// <summary>Create is disabled and returns PermissionDenied without activity write permission.</summary>
    [Test]
    [TestPermissions(TestPermissions::Restrictive)]
    procedure Create_WithoutPermission_ReturnsPermissionDenied()
    var
        TempArgument: Record "Message Argument ori" temporary;
        CreateImpl: Codeunit "Whse InvtPut Create Impl ori";
        LibraryLowerPermissions: Codeunit "Library - Lower Permissions";
        MessageTypeInterface: Interface "Msg Interface ori";
        ResponseJson: JsonObject;
    begin
        LibraryLowerPermissions.PushPermissionSetWithoutDefaults('Whse NoRead Test ori');
        LibraryLowerPermissions.AddPermissionSet('Whse Gate Test ori');
        MessageTypeInterface := Enum::"Message Type ori"::"Warehouse.InventoryPutAway.Create";
        Assert.IsFalse(MessageTypeInterface.IsEnabled(), 'Create must be disabled without activity write permission.');

        TempArgument.Init();
        TempArgument.Version := "Message Version ori"::"1.0";
        TempArgument.Insert(true);
        CreateImpl.ExecuteBifrostTask(TempArgument);
        ResponseJson := TempArgument.GetResponseJson();
        Assert.AreEqual('PermissionDenied', TextValue(ResponseJson, 'code'), 'The denial must use PermissionDenied.');
        Assert.AreEqual('Ask an administrator to assign BIFROST Whse - Full ori.', TextValue(ResponseJson, 'nextStep'), 'The next step must name the full permission set.');
    end;

    local procedure PreparePurchaseOrder(var Location: Record Location; var Item: Record Item; var PurchaseHeader: Record "Purchase Header"; ReleaseDocument: Boolean; RequirePutAway: Boolean; RequireReceive: Boolean)
    var
        Vendor: Record Vendor;
        PurchaseLine: Record "Purchase Line";
        Bin: Record Bin;
        ShipmentHelper: Codeunit "Whse Shipment Test Helper ori";
        ReleasePurchaseDocument: Codeunit "Release Purchase Document";
        BinMandatory: Boolean;
    begin
        BinMandatory := RequirePutAway and not RequireReceive;
        LibraryWarehouse.CreateLocationWMS(Location, BinMandatory, RequirePutAway, false, RequireReceive, false);
        EnsureInventoryPutAwayNos();
        ShipmentHelper.RegisterCurrentUserAsWarehouseEmployee(Location.Code);
        LibraryInventory.CreateItem(Item);
        LibraryPurchase.CreateVendor(Vendor);
        LibraryPurchase.CreatePurchHeader(PurchaseHeader, PurchaseHeader."Document Type"::Order, Vendor."No.");
        PurchaseHeader.Validate("Location Code", Location.Code);
        PurchaseHeader.Modify(true);
        LibraryPurchase.CreatePurchaseLine(PurchaseLine, PurchaseHeader, PurchaseLine.Type::Item, Item."No.", 1);
        PurchaseLine.Validate("Location Code", Location.Code);
        PurchaseLine.Validate("Direct Unit Cost", 100);
        if BinMandatory then begin
            LibraryWarehouse.CreateBin(Bin, Location.Code, 'PUT', '', '');
            PurchaseLine.Validate("Bin Code", Bin.Code);
        end;
        PurchaseLine.Modify(true);
        if not ReleaseDocument then
            exit;
        ReleasePurchaseDocument.Run(PurchaseHeader);
        PurchaseHeader.Get(PurchaseHeader."Document Type"::Order, PurchaseHeader."No.");
    end;

    local procedure EnsureInventoryPutAwayNos()
    var
        InventorySetup: Record "Inventory Setup";
    begin
        InventorySetup.Get();
        if InventorySetup."Inventory Put-away Nos." = '' then
            InventorySetup.Validate("Inventory Put-away Nos.", LibraryUtility.GetGlobalNoSeriesCode());
        if InventorySetup."Posted Invt. Put-away Nos." = '' then
            InventorySetup.Validate("Posted Invt. Put-away Nos.", LibraryUtility.GetGlobalNoSeriesCode());
        InventorySetup.Modify(true);
    end;

    local procedure PurchaseRequest(SourceNo: Code[20]): Text
    begin
        exit('{"sourceDocument":"Purchase Order","sourceNo":"' + SourceNo + '"}');
    end;

    local procedure CountPutaways(SourceNo: Code[20]): Integer
    var
        ActivityHeader: Record "Warehouse Activity Header";
    begin
        ActivityHeader.SetRange(Type, ActivityHeader.Type::"Invt. Put-away");
        ActivityHeader.SetRange("Source No.", SourceNo);
        exit(ActivityHeader.Count());
    end;

    local procedure Run(RequestText: Text; Subject: Text; var ResponseJson: JsonObject)
    var
        Helper: Codeunit "Whse Receipt Test Helper ori";
    begin
        Assert.IsTrue(Helper.RunMessage(Enum::"Message Type ori"::"Warehouse.InventoryPutAway.Create", Subject, RequestText, ResponseJson), 'The response should be JSON.');
    end;

    local procedure FirstPutaway(ResponseJson: JsonObject): JsonObject
    var
        Token: JsonToken;
        Putaways: JsonArray;
    begin
        Assert.IsTrue(ResponseJson.Get('putaways', Token), 'The response should list put-aways.');
        Putaways := Token.AsArray();
        Putaways.Get(0, Token);
        exit(Token.AsObject());
    end;

    local procedure FirstLine(PutawayJson: JsonObject): JsonObject
    var
        Token: JsonToken;
        Lines: JsonArray;
    begin
        Assert.IsTrue(PutawayJson.Get('lines', Token), 'The put-away should list lines.');
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
