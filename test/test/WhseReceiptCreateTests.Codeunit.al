namespace Origo.Bifrost.Warehouse.Test;

using Origo.Bifrost;
using Microsoft.Inventory.Item;
using Microsoft.Inventory.Location;
using Microsoft.Purchases.Document;
using Microsoft.Warehouse.Document;
using System.TestLibraries.Utilities;

/// <summary>
/// Unit tests for Warehouse.Receipt.Create message type.
/// </summary>
codeunit 97014 "Whse Receipt Create Tests ori"
{
    Subtype = Test;
    TestPermissions = Disabled;

    var
        Assert: Codeunit "Library Assert";
        Helper: Codeunit "Whse Receipt Test Helper ori";
        IsInitialized: Boolean;

    local procedure Initialize()
    begin
        if IsInitialized then exit;
        IsInitialized := true;
    end;

    [Test]
    procedure Create_PurchaseOrder_ReturnsReceiptNo()
    var
        Location: Record Location;
        Item: Record Item;
        PurchaseHeader: Record "Purchase Header";
        WhseReceiptHeader: Record "Warehouse Receipt Header";
        ResponseJson: JsonObject;
        StatusToken, ReceiptsToken, ReceiptToken, NoToken : JsonToken;
        ReceiptsArray: JsonArray;
    begin
        // [SCENARIO] Creating a Warehouse Receipt from a released Purchase Order returns the receipt number
        Initialize();
        Helper.SetupLocationAndItem(Location, Item, 0);
        Helper.CreateReleasedPurchaseOrder(PurchaseHeader, Item."No.", Location.Code, 5);

        CreateMessageWithPurchaseOrder(ResponseJson, PurchaseHeader."No.");
        Assert.IsTrue(ResponseJson.Get('status', StatusToken), 'status missing');
        Assert.AreEqual('Success', StatusToken.AsValue().AsText(), 'Status should be Success');

        Assert.IsTrue(ResponseJson.Get('receipts', ReceiptsToken), 'receipts missing');
        ReceiptsArray := ReceiptsToken.AsArray();
        Assert.AreEqual(1, ReceiptsArray.Count(), 'Expected one receipt created');

        ReceiptsArray.Get(0, ReceiptToken);
        Assert.IsTrue(ReceiptToken.AsObject().Get('no', NoToken), 'receipt no missing');
        Assert.IsTrue(WhseReceiptHeader.Get(NoToken.AsValue().AsText()), 'Warehouse Receipt Header should exist');
        Assert.AreEqual(Location.Code, WhseReceiptHeader."Location Code", 'Location Code mismatch');
    end;

    [Test]
    procedure Create_MissingSourceDocuments_ReturnsError()
    var
        RequestJson, ResponseJson : JsonObject;
        StatusToken: JsonToken;
    begin
        // [SCENARIO] Empty request returns Error
        Initialize();

        CreateMessageWithRequestJson(ResponseJson, RequestJson);
        Assert.IsTrue(ResponseJson.Get('status', StatusToken), 'status missing');
        Assert.AreEqual('Error', StatusToken.AsValue().AsText(), 'Status should be Error');
    end;

    [Test]
    procedure Create_UnsupportedSourceType_ReturnsError()
    var
        RequestJson, SourceObj : JsonObject;
        SourcesArray: JsonArray;
        ResponseJson: JsonObject;
        StatusToken: JsonToken;
    begin
        // [SCENARIO] Unsupported sourceType (e.g. SalesOrder — only return orders are inbound) returns Error
        Initialize();

        SourceObj.Add('sourceType', 'SalesOrder');
        SourceObj.Add('documentNo', 'X');
        SourcesArray.Add(SourceObj);
        RequestJson.Add('sourceDocuments', SourcesArray);

        CreateMessageWithRequestJson(ResponseJson, RequestJson);
        Assert.IsTrue(ResponseJson.Get('status', StatusToken), 'status missing');
        Assert.AreEqual('Error', StatusToken.AsValue().AsText(), 'Status should be Error');
    end;

    [Test]
    procedure Create_PurchaseOrderNotReleased_ReturnsError()
    var
        Location: Record Location;
        Item: Record Item;
        PurchaseHeader: Record "Purchase Header";
        ReopenPurchaseDocument: Codeunit "Release Purchase Document";
        ResponseJson: JsonObject;
        StatusToken: JsonToken;
    begin
        // [SCENARIO] An Open purchase order returns Error
        Initialize();
        Helper.SetupLocationAndItem(Location, Item, 0);
        Helper.CreateReleasedPurchaseOrder(PurchaseHeader, Item."No.", Location.Code, 5);
        ReopenPurchaseDocument.Reopen(PurchaseHeader);
        PurchaseHeader.Get(PurchaseHeader."Document Type"::Order, PurchaseHeader."No.");

        CreateMessageWithPurchaseOrder(ResponseJson, PurchaseHeader."No.");
        Assert.IsTrue(ResponseJson.Get('status', StatusToken), 'status missing');
        Assert.AreEqual('Error', StatusToken.AsValue().AsText(), 'Status should be Error');
    end;

    [Test]
    procedure Create_LocationCodeMismatch_ReturnsError()
    var
        Location, OtherLocation : Record Location;
        Item: Record Item;
        PurchaseHeader: Record "Purchase Header";
        RequestJson, SourceObj : JsonObject;
        SourcesArray: JsonArray;
        ResponseJson: JsonObject;
        StatusToken: JsonToken;
    begin
        // [SCENARIO] locationCode filter that doesn't match the source returns Error
        Initialize();
        Helper.SetupLocationAndItem(Location, Item, 0);
        Helper.CreateReceiveLocation(OtherLocation);
        Helper.CreateReleasedPurchaseOrder(PurchaseHeader, Item."No.", Location.Code, 5);

        SourceObj.Add('sourceType', 'PurchaseOrder');
        SourceObj.Add('documentNo', PurchaseHeader."No.");
        SourcesArray.Add(SourceObj);
        RequestJson.Add('sourceDocuments', SourcesArray);
        RequestJson.Add('locationCode', OtherLocation.Code);

        CreateMessageWithRequestJson(ResponseJson, RequestJson);
        Assert.IsTrue(ResponseJson.Get('status', StatusToken), 'status missing');
        Assert.AreEqual('Error', StatusToken.AsValue().AsText(), 'Status should be Error');
    end;

    /// <summary>A valid optional posting date is persisted on the created receipt.</summary>
    [Test]
    procedure Create_ValidPostingDate_PersistsOverride()
    var
        Location: Record Location;
        Item: Record Item;
        PurchaseHeader: Record "Purchase Header";
        WhseReceiptHeader: Record "Warehouse Receipt Header";
        RequestJson: JsonObject;
        SourceJson: JsonObject;
        ResponseJson: JsonObject;
        Sources: JsonArray;
        Receipts: JsonArray;
        Token: JsonToken;
        ReceiptToken: JsonToken;
    begin
        // PR #23 B2 | Time: explicit WorkDate ISO override | Risk: None
        // [SCENARIO] Date reader preserves a valid request override.
        Initialize();
        // [GIVEN] A released purchase order and a valid date.
        Helper.SetupLocationAndItem(Location, Item, 0);
        Helper.CreateReleasedPurchaseOrder(PurchaseHeader, Item."No.", Location.Code, 5);
        SourceJson.Add('sourceType', 'PurchaseOrder');
        SourceJson.Add('documentNo', PurchaseHeader."No.");
        Sources.Add(SourceJson);
        RequestJson.Add('sourceDocuments', Sources);
        RequestJson.Add('postingDate', Format(WorkDate(), 0, 9));
        // [WHEN] Dispatching the real creation path.
        CreateMessageWithRequestJson(ResponseJson, RequestJson);
        // [THEN] A successful receipt has the requested date.
        Assert.IsTrue(ResponseJson.Get('status', Token), 'status missing');
        Assert.AreEqual('Success', Token.AsValue().AsText(), 'Valid date must succeed');
        Assert.IsTrue(ResponseJson.Get('receipts', Token), 'receipts missing');
        Receipts := Token.AsArray();
        Assert.AreEqual(1, Receipts.Count(), 'Exactly one receipt expected');
        Receipts.Get(0, ReceiptToken);
        Assert.IsTrue(ReceiptToken.AsObject().Get('no', Token), 'no missing');
        Assert.IsTrue(WhseReceiptHeader.Get(Token.AsValue().AsText()), 'Receipt must exist');
        Assert.AreEqual(WorkDate(), WhseReceiptHeader."Posting Date", 'Posting date must match request');
    end;

    /// <summary>Invalid optional posting dates fail before creating a receipt.</summary>
    [Test]
    procedure Create_InvalidPostingDate_ReturnsErrorWithoutReceipt()
    var
        Location: Record Location;
        Item: Record Item;
        PurchaseHeader: Record "Purchase Header";
        WhseReceiptHeader: Record "Warehouse Receipt Header";
        RequestJson: JsonObject;
        SourceJson: JsonObject;
        ResponseJson: JsonObject;
        Sources: JsonArray;
        StatusToken: JsonToken;
        ErrorToken: JsonToken;
        CountBefore: Integer;
    begin
        // PR #23 B2 | Time: invalid ISO date; WorkDate unchanged | Risk: None
        // [SCENARIO] The public date reader rejects invalid input before writes.
        Initialize();
        // [GIVEN] A released order and an invalid date override.
        Helper.SetupLocationAndItem(Location, Item, 0);
        Helper.CreateReleasedPurchaseOrder(PurchaseHeader, Item."No.", Location.Code, 5);
        CountBefore := WhseReceiptHeader.Count();
        SourceJson.Add('sourceType', 'PurchaseOrder');
        SourceJson.Add('documentNo', PurchaseHeader."No.");
        Sources.Add(SourceJson);
        RequestJson.Add('sourceDocuments', Sources);
        RequestJson.Add('postingDate', '2026-02-30');
        // [WHEN] Dispatching the real message path.
        CreateMessageWithRequestJson(ResponseJson, RequestJson);
        // [THEN] A typed error and no receipt creation.
        Assert.IsTrue(ResponseJson.Get('status', StatusToken), 'status missing');
        Assert.AreEqual('Error', StatusToken.AsValue().AsText(), 'Invalid date must fail');
        Assert.IsTrue(ResponseJson.Get('error', ErrorToken), 'error missing');
        Assert.IsTrue(ErrorToken.AsValue().AsText().Contains('postingDate'), 'Error must identify postingDate');
        Assert.AreEqual(CountBefore, WhseReceiptHeader.Count(), 'Invalid date must not create receipts');
    end;

    local procedure CreateMessageWithPurchaseOrder(var ResponseJson: JsonObject; PurchaseOrderNo: Code[20])
    var
        RequestJson, SourceObj : JsonObject;
        SourcesArray: JsonArray;
    begin
        SourceObj.Add('sourceType', 'PurchaseOrder');
        SourceObj.Add('documentNo', PurchaseOrderNo);
        SourcesArray.Add(SourceObj);
        RequestJson.Add('sourceDocuments', SourcesArray);
        CreateMessageWithRequestJson(ResponseJson, RequestJson);
    end;

    local procedure CreateMessageWithRequestJson(var ResponseJson: JsonObject; RequestJson: JsonObject)
    var
        RequestText: Text;
    begin
        RequestJson.WriteTo(RequestText);

        Helper.RunMessage(Enum::"Message Type ori"::"Warehouse.Receipt.Create", '', RequestText, ResponseJson);
    end;

    /// <summary>Verifies that Warehouse.Receipt.Create is enabled when write permission is present.</summary>
    [Test]
    procedure IsEnabledWithWritePermission()
    var
        MessageTypeInterface: Interface "Msg Interface ori";
    begin
        MessageTypeInterface := Enum::"Message Type ori"::"Warehouse.Receipt.Create";
        Assert.IsTrue(MessageTypeInterface.IsEnabled(), 'Warehouse.Receipt.Create must be enabled when the caller can write Warehouse Receipt Header.');
    end;

    /// <summary>Verifies that Warehouse.Receipt.Create is disabled without write permission on Warehouse Receipt Header.</summary>
    [Test]
    [TestPermissions(TestPermissions::Restrictive)]
    procedure IsDisabledWithoutWritePermission()
    var
        LibraryLowerPermissions: Codeunit "Library - Lower Permissions";
        MessageTypeInterface: Interface "Msg Interface ori";
    begin
        LibraryLowerPermissions.PushPermissionSetWithoutDefaults('Whse NoRead Test ori');
        MessageTypeInterface := Enum::"Message Type ori"::"Warehouse.Receipt.Create";
        Assert.IsFalse(MessageTypeInterface.IsEnabled(), 'Warehouse.Receipt.Create must be disabled without write permission on Warehouse Receipt Header.');
    end;
}
