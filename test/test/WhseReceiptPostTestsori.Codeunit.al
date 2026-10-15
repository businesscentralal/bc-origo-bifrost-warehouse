namespace Origo.Bifrost.Warehouse.Test;

using Origo.Bifrost;
using Microsoft.Inventory.Item;
using Microsoft.Inventory.Location;
using Microsoft.Purchases.Document;
using Microsoft.Warehouse.Document;
using System.TestLibraries.Utilities;

/// <summary>
/// Unit tests for Warehouse.Receipt.Post message type.
/// </summary>
codeunit 97015 "Whse Receipt Post Tests ori"
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
    procedure Post_PurchaseReceipt_ReturnsPostedWhseReceiptNo()
    var
        Location: Record Location;
        Item: Record Item;
        PurchaseHeader: Record "Purchase Header";
        WhseReceiptHeader: Record "Warehouse Receipt Header";
        ResponseJson: JsonObject;
        StatusToken, PostedNoToken : JsonToken;
    begin
        // [SCENARIO] Posting a Warehouse Receipt for a Purchase Order returns postedWhseReceiptNo
        Initialize();
        Helper.SetupLocationAndItem(Location, Item, 0);
        Helper.CreateReleasedPurchaseOrder(PurchaseHeader, Item."No.", Location.Code, 5);
        Helper.CreateWhseReceiptFromPurchaseOrder(WhseReceiptHeader, PurchaseHeader);

        CreateMessage(ResponseJson, WhseReceiptHeader."No.");
        Assert.IsTrue(ResponseJson.Get('status', StatusToken), 'status missing');
        Assert.AreEqual('Success', StatusToken.AsValue().AsText(), 'Status should be Success');
        Assert.IsTrue(ResponseJson.Get('postedWhseReceiptNo', PostedNoToken), 'postedWhseReceiptNo missing');
        Assert.AreNotEqual('', PostedNoToken.AsValue().AsText(), 'postedWhseReceiptNo should be populated');
    end;

    [Test]
    procedure Post_MissingReceipt_ReturnsError()
    var
        ResponseJson: JsonObject;
        StatusToken: JsonToken;
    begin
        // [SCENARIO] Posting with no receipt identifier returns Error
        Initialize();

        CreateMessage(ResponseJson, '');
        Assert.IsTrue(ResponseJson.Get('status', StatusToken), 'status missing');
        Assert.AreEqual('Error', StatusToken.AsValue().AsText(), 'Status should be Error');
    end;

    [Test]
    procedure Post_ReturnsEchoedReceiptNo()
    var
        Location: Record Location;
        Item: Record Item;
        PurchaseHeader: Record "Purchase Header";
        WhseReceiptHeader: Record "Warehouse Receipt Header";
        ResponseJson: JsonObject;
        ReceiptNoToken: JsonToken;
    begin
        // [SCENARIO] Response echoes the source receiptNo for traceability
        Initialize();
        Helper.SetupLocationAndItem(Location, Item, 0);
        Helper.CreateReleasedPurchaseOrder(PurchaseHeader, Item."No.", Location.Code, 3);
        Helper.CreateWhseReceiptFromPurchaseOrder(WhseReceiptHeader, PurchaseHeader);

        CreateMessage(ResponseJson, WhseReceiptHeader."No.");
        Assert.IsTrue(ResponseJson.Get('receiptNo', ReceiptNoToken), 'receiptNo missing');
        Assert.AreEqual(WhseReceiptHeader."No.", ReceiptNoToken.AsValue().AsText(), 'Echoed receiptNo mismatch');
    end;

    local procedure CreateMessage(var ResponseJson: JsonObject; WhseReceiptNo: Code[20])
    var
        RequestJson: JsonObject;
        RequestText: Text;
    begin
        RequestJson.WriteTo(RequestText);

        Helper.RunMessage(Enum::"Message Type ori"::"Warehouse.Receipt.Post", WhseReceiptNo, RequestText, ResponseJson);
    end;

    /// <summary>Verifies that Warehouse.Receipt.Post is enabled when write permission is present.</summary>
    [Test]
    procedure IsEnabledWithWritePermission()
    var
        MessageTypeInterface: Interface "Msg Interface ori";
    begin
        MessageTypeInterface := Enum::"Message Type ori"::"Warehouse.Receipt.Post";
        Assert.IsTrue(MessageTypeInterface.IsEnabled(), 'Warehouse.Receipt.Post must be enabled when the caller can write Warehouse Receipt Header.');
    end;

    /// <summary>Verifies that Warehouse.Receipt.Post is disabled without write permission on Warehouse Receipt Header.</summary>
    [Test]
    [TestPermissions(TestPermissions::Restrictive)]
    procedure IsDisabledWithoutWritePermission()
    var
        LibraryLowerPermissions: Codeunit "Library - Lower Permissions";
        MessageTypeInterface: Interface "Msg Interface ori";
    begin
        LibraryLowerPermissions.PushPermissionSetWithoutDefaults('Whse NoRead Test ori');
        MessageTypeInterface := Enum::"Message Type ori"::"Warehouse.Receipt.Post";
        Assert.IsFalse(MessageTypeInterface.IsEnabled(), 'Warehouse.Receipt.Post must be disabled without write permission on Warehouse Receipt Header.');
    end;
}
