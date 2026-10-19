namespace Origo.Bifrost.Warehouse.Test;

using Microsoft.Inventory.Item;
using Microsoft.Inventory.Location;
using Microsoft.Inventory.Setup;
using Microsoft.Inventory.Tracking;
using Microsoft.Purchases.Document;
using Microsoft.Purchases.History;
using Microsoft.Purchases.Vendor;
using Microsoft.Sales.Customer;
using Microsoft.Sales.Document;
using Microsoft.Warehouse.Activity;
using Microsoft.Warehouse.InventoryDocument;
using Microsoft.Warehouse.Structure;
using Origo.Bifrost;
using Origo.Bifrost.Warehouse;
using System.TestLibraries.Utilities;

/// <summary>
/// Tests Warehouse.InventoryPutAway.Post through the public dispatcher and the permission denial path.
/// </summary>
codeunit 97088 "Whse InvtPut Post Tests ori"
{
    Subtype = Test;
    TestPermissions = Disabled;

    var
        Assert: Codeunit "Library Assert";
        LibraryInventory: Codeunit "Library - Inventory";
        LibraryItemTracking: Codeunit "Library - Item Tracking";
        LibraryPurchase: Codeunit "Library - Purchase";
        LibrarySales: Codeunit "Library - Sales";
        LibraryUtility: Codeunit "Library - Utility";
        LibraryWarehouse: Codeunit "Library - Warehouse";
        ShortNextStepTxt: Label 'Lower qtyToHandle to the outstanding quantity.', Locked = true;
        BinNextStepTxt: Label 'Read Warehouse.Bin.Get for valid bins.', Locked = true;

    /// <summary>Posting an inventory put-away receives the purchase order and removes the open put-away.</summary>
    [Test]
    procedure Post_PurchasePutAway_ReceivesTheOrder()
    var
        Location: Record Location;
        Item: Record Item;
        PurchaseHeader: Record "Purchase Header";
        ActivityHeader: Record "Warehouse Activity Header";
        PostedHeader: Record "Posted Invt. Put-away Header";
        PurchRcptHeader: Record "Purch. Rcpt. Header";
        ResponseJson: JsonObject;
        PutawayNo: Code[20];
    begin
        PutawayNo := CreatePurchasePutAway(Location, Item, PurchaseHeader, false);

        Run('{"putawayNo":"' + PutawayNo + '","invoice":false}', '', ResponseJson);

        Assert.AreEqual('Success', TextValue(ResponseJson, 'status'), ResponseText(ResponseJson));
        Assert.AreEqual(PutawayNo, TextValue(ResponseJson, 'putawayNo'), 'The posted response should name the put-away.');
        Assert.AreNotEqual('', TextValue(ResponseJson, 'postedPutawayNo'), 'A posted inventory put-away number should be returned.');
        Assert.AreNotEqual('', TextValue(ResponseJson, 'postedDocumentNo'), 'A posted receipt number should be returned.');
        Assert.IsFalse(ActivityHeader.Get(ActivityHeader.Type::"Invt. Put-away", PutawayNo), 'The open inventory put-away should be gone.');
        PostedHeader.SetRange("Invt. Put-away No.", PutawayNo);
        Assert.IsTrue(PostedHeader.FindLast(), 'The posted inventory put-away should exist.');
        Assert.AreEqual(TextValue(ResponseJson, 'postedPutawayNo'), PostedHeader."No.", 'The posted put-away number should match the response.');
        PurchRcptHeader.SetRange("Order No.", PurchaseHeader."No.");
        Assert.IsTrue(PurchRcptHeader.FindLast(), 'The purchase order should have a receipt.');
        Assert.AreEqual(TextValue(ResponseJson, 'postedDocumentNo'), PurchRcptHeader."No.", 'The receipt number should match the response.');
    end;

    /// <summary>A quantity above outstanding is refused and the put-away stays open.</summary>
    [Test]
    procedure Post_QuantityAboveOutstanding_IsRefused()
    var
        Location: Record Location;
        Item: Record Item;
        PurchaseHeader: Record "Purchase Header";
        ActivityHeader: Record "Warehouse Activity Header";
        PurchRcptHeader: Record "Purch. Rcpt. Header";
        ResponseJson: JsonObject;
        PutawayNo: Code[20];
        LineNo: Integer;
    begin
        PutawayNo := CreatePurchasePutAway(Location, Item, PurchaseHeader, false);
        LineNo := FirstLineNo(PutawayNo);

        Run('{"putawayNo":"' + PutawayNo + '","lines":[{"lineNo":' + Format(LineNo) + ',"qtyToHandle":99}]}', '', ResponseJson);

        Assert.AreEqual('InvalidLine', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));
        Assert.AreEqual(ShortNextStepTxt, TextValue(ResponseJson, 'nextStep'), 'The next step should name the outstanding quantity.');
        Assert.IsTrue(ActivityHeader.Get(ActivityHeader.Type::"Invt. Put-away", PutawayNo), 'The inventory put-away should stay open.');
        PurchRcptHeader.SetRange("Order No.", PurchaseHeader."No.");
        Assert.AreEqual(0, PurchRcptHeader.Count(), 'A short quantity must not receive the order.');
    end;

    /// <summary>A bin that is blocked for inbound movement is refused and nothing is posted.</summary>
    [Test]
    procedure Post_BlockedBin_IsRefused()
    var
        Location: Record Location;
        Item: Record Item;
        PurchaseHeader: Record "Purchase Header";
        Bin: Record Bin;
        ActivityHeader: Record "Warehouse Activity Header";
        ResponseJson: JsonObject;
        PutawayNo: Code[20];
        LineNo: Integer;
    begin
        PutawayNo := CreatePurchasePutAway(Location, Item, PurchaseHeader, false);
        LineNo := FirstLineNo(PutawayNo);
        LibraryWarehouse.CreateBin(Bin, Location.Code, 'BLOCK', '', '');
        Bin.Validate("Block Movement", Bin."Block Movement"::Inbound);
        Bin.Modify(true);

        Run('{"putawayNo":"' + PutawayNo + '","lines":[{"lineNo":' + Format(LineNo) + ',"qtyToHandle":1,"binCode":"BLOCK"}]}', '', ResponseJson);

        Assert.AreEqual('InvalidLine', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));
        Assert.AreEqual(BinNextStepTxt, TextValue(ResponseJson, 'nextStep'), 'The next step should name Warehouse.Bin.Get.');
        Assert.IsTrue(ActivityHeader.Get(ActivityHeader.Type::"Invt. Put-away", PutawayNo), 'The inventory put-away should stay open.');
    end;

    /// <summary>A tracked item without a lot number is refused with the line number and nothing is posted.</summary>
    [Test]
    procedure Post_TrackedItemWithoutLot_IsRefused()
    var
        Location: Record Location;
        Item: Record Item;
        PurchaseHeader: Record "Purchase Header";
        ActivityHeader: Record "Warehouse Activity Header";
        PurchRcptHeader: Record "Purch. Rcpt. Header";
        ResponseJson: JsonObject;
        PutawayNo: Code[20];
        LineNo: Integer;
    begin
        PutawayNo := CreatePurchasePutAway(Location, Item, PurchaseHeader, true);
        LineNo := FirstLineNo(PutawayNo);

        Run('{"putawayNo":"' + PutawayNo + '"}', '', ResponseJson);

        Assert.AreEqual('InvalidLine', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));
        Assert.IsTrue(StrPos(ResponseText(ResponseJson), Format(LineNo)) > 0, 'The refusal should name the line number.');
        Assert.IsTrue(ActivityHeader.Get(ActivityHeader.Type::"Invt. Put-away", PutawayNo), 'The inventory put-away should stay open.');
        PurchRcptHeader.SetRange("Order No.", PurchaseHeader."No.");
        Assert.AreEqual(0, PurchRcptHeader.Count(), 'A missing lot must not receive the order.');
    end;

    /// <summary>invoice true on a sales return is refused before anything is posted.</summary>
    [Test]
    procedure Post_InvoiceOnSalesReturn_IsRefused()
    var
        Location: Record Location;
        Item: Record Item;
        SalesHeader: Record "Sales Header";
        ActivityHeader: Record "Warehouse Activity Header";
        ResponseJson: JsonObject;
        PutawayNo: Code[20];
    begin
        PutawayNo := CreateSalesReturnPutAway(Location, Item, SalesHeader);

        Run('{"putawayNo":"' + PutawayNo + '","invoice":true}', '', ResponseJson);

        Assert.AreEqual('InvalidParameter', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));
        Assert.AreEqual('invoice', TextValue(ResponseJson, 'parameter'), 'The error should name invoice.');
        Assert.IsTrue(ActivityHeader.Get(ActivityHeader.Type::"Invt. Put-away", PutawayNo), 'The inventory put-away should stay open.');
    end;

    /// <summary>A missing put-away identifier is refused.</summary>
    [Test]
    procedure Post_MissingIdentifier_IsRefused()
    var
        ResponseJson: JsonObject;
    begin
        Run('{}', '', ResponseJson);

        Assert.AreEqual('MissingParameter', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));
        Assert.AreEqual('putawayNo', TextValue(ResponseJson, 'parameter'), 'The error should name putawayNo.');
    end;

    /// <summary>An unknown key is refused and writes nothing.</summary>
    [Test]
    procedure Post_UnknownKey_IsRefused()
    var
        Location: Record Location;
        Item: Record Item;
        PurchaseHeader: Record "Purchase Header";
        ActivityHeader: Record "Warehouse Activity Header";
        ResponseJson: JsonObject;
        PutawayNo: Code[20];
    begin
        PutawayNo := CreatePurchasePutAway(Location, Item, PurchaseHeader, false);

        Run('{"putawayNo":"' + PutawayNo + '","note":"nope"}', '', ResponseJson);

        Assert.AreEqual('UnknownParameter', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));
        Assert.AreEqual('note', TextValue(ResponseJson, 'parameter'), 'The error should name the unknown key.');
        Assert.IsTrue(ActivityHeader.Get(ActivityHeader.Type::"Invt. Put-away", PutawayNo), 'An unknown key must leave the put-away open.');
    end;

    /// <summary>Post is disabled and returns PermissionDenied without activity write permission.</summary>
    [Test]
    [TestPermissions(TestPermissions::Restrictive)]
    procedure Post_WithoutPermission_ReturnsPermissionDenied()
    var
        TempArgument: Record "Message Argument ori";
        PostImpl: Codeunit "Whse InvtPut Post Impl ori";
        LibraryLowerPermissions: Codeunit "Library - Lower Permissions";
        MessageTypeInterface: Interface "Msg Interface ori";
        ResponseJson: JsonObject;
    begin
        // Whse Gate Test ori would grant the activity tables, so the posting gate and not the missing write would refuse.
        LibraryLowerPermissions.PushPermissionSetWithoutDefaults('Whse NoRead Test ori');
        MessageTypeInterface := Enum::"Message Type ori"::"Warehouse.InventoryPutAway.Post";
        Assert.IsFalse(MessageTypeInterface.IsEnabled(), 'Post must be disabled without activity write permission.');

        TempArgument.Init();
        TempArgument.Version := "Message Version ori"::"1.0";
        TempArgument.Insert(true);
        PostImpl.ExecuteBifrostTask(TempArgument);
        ResponseJson := TempArgument.GetResponseJson();
        Assert.AreEqual('PermissionDenied', TextValue(ResponseJson, 'code'), 'The denial must use PermissionDenied.');
        Assert.AreEqual('Ask an administrator to assign BIFROST Whse - Full ori.', TextValue(ResponseJson, 'nextStep'), 'The next step must name the full permission set.');
    end;

    local procedure CreatePurchasePutAway(var Location: Record Location; var Item: Record Item; var PurchaseHeader: Record "Purchase Header"; Tracked: Boolean): Code[20]
    var
        Vendor: Record Vendor;
        PurchaseLine: Record "Purchase Line";
        Bin: Record Bin;
        ItemTrackingCode: Record "Item Tracking Code";
        ShipmentHelper: Codeunit "Whse Shipment Test Helper ori";
        ReleasePurchaseDocument: Codeunit "Release Purchase Document";
        ResponseJson: JsonObject;
    begin
        LibraryWarehouse.CreateLocationWMS(Location, true, true, false, false, false);
        EnsureInventoryPutAwayNos();
        ShipmentHelper.RegisterCurrentUserAsWarehouseEmployee(Location.Code);
        if Tracked then begin
            LibraryItemTracking.CreateItemTrackingCode(ItemTrackingCode, false, true);
            LibraryItemTracking.CreateItemWithItemTrackingCode(Item, ItemTrackingCode);
        end else
            LibraryInventory.CreateItem(Item);
        LibraryWarehouse.CreateBin(Bin, Location.Code, 'PUT', '', '');
        LibraryPurchase.CreateVendor(Vendor);
        LibraryPurchase.CreatePurchHeader(PurchaseHeader, PurchaseHeader."Document Type"::Order, Vendor."No.");
        PurchaseHeader.Validate("Location Code", Location.Code);
        PurchaseHeader.Modify(true);
        LibraryPurchase.CreatePurchaseLine(PurchaseLine, PurchaseHeader, PurchaseLine.Type::Item, Item."No.", 1);
        PurchaseLine.Validate("Location Code", Location.Code);
        PurchaseLine.Validate("Direct Unit Cost", 100);
        PurchaseLine.Validate("Bin Code", Bin.Code);
        PurchaseLine.Modify(true);
        ReleasePurchaseDocument.Run(PurchaseHeader);
        RunCreate('{"sourceDocument":"Purchase Order","sourceNo":"' + PurchaseHeader."No." + '"}', ResponseJson);
        Assert.AreEqual('Success', TextValue(ResponseJson, 'status'), ResponseText(ResponseJson));
        exit(CopyStr(TextValue(FirstPutaway(ResponseJson), 'putawayNo'), 1, 20));
    end;

    local procedure CreateSalesReturnPutAway(var Location: Record Location; var Item: Record Item; var SalesHeader: Record "Sales Header"): Code[20]
    var
        Customer: Record Customer;
        SalesLine: Record "Sales Line";
        Bin: Record Bin;
        ShipmentHelper: Codeunit "Whse Shipment Test Helper ori";
        ReleaseSalesDocument: Codeunit "Release Sales Document";
        ResponseJson: JsonObject;
    begin
        LibraryWarehouse.CreateLocationWMS(Location, true, true, false, false, false);
        EnsureInventoryPutAwayNos();
        ShipmentHelper.RegisterCurrentUserAsWarehouseEmployee(Location.Code);
        LibraryInventory.CreateItem(Item);
        LibraryWarehouse.CreateBin(Bin, Location.Code, 'RET', '', '');
        LibrarySales.CreateCustomer(Customer);
        LibrarySales.CreateSalesHeader(SalesHeader, SalesHeader."Document Type"::"Return Order", Customer."No.");
        SalesHeader.Validate("Location Code", Location.Code);
        SalesHeader.Modify(true);
        LibrarySales.CreateSalesLine(SalesLine, SalesHeader, SalesLine.Type::Item, Item."No.", 1);
        SalesLine.Validate("Location Code", Location.Code);
        SalesLine.Validate("Unit Price", 100);
        SalesLine.Validate("Bin Code", Bin.Code);
        SalesLine.Modify(true);
        ReleaseSalesDocument.Run(SalesHeader);
        RunCreate('{"sourceDocument":"Sales Return Order","sourceNo":"' + SalesHeader."No." + '"}', ResponseJson);
        Assert.AreEqual('Success', TextValue(ResponseJson, 'status'), ResponseText(ResponseJson));
        exit(CopyStr(TextValue(FirstPutaway(ResponseJson), 'putawayNo'), 1, 20));
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

    local procedure FirstLineNo(PutawayNo: Code[20]): Integer
    var
        ActivityLine: Record "Warehouse Activity Line";
    begin
        ActivityLine.SetRange("Activity Type", ActivityLine."Activity Type"::"Invt. Put-away");
        ActivityLine.SetRange("No.", PutawayNo);
        ActivityLine.FindFirst();
        exit(ActivityLine."Line No.");
    end;

    local procedure RunCreate(RequestText: Text; var ResponseJson: JsonObject)
    var
        Helper: Codeunit "Whse Receipt Test Helper ori";
    begin
        Assert.IsTrue(Helper.RunMessage(Enum::"Message Type ori"::"Warehouse.InventoryPutAway.Create", '', RequestText, ResponseJson), 'The create response should be JSON.');
    end;

    local procedure Run(RequestText: Text; Subject: Text; var ResponseJson: JsonObject)
    var
        Helper: Codeunit "Whse Receipt Test Helper ori";
    begin
        Assert.IsTrue(Helper.RunMessage(Enum::"Message Type ori"::"Warehouse.InventoryPutAway.Post", Subject, RequestText, ResponseJson), 'The response should be JSON.');
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
}
