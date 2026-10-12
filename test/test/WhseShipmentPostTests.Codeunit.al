namespace Origo.Bifrost.Warehouse.Test;

using Origo.Bifrost;
using Microsoft.Inventory.Item;
using Microsoft.Inventory.Location;
using Microsoft.Sales.Document;
using Microsoft.Warehouse.Document;
using System.TestLibraries.Utilities;

/// <summary>
/// Unit tests for Warehouse.Shipment.Post message type.
/// </summary>
codeunit 97012 "Whse Shipment Post Tests ori"
{
    Subtype = Test;
    TestPermissions = Disabled;

    var
        Assert: Codeunit "Library Assert";
        Helper: Codeunit "Whse Shipment Test Helper ori";
        IsInitialized: Boolean;

    local procedure Initialize()
    begin
        if IsInitialized then exit;
        IsInitialized := true;
    end;

    [Test]
    procedure Post_Ship_ReturnsPostedWhseShipmentNo()
    var
        Location: Record Location;
        Item: Record Item;
        SalesHeader: Record "Sales Header";
        WhseShipmentHeader: Record "Warehouse Shipment Header";
        ResponseJson: JsonObject;
        StatusToken, PostedNoToken : JsonToken;
    begin
        // [SCENARIO] Posting (ship only) returns postedWhseShipmentNo
        Initialize();
        Helper.SetupLocationAndItem(Location, Item, 100);
        Helper.CreateReleasedSalesOrder(SalesHeader, Item."No.", Location.Code, 5);
        Helper.CreateWhseShipmentFromSalesOrder(WhseShipmentHeader, SalesHeader);

        CreateMessage(ResponseJson, WhseShipmentHeader."No.", false);
        Assert.IsTrue(ResponseJson.Get('status', StatusToken), 'status missing');
        Assert.AreEqual('Success', StatusToken.AsValue().AsText(), 'Status should be Success');
        Assert.IsTrue(ResponseJson.Get('postedWhseShipmentNo', PostedNoToken), 'postedWhseShipmentNo missing');
        Assert.AreNotEqual('', PostedNoToken.AsValue().AsText(), 'postedWhseShipmentNo should be populated');
    end;

    [Test]
    procedure Post_ShipAndInvoice_ReturnsSuccess()
    var
        Location: Record Location;
        Item: Record Item;
        SalesHeader: Record "Sales Header";
        WhseShipmentHeader: Record "Warehouse Shipment Header";
        ResponseJson: JsonObject;
        StatusToken, InvoiceToken : JsonToken;
    begin
        // [SCENARIO] Posting with invoice = true returns Success and echoes invoice flag
        Initialize();
        Helper.SetupLocationAndItem(Location, Item, 100);
        Helper.CreateReleasedSalesOrder(SalesHeader, Item."No.", Location.Code, 5);
        Helper.CreateWhseShipmentFromSalesOrder(WhseShipmentHeader, SalesHeader);

        CreateMessage(ResponseJson, WhseShipmentHeader."No.", true);
        Assert.IsTrue(ResponseJson.Get('status', StatusToken), 'status missing');
        Assert.AreEqual('Success', StatusToken.AsValue().AsText(), 'Status should be Success');
        Assert.IsTrue(ResponseJson.Get('invoice', InvoiceToken), 'invoice missing');
        Assert.IsTrue(InvoiceToken.AsValue().AsBoolean(), 'invoice flag should be true');
    end;

    [Test]
    procedure Post_MissingShipment_ReturnsError()
    var
        ResponseJson: JsonObject;
        StatusToken: JsonToken;
    begin
        // [SCENARIO] Posting with no shipment identifier returns Error
        Initialize();

        CreateMessage(ResponseJson, '', false);
        Assert.IsTrue(ResponseJson.Get('status', StatusToken), 'status missing');
        Assert.AreEqual('Error', StatusToken.AsValue().AsText(), 'Status should be Error');
    end;

    /// <summary>An invalid invoice value must not post the shipment.</summary>
    [Test]
    procedure Post_InvalidInvoice_ReturnsErrorWithoutPosting()
    var
        Location: Record Location;
        Item: Record Item;
        SalesHeader: Record "Sales Header";
        WhseShipmentHeader: Record "Warehouse Shipment Header";
        ResponseJson: JsonObject;
        StatusToken: JsonToken;
        ErrorToken: JsonToken;
    begin
        // PR #23 B2 | Time: helper uses WorkDate | Risk: None
        // [SCENARIO] Typed Boolean validation rejects a numeric invoice.
        Initialize();
        // [GIVEN] A postable shipment.
        Helper.SetupLocationAndItem(Location, Item, 100);
        Helper.CreateReleasedSalesOrder(SalesHeader, Item."No.", Location.Code, 5);
        Helper.CreateWhseShipmentFromSalesOrder(WhseShipmentHeader, SalesHeader);
        // [WHEN] Dispatching invalid JSON through the real message path.
        Assert.IsTrue(Helper.RunMessage(Enum::"Message Type ori"::"Warehouse.Shipment.Post", WhseShipmentHeader."No.", '{"invoice":123}', ResponseJson), 'Response should parse');
        // [THEN] Error identifies invoice and shipment remains unposted.
        Assert.IsTrue(ResponseJson.Get('status', StatusToken), 'status missing');
        Assert.AreEqual('Error', StatusToken.AsValue().AsText(), 'Invalid Boolean must fail');
        Assert.IsTrue(ResponseJson.Get('error', ErrorToken), 'error missing');
        Assert.IsTrue(ErrorToken.AsValue().AsText().Contains('invoice'), 'Error must identify invoice');
        Assert.IsTrue(WhseShipmentHeader.Get(WhseShipmentHeader."No."), 'Invalid invoice must not consume shipment');
    end;

    local procedure CreateMessage(var ResponseJson: JsonObject; WhseShipmentNo: Code[20]; Invoice: Boolean)
    var
        RequestJson: JsonObject;
        RequestText: Text;
    begin
        RequestJson.Add('invoice', Invoice);
        RequestJson.WriteTo(RequestText);

        Helper.RunMessage(Enum::"Message Type ori"::"Warehouse.Shipment.Post", WhseShipmentNo, RequestText, ResponseJson);
    end;

    /// <summary>Verifies that Warehouse.Shipment.Post is enabled when write permission is present.</summary>
    [Test]
    procedure IsEnabledWithWritePermission()
    var
        MessageTypeInterface: Interface "Msg Interface ori";
    begin
        MessageTypeInterface := Enum::"Message Type ori"::"Warehouse.Shipment.Post";
        Assert.IsTrue(MessageTypeInterface.IsEnabled(), 'Warehouse.Shipment.Post must be enabled when the caller can write Warehouse Shipment Header.');
    end;

    /// <summary>Verifies that Warehouse.Shipment.Post is disabled without write permission on Warehouse Shipment Header.</summary>
    [Test]
    [TestPermissions(TestPermissions::Restrictive)]
    procedure IsDisabledWithoutWritePermission()
    var
        LibraryLowerPermissions: Codeunit "Library - Lower Permissions";
        MessageTypeInterface: Interface "Msg Interface ori";
    begin
        LibraryLowerPermissions.PushPermissionSetWithoutDefaults('Whse NoRead Test ori');
        MessageTypeInterface := Enum::"Message Type ori"::"Warehouse.Shipment.Post";
        Assert.IsFalse(MessageTypeInterface.IsEnabled(), 'Warehouse.Shipment.Post must be disabled without write permission on Warehouse Shipment Header.');
    end;
}
