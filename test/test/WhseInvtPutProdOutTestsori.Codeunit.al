namespace Origo.Bifrost.Warehouse.Test;

using Microsoft.Inventory.Item;
using Microsoft.Inventory.Ledger;
using Microsoft.Inventory.Location;
using Microsoft.Inventory.Setup;
using Microsoft.Manufacturing.Document;
using Microsoft.Warehouse.Activity;
using Microsoft.Warehouse.InventoryDocument;
using Microsoft.Warehouse.Structure;
using Origo.Bifrost;
using System.TestLibraries.Utilities;

/// <summary>
/// Tests Prod. Output as a source of Warehouse.InventoryPutAway.Create and Warehouse.InventoryPutAway.Post (#111 AC04, AC05).
/// Every order, item and location is created by the test through the Microsoft test libraries.
/// </summary>
codeunit 97093 "Whse InvtPut ProdOut Tests ori"
{
    Subtype = Test;
    TestPermissions = Disabled;

    var
        Assert: Codeunit "Library Assert";
        LibraryInventory: Codeunit "Library - Inventory";
        LibraryManufacturing: Codeunit "Library - Manufacturing";
        LibraryUtility: Codeunit "Library - Utility";
        LibraryWarehouse: Codeunit "Library - Warehouse";
        NotReleasedNextStepTxt: Label 'Release the document first, or post it directly.', Locked = true;
        HandlingNextStepTxt: Label 'Set Prod. Output Whse. Handling on the location to Inventory Put-away, or post the output without warehouse handling.', Locked = true;
        OutputQty: Decimal;

    /// <summary>The output of a released production order is put away and posted; output and put-away post together.</summary>
    [Test]
    procedure CreateAndPost_ProdOutput_PostsOutputAndPutAway()
    var
        Location: Record Location;
        Item: Record Item;
        ProductionOrder: Record "Production Order";
        ActivityHeader: Record "Warehouse Activity Header";
        PostedHeader: Record "Posted Invt. Put-away Header";
        ItemLedgerEntry: Record "Item Ledger Entry";
        ResponseJson: JsonObject;
        PutawayJson: JsonObject;
        PutawayNo: Code[20];
    begin
        PrepareProductionOrder(Location, Item, ProductionOrder, true, true);

        RunCreate(OutputRequest(ProductionOrder."No."), '', ResponseJson);

        Assert.AreEqual('Success', TextValue(ResponseJson, 'status'), ResponseText(ResponseJson));
        Assert.AreEqual('Prod. Output', TextValue(ResponseJson, 'sourceDocument'), 'The source document should be returned.');
        Assert.AreEqual(ProductionOrder."No.", TextValue(ResponseJson, 'sourceNo'), 'The production order number should be returned.');
        Assert.AreEqual(1, IntegerValue(ResponseJson, 'putawayCount'), 'One inventory put-away should be created.');
        PutawayJson := FirstPutaway(ResponseJson);
        Assert.AreEqual(Item."No.", TextValue(FirstLine(PutawayJson), 'itemNo'), 'The put-away line should name the output item.');
        Assert.AreEqual('OUT', TextValue(FirstLine(PutawayJson), 'binCode'), 'The put-away line should suggest the from-production bin.');
        PutawayNo := CopyStr(TextValue(PutawayJson, 'putawayNo'), 1, MaxStrLen(PutawayNo));
        Assert.IsTrue(ActivityHeader.Get(ActivityHeader.Type::"Invt. Put-away", PutawayNo), 'The inventory put-away should exist.');
        Assert.AreEqual(ActivityHeader."Source Document"::"Prod. Output", ActivityHeader."Source Document", 'The put-away should be for production output.');

        RunPost('{"putawayNo":"' + PutawayNo + '","expectedCount":1}', ResponseJson);

        Assert.AreEqual('Success', TextValue(ResponseJson, 'status'), ResponseText(ResponseJson));
        Assert.AreEqual('Prod. Output', TextValue(ResponseJson, 'sourceDocument'), 'The posted response should name Prod. Output.');
        Assert.AreEqual('', TextValue(ResponseJson, 'postedDocumentNo'), 'Output posts entries, not a document.');
        Assert.IsFalse(ActivityHeader.Get(ActivityHeader.Type::"Invt. Put-away", PutawayNo), 'The open inventory put-away should be gone.');
        PostedHeader.SetRange("Invt. Put-away No.", PutawayNo);
        Assert.IsFalse(PostedHeader.IsEmpty(), 'A posted inventory put-away should exist.');
        ItemLedgerEntry.SetRange("Entry Type", ItemLedgerEntry."Entry Type"::Output);
        ItemLedgerEntry.SetRange("Order No.", ProductionOrder."No.");
        ItemLedgerEntry.SetRange("Item No.", Item."No.");
        ItemLedgerEntry.CalcSums(Quantity);
        Assert.AreEqual(OutputQty, ItemLedgerEntry.Quantity, 'The output should be posted with the put-away.');
    end;

    /// <summary>The source name is case- and space-insensitive, like the other sources.</summary>
    [Test]
    procedure Create_ProdOutputAlias_IsAccepted()
    var
        Location: Record Location;
        Item: Record Item;
        ProductionOrder: Record "Production Order";
        ResponseJson: JsonObject;
    begin
        PrepareProductionOrder(Location, Item, ProductionOrder, true, true);

        RunCreate('{"sourceDocument":"prod. output","sourceNo":"' + ProductionOrder."No." + '"}', '', ResponseJson);

        Assert.AreEqual('Success', TextValue(ResponseJson, 'status'), ResponseText(ResponseJson));
        Assert.AreEqual('Prod. Output', TextValue(ResponseJson, 'sourceDocument'), 'The canonical source name should be returned.');
    end;

    /// <summary>A firm planned production order is refused and gets no put-away.</summary>
    [Test]
    procedure Create_FirmPlannedOrder_IsRefused()
    var
        Location: Record Location;
        Item: Record Item;
        ProductionOrder: Record "Production Order";
        ResponseJson: JsonObject;
    begin
        PrepareProductionOrder(Location, Item, ProductionOrder, false, true);

        RunCreate(OutputRequest(ProductionOrder."No."), '', ResponseJson);

        Assert.AreEqual('PreconditionFailed', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));
        Assert.AreEqual(NotReleasedNextStepTxt, TextValue(ResponseJson, 'nextStep'), 'The next step should name release.');
        Assert.AreEqual(0, CountPutaways(ProductionOrder."No."), 'An unreleased order must not get an inventory put-away.');
    end;

    /// <summary>A location whose Prod. Output Whse. Handling is not Inventory Put-away is refused with the setting as next step.</summary>
    [Test]
    procedure Create_LocationWithoutOutputPutAway_IsRefused()
    var
        Location: Record Location;
        Item: Record Item;
        ProductionOrder: Record "Production Order";
        ResponseJson: JsonObject;
    begin
        PrepareProductionOrder(Location, Item, ProductionOrder, true, false);

        RunCreate(OutputRequest(ProductionOrder."No."), '', ResponseJson);

        Assert.AreEqual('PreconditionFailed', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));
        Assert.AreEqual(HandlingNextStepTxt, TextValue(ResponseJson, 'nextStep'), 'The next step should name the location setting.');
        Assert.AreEqual(0, CountPutaways(ProductionOrder."No."), 'A refused request must not create an inventory put-away.');
    end;

    /// <summary>An unknown production order number is refused as not found.</summary>
    [Test]
    procedure Create_UnknownProductionOrder_IsRefused()
    var
        ResponseJson: JsonObject;
        UnknownNo: Code[20];
    begin
        UnknownNo := CopyStr(LibraryUtility.GenerateGUID(), 1, MaxStrLen(UnknownNo));

        RunCreate(OutputRequest(UnknownNo), '', ResponseJson);

        Assert.AreEqual('RecordNotFound', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));
        Assert.AreEqual(0, CountPutaways(UnknownNo), 'Nothing should be created.');
    end;

    /// <summary>sourceNo and a systemId of another production order conflict and nothing is created.</summary>
    [Test]
    procedure Create_ConflictingIdentifiers_IsRefused()
    var
        Location: Record Location;
        Item: Record Item;
        ProductionOrder: Record "Production Order";
        OtherOrder: Record "Production Order";
        ResponseJson: JsonObject;
    begin
        PrepareProductionOrder(Location, Item, ProductionOrder, true, true);
        PrepareProductionOrder(Location, Item, OtherOrder, true, true);

        RunCreate('{"sourceDocument":"Prod. Output","sourceNo":"' + ProductionOrder."No." + '","systemId":"' + Format(OtherOrder.SystemId, 0, 4) + '"}', '', ResponseJson);

        Assert.AreEqual('ConflictingIdentifiers', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));
        Assert.AreEqual(0, CountPutaways(ProductionOrder."No."), 'Nothing should be created for the first order.');
        Assert.AreEqual(0, CountPutaways(OtherOrder."No."), 'Nothing should be created for the second order.');
    end;

    local procedure PrepareProductionOrder(var Location: Record Location; var Item: Record Item; var ProductionOrder: Record "Production Order"; Release: Boolean; OutputPutAway: Boolean)
    var
        Bin: Record Bin;
        FirmPlannedOrder: Record "Production Order";
        ShipmentHelper: Codeunit "Whse Shipment Test Helper ori";
    begin
        OutputQty := 2;
        LibraryWarehouse.CreateLocationWMS(Location, true, true, false, false, false);
        LibraryWarehouse.CreateBin(Bin, Location.Code, 'OUT', '', '');
        Location.Validate("From-Production Bin Code", Bin.Code);
        if OutputPutAway then
            Location.Validate("Prod. Output Whse. Handling", Location."Prod. Output Whse. Handling"::"Inventory Put-away")
        else
            Location.Validate("Prod. Output Whse. Handling", Location."Prod. Output Whse. Handling"::"No Warehouse Handling");
        Location.Modify(true);
        EnsureInventoryPutAwayNos();
        ShipmentHelper.RegisterCurrentUserAsWarehouseEmployee(Location.Code);
        LibraryInventory.CreateItem(Item);
        Item.Validate("Replenishment System", Item."Replenishment System"::"Prod. Order");
        Item.Modify(true);
        LibraryManufacturing.CreateProductionOrder(FirmPlannedOrder, FirmPlannedOrder.Status::"Firm Planned", FirmPlannedOrder."Source Type"::Item, Item."No.", OutputQty);
        FirmPlannedOrder.Validate("Location Code", Location.Code);
        FirmPlannedOrder.Modify(true);
        LibraryManufacturing.RefreshProdOrder(FirmPlannedOrder, false, true, true, true, false);
        if not Release then begin
            ProductionOrder := FirmPlannedOrder;
            ProductionOrder.Find();
            exit;
        end;
        LibraryManufacturing.ChangeProdOrderStatus(FirmPlannedOrder, FirmPlannedOrder.Status::Released, WorkDate(), false);
        ProductionOrder.SetRange(Status, ProductionOrder.Status::Released);
        ProductionOrder.SetRange("Source No.", Item."No.");
        ProductionOrder.SetRange("Location Code", Location.Code);
        ProductionOrder.FindLast();
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

    local procedure OutputRequest(SourceNo: Code[20]): Text
    begin
        exit('{"sourceDocument":"Prod. Output","sourceNo":"' + SourceNo + '"}');
    end;

    local procedure CountPutaways(SourceNo: Code[20]): Integer
    var
        ActivityHeader: Record "Warehouse Activity Header";
    begin
        ActivityHeader.SetRange(Type, ActivityHeader.Type::"Invt. Put-away");
        ActivityHeader.SetRange("Source No.", SourceNo);
        exit(ActivityHeader.Count());
    end;

    local procedure RunCreate(RequestText: Text; Subject: Text; var ResponseJson: JsonObject)
    var
        Helper: Codeunit "Whse Receipt Test Helper ori";
    begin
        Assert.IsTrue(Helper.RunMessage(Enum::"Message Type ori"::"Warehouse.InventoryPutAway.Create", Subject, RequestText, ResponseJson), 'The create response should be JSON.');
    end;

    local procedure RunPost(RequestText: Text; var ResponseJson: JsonObject)
    var
        Helper: Codeunit "Whse Receipt Test Helper ori";
    begin
        Assert.IsTrue(Helper.RunMessage(Enum::"Message Type ori"::"Warehouse.InventoryPutAway.Post", '', RequestText, ResponseJson), 'The post response should be JSON.');
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
