namespace Origo.Bifrost.Warehouse.Test;

using Microsoft.Inventory.Item;
using Microsoft.Inventory.Location;
using Microsoft.Inventory.Setup;
using Microsoft.Purchases.Document;
using Microsoft.Purchases.Vendor;
using Microsoft.Sales.Customer;
using Microsoft.Sales.Document;
using Microsoft.Sales.History;
using Microsoft.Warehouse.Activity;
using Microsoft.Warehouse.InventoryDocument;
using Origo.Bifrost;
using Origo.Bifrost.Warehouse;
using System.TestLibraries.Utilities;

/// <summary>
/// Tests Warehouse.InventoryPick.Post through the public dispatcher and the permission denial path.
/// </summary>
codeunit 97086 "Whse InvtPick Post Tests ori"
{
    Subtype = Test;
    TestPermissions = Disabled;

    var
        Assert: Codeunit "Library Assert";
        LibraryInventory: Codeunit "Library - Inventory";
        LibraryPurchase: Codeunit "Library - Purchase";
        LibrarySales: Codeunit "Library - Sales";
        LibraryUtility: Codeunit "Library - Utility";
        LibraryWarehouse: Codeunit "Library - Warehouse";
        ShortNextStepTxt: Label 'Lower qtyToHandle; read Warehouse.BinContent.Get.', Locked = true;

    /// <summary>Posting an inventory pick ships the sales order and removes the open pick.</summary>
    [Test]
    procedure Post_SalesPick_ShipsTheOrder()
    var
        Location: Record Location;
        Item: Record Item;
        SalesHeader: Record "Sales Header";
        ActivityHeader: Record "Warehouse Activity Header";
        PostedHeader: Record "Posted Invt. Pick Header";
        SalesShipmentHeader: Record "Sales Shipment Header";
        ResponseJson: JsonObject;
        PickNo: Code[20];
    begin
        PickNo := CreateSalesPick(Location, Item, SalesHeader);

        Run('{"pickNo":"' + PickNo + '","invoice":false}', '', ResponseJson);

        Assert.AreEqual('Success', TextValue(ResponseJson, 'status'), ResponseText(ResponseJson));
        Assert.AreEqual(PickNo, TextValue(ResponseJson, 'pickNo'), 'The posted response should name the pick.');
        Assert.AreNotEqual('', TextValue(ResponseJson, 'postedPickNo'), 'A posted inventory pick number should be returned.');
        Assert.AreNotEqual('', TextValue(ResponseJson, 'postedDocumentNo'), 'A posted shipment number should be returned.');
        Assert.IsFalse(ActivityHeader.Get(ActivityHeader.Type::"Invt. Pick", PickNo), 'The open inventory pick should be gone.');
        PostedHeader.SetRange("Invt Pick No.", PickNo);
        Assert.IsTrue(PostedHeader.FindLast(), 'The posted inventory pick should exist.');
        Assert.AreEqual(TextValue(ResponseJson, 'postedPickNo'), PostedHeader."No.", 'The posted pick number should match the response.');
        SalesShipmentHeader.SetRange("Order No.", SalesHeader."No.");
        Assert.IsTrue(SalesShipmentHeader.FindLast(), 'The sales order should have a shipment.');
        Assert.AreEqual(TextValue(ResponseJson, 'postedDocumentNo'), SalesShipmentHeader."No.", 'The shipment number should match the response.');
    end;

    /// <summary>A quantity above outstanding is refused and the pick stays open.</summary>
    [Test]
    procedure Post_QuantityAboveOutstanding_IsRefused()
    var
        Location: Record Location;
        Item: Record Item;
        SalesHeader: Record "Sales Header";
        ActivityHeader: Record "Warehouse Activity Header";
        SalesShipmentHeader: Record "Sales Shipment Header";
        ResponseJson: JsonObject;
        PickNo: Code[20];
        LineNo: Integer;
    begin
        PickNo := CreateSalesPick(Location, Item, SalesHeader);
        LineNo := FirstLineNo(PickNo);

        Run('{"pickNo":"' + PickNo + '","lines":[{"lineNo":' + Format(LineNo) + ',"qtyToHandle":99}]}', '', ResponseJson);

        Assert.AreEqual('InvalidLine', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));
        Assert.AreEqual(ShortNextStepTxt, TextValue(ResponseJson, 'nextStep'), 'The next step should name BinContent.Get.');
        Assert.IsTrue(ActivityHeader.Get(ActivityHeader.Type::"Invt. Pick", PickNo), 'The inventory pick should stay open.');
        SalesShipmentHeader.SetRange("Order No.", SalesHeader."No.");
        Assert.AreEqual(0, SalesShipmentHeader.Count(), 'A short quantity must not ship the order.');
    end;

    /// <summary>Zero quantity to handle on every line is refused and nothing is shipped.</summary>
    [Test]
    procedure Post_ZeroQuantity_IsRefused()
    var
        Location: Record Location;
        Item: Record Item;
        SalesHeader: Record "Sales Header";
        ActivityHeader: Record "Warehouse Activity Header";
        SalesShipmentHeader: Record "Sales Shipment Header";
        ResponseJson: JsonObject;
        PickNo: Code[20];
        LineNo: Integer;
    begin
        PickNo := CreateSalesPick(Location, Item, SalesHeader);
        LineNo := FirstLineNo(PickNo);

        Run('{"pickNo":"' + PickNo + '","lines":[{"lineNo":' + Format(LineNo) + ',"qtyToHandle":0}]}', '', ResponseJson);

        Assert.AreEqual('PreconditionFailed', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));
        Assert.IsTrue(ActivityHeader.Get(ActivityHeader.Type::"Invt. Pick", PickNo), 'The inventory pick should stay open.');
        SalesShipmentHeader.SetRange("Order No.", SalesHeader."No.");
        Assert.AreEqual(0, SalesShipmentHeader.Count(), 'Nothing should be shipped.');
    end;

    /// <summary>invoice true on a purchase return is refused before anything is posted.</summary>
    [Test]
    procedure Post_InvoiceOnPurchaseReturn_IsRefused()
    var
        Location: Record Location;
        Item: Record Item;
        PurchaseHeader: Record "Purchase Header";
        ActivityHeader: Record "Warehouse Activity Header";
        ResponseJson: JsonObject;
        PickNo: Code[20];
    begin
        PickNo := CreatePurchaseReturnPick(Location, Item, PurchaseHeader);

        Run('{"pickNo":"' + PickNo + '","invoice":true}', '', ResponseJson);

        Assert.AreEqual('InvalidParameter', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));
        Assert.AreEqual('invoice', TextValue(ResponseJson, 'parameter'), 'The error should name invoice.');
        Assert.IsTrue(ActivityHeader.Get(ActivityHeader.Type::"Invt. Pick", PickNo), 'The inventory pick should stay open.');
    end;

    /// <summary>A missing pick identifier is refused.</summary>
    [Test]
    procedure Post_MissingIdentifier_IsRefused()
    var
        ResponseJson: JsonObject;
    begin
        Run('{}', '', ResponseJson);

        Assert.AreEqual('MissingParameter', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));
        Assert.AreEqual('pickNo', TextValue(ResponseJson, 'parameter'), 'The error should name pickNo.');
    end;

    /// <summary>An unknown key is refused and writes nothing.</summary>
    [Test]
    procedure Post_UnknownKey_IsRefused()
    var
        Location: Record Location;
        Item: Record Item;
        SalesHeader: Record "Sales Header";
        ActivityHeader: Record "Warehouse Activity Header";
        ResponseJson: JsonObject;
        PickNo: Code[20];
    begin
        PickNo := CreateSalesPick(Location, Item, SalesHeader);

        Run('{"pickNo":"' + PickNo + '","note":"nope"}', '', ResponseJson);

        Assert.AreEqual('UnknownParameter', TextValue(ResponseJson, 'code'), ResponseText(ResponseJson));
        Assert.AreEqual('note', TextValue(ResponseJson, 'parameter'), 'The error should name the unknown key.');
        Assert.IsTrue(ActivityHeader.Get(ActivityHeader.Type::"Invt. Pick", PickNo), 'An unknown key must leave the pick open.');
    end;

    /// <summary>Post is disabled and returns PermissionDenied without activity write permission.</summary>
    [Test]
    [TestPermissions(TestPermissions::Restrictive)]
    procedure Post_WithoutPermission_ReturnsPermissionDenied()
    var
        TempArgument: Record "Message Argument ori";
        PostImpl: Codeunit "Whse InvtPick Post Impl ori";
        LibraryLowerPermissions: Codeunit "Library - Lower Permissions";
        MessageTypeInterface: Interface "Msg Interface ori";
        ResponseJson: JsonObject;
    begin
        // Whse Gate Test ori would grant the activity tables, so the posting gate and not the missing write would refuse.
        LibraryLowerPermissions.PushPermissionSetWithoutDefaults('Whse NoRead Test ori');
        MessageTypeInterface := Enum::"Message Type ori"::"Warehouse.InventoryPick.Post";
        Assert.IsFalse(MessageTypeInterface.IsEnabled(), 'Post must be disabled without activity write permission.');

        TempArgument.Init();
        TempArgument.Version := "Message Version ori"::"1.0";
        TempArgument.Insert(true);
        PostImpl.ExecuteBifrostTask(TempArgument);
        ResponseJson := TempArgument.GetResponseJson();
        Assert.AreEqual('PermissionDenied', TextValue(ResponseJson, 'code'), 'The denial must use PermissionDenied.');
        Assert.AreEqual('Ask an administrator to assign BIFROST Whse - Full ori.', TextValue(ResponseJson, 'nextStep'), 'The next step must name the full permission set.');
    end;

    local procedure CreateSalesPick(var Location: Record Location; var Item: Record Item; var SalesHeader: Record "Sales Header"): Code[20]
    var
        Customer: Record Customer;
        SalesLine: Record "Sales Line";
        ShipmentHelper: Codeunit "Whse Shipment Test Helper ori";
        ReleaseSalesDocument: Codeunit "Release Sales Document";
        ResponseJson: JsonObject;
    begin
        LibraryWarehouse.CreateLocationWMS(Location, false, false, true, false, false);
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
        ReleaseSalesDocument.Run(SalesHeader);
        RunCreate('{"sourceDocument":"Sales Order","sourceNo":"' + SalesHeader."No." + '"}', ResponseJson);
        Assert.AreEqual('Success', TextValue(ResponseJson, 'status'), ResponseText(ResponseJson));
        exit(CopyStr(TextValue(FirstPick(ResponseJson), 'pickNo'), 1, 20));
    end;

    local procedure CreatePurchaseReturnPick(var Location: Record Location; var Item: Record Item; var PurchaseHeader: Record "Purchase Header"): Code[20]
    var
        Vendor: Record Vendor;
        PurchaseLine: Record "Purchase Line";
        ShipmentHelper: Codeunit "Whse Shipment Test Helper ori";
        ReleasePurchaseDocument: Codeunit "Release Purchase Document";
        ResponseJson: JsonObject;
    begin
        LibraryWarehouse.CreateLocationWMS(Location, false, false, true, false, false);
        EnsureInventoryPickNos();
        ShipmentHelper.RegisterCurrentUserAsWarehouseEmployee(Location.Code);
        LibraryInventory.CreateItem(Item);
        ShipmentHelper.CreatePositiveAdjustment(Item."No.", Location.Code, 5);
        LibraryPurchase.CreateVendor(Vendor);
        LibraryPurchase.CreatePurchHeader(PurchaseHeader, PurchaseHeader."Document Type"::"Return Order", Vendor."No.");
        PurchaseHeader.Validate("Location Code", Location.Code);
        PurchaseHeader.Modify(true);
        LibraryPurchase.CreatePurchaseLine(PurchaseLine, PurchaseHeader, PurchaseLine.Type::Item, Item."No.", 1);
        PurchaseLine.Validate("Location Code", Location.Code);
        PurchaseLine.Validate("Direct Unit Cost", 100);
        PurchaseLine.Modify(true);
        ReleasePurchaseDocument.Run(PurchaseHeader);
        RunCreate('{"sourceDocument":"Purchase Return Order","sourceNo":"' + PurchaseHeader."No." + '"}', ResponseJson);
        Assert.AreEqual('Success', TextValue(ResponseJson, 'status'), ResponseText(ResponseJson));
        exit(CopyStr(TextValue(FirstPick(ResponseJson), 'pickNo'), 1, 20));
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

    local procedure FirstLineNo(PickNo: Code[20]): Integer
    var
        ActivityLine: Record "Warehouse Activity Line";
    begin
        ActivityLine.SetRange("Activity Type", ActivityLine."Activity Type"::"Invt. Pick");
        ActivityLine.SetRange("No.", PickNo);
        ActivityLine.FindFirst();
        exit(ActivityLine."Line No.");
    end;

    local procedure RunCreate(RequestText: Text; var ResponseJson: JsonObject)
    var
        Helper: Codeunit "Whse Receipt Test Helper ori";
    begin
        Assert.IsTrue(Helper.RunMessage(Enum::"Message Type ori"::"Warehouse.InventoryPick.Create", '', RequestText, ResponseJson), 'The create response should be JSON.');
    end;

    local procedure Run(RequestText: Text; Subject: Text; var ResponseJson: JsonObject)
    var
        Helper: Codeunit "Whse Receipt Test Helper ori";
    begin
        Assert.IsTrue(Helper.RunMessage(Enum::"Message Type ori"::"Warehouse.InventoryPick.Post", Subject, RequestText, ResponseJson), 'The response should be JSON.');
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
