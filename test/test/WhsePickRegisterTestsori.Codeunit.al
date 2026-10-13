namespace Origo.Bifrost.Warehouse.Test;

using Origo.Bifrost;
using Microsoft.Inventory.Item;
using Microsoft.Inventory.Location;
using Microsoft.Sales.Document;
using Microsoft.Warehouse.Activity;
using Microsoft.Warehouse.Document;
using System.TestLibraries.Utilities;

/// <summary>
/// Unit tests for Warehouse.Pick.Register message type.
/// </summary>
codeunit 97018 "Whse Pick Register Tests ori"
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
    procedure PickRegister_HappyPath_ReturnsRegisteredPickNo()
    var
        Location: Record Location;
        Item: Record Item;
        SalesHeader: Record "Sales Header";
        WhseShipmentHeader: Record "Warehouse Shipment Header";
        WarehouseActivityHeader: Record "Warehouse Activity Header";
        ResponseJson: JsonObject;
        StatusToken, LinesToken, RegisteredNoToken : JsonToken;
    begin
        // [SCENARIO] Registering a freshly-created pick returns Success and a registeredPickNo
        Initialize();
        ArrangePickReadyForRegister(Location, Item, SalesHeader, WhseShipmentHeader, WarehouseActivityHeader);

        CreateRegisterMessage(ResponseJson, WarehouseActivityHeader."No.");
        Assert.IsTrue(ResponseJson.Get('status', StatusToken), 'status missing');
        Assert.AreEqual('Success', StatusToken.AsValue().AsText(), 'Status should be Success');
        Assert.IsTrue(ResponseJson.Get('linesRegistered', LinesToken), 'linesRegistered missing');
        Assert.IsTrue(LinesToken.AsValue().AsInteger() >= 1, 'linesRegistered should be at least 1');
        Assert.IsTrue(ResponseJson.Get('registeredPickNo', RegisteredNoToken), 'registeredPickNo missing');
        Assert.AreNotEqual('', RegisteredNoToken.AsValue().AsText(), 'registeredPickNo should be populated');
    end;

    [Test]
    procedure PickRegister_HappyPath_UpdatesShipmentLineQtyPicked()
    var
        Location: Record Location;
        Item: Record Item;
        SalesHeader: Record "Sales Header";
        WhseShipmentHeader: Record "Warehouse Shipment Header";
        WarehouseActivityHeader: Record "Warehouse Activity Header";
        WhseShipmentLine: Record "Warehouse Shipment Line";
        ResponseJson: JsonObject;
    begin
        // [SCENARIO] After register, the source Warehouse Shipment Line has Qty. Picked > 0
        Initialize();
        ArrangePickReadyForRegister(Location, Item, SalesHeader, WhseShipmentHeader, WarehouseActivityHeader);

        CreateRegisterMessage(ResponseJson, WarehouseActivityHeader."No.");

        WhseShipmentLine.SetRange("No.", WhseShipmentHeader."No.");
        WhseShipmentLine.FindFirst();
        Assert.IsTrue(WhseShipmentLine."Qty. Picked" > 0, 'Warehouse Shipment Line Qty. Picked should be > 0 after register');
    end;

    [Test]
    procedure PickRegister_ResponseIncludesShipmentLines()
    var
        Location: Record Location;
        Item: Record Item;
        SalesHeader: Record "Sales Header";
        WhseShipmentHeader: Record "Warehouse Shipment Header";
        WarehouseActivityHeader: Record "Warehouse Activity Header";
        ResponseJson: JsonObject;
        ShipmentLinesToken: JsonToken;
    begin
        // [SCENARIO] Response includes a non-empty shipmentLines array
        Initialize();
        ArrangePickReadyForRegister(Location, Item, SalesHeader, WhseShipmentHeader, WarehouseActivityHeader);

        CreateRegisterMessage(ResponseJson, WarehouseActivityHeader."No.");
        Assert.IsTrue(ResponseJson.Get('shipmentLines', ShipmentLinesToken), 'shipmentLines missing');
        Assert.IsTrue(ShipmentLinesToken.IsArray(), 'shipmentLines should be a JSON array');
        Assert.IsTrue(ShipmentLinesToken.AsArray().Count() >= 1, 'shipmentLines should contain at least one row');
    end;

    [Test]
    procedure PickRegister_PickNotFound_ReturnsError()
    var
        ResponseJson: JsonObject;
        StatusToken: JsonToken;
    begin
        // [SCENARIO] Non-existent pick No. returns Error
        Initialize();

        CreateRegisterMessage(ResponseJson, 'NO-SUCH-PICK');
        Assert.IsTrue(ResponseJson.Get('status', StatusToken), 'status missing');
        Assert.AreEqual('Error', StatusToken.AsValue().AsText(), 'Status should be Error');
        // [THEN] #135 amended AC6: RecordNotFound in the shared wording, with parameter and received.
        ResponseJson.Get('code', StatusToken);
        Assert.AreEqual('RecordNotFound', StatusToken.AsValue().AsText(), 'code');
        ResponseJson.Get('error', StatusToken);
        Assert.AreEqual('Warehouse Activity Header "NO-SUCH-PICK" was not found (from subject).', StatusToken.AsValue().AsText(), 'error');
        ResponseJson.Get('parameter', StatusToken);
        Assert.AreEqual('subject', StatusToken.AsValue().AsText(), 'parameter');
        ResponseJson.Get('received', StatusToken);
        Assert.AreEqual('NO-SUCH-PICK', StatusToken.AsValue().AsText(), 'received');
    end;

    [Test]
    procedure PickRegister_MissingIdentifier_ReturnsError()
    var
        ResponseJson: JsonObject;
        StatusToken: JsonToken;
    begin
        // [SCENARIO] No Subject and no identifier key returns Error
        Initialize();

        CreateRegisterMessage(ResponseJson, '');
        Assert.IsTrue(ResponseJson.Get('status', StatusToken), 'status missing');
        Assert.AreEqual('Error', StatusToken.AsValue().AsText(), 'Status should be Error');
        ResponseJson.Get('code', StatusToken);
        Assert.AreEqual('MissingParameter', StatusToken.AsValue().AsText(), 'code');
    end;

    local procedure ArrangePickReadyForRegister(var Location: Record Location; var Item: Record Item; var SalesHeader: Record "Sales Header"; var WhseShipmentHeader: Record "Warehouse Shipment Header"; var WarehouseActivityHeader: Record "Warehouse Activity Header")
    var
        ResponseJson: JsonObject;
    begin
        Helper.SetupPickLocationAndItem(Location, Item, 100);
        Helper.CreateReleasedSalesOrder(SalesHeader, Item."No.", Location.Code, 5);
        Helper.CreateWhseShipmentFromSalesOrder(WhseShipmentHeader, SalesHeader);

        // Use the Bifrost Pick.Create message type to build the pick (mirrors customer usage).
        CreatePickCreateMessage(ResponseJson, WhseShipmentHeader."No.");

        Assert.IsTrue(Helper.FindPickForShipment(WhseShipmentHeader."No.", WarehouseActivityHeader), 'Pick should have been created for shipment ' + WhseShipmentHeader."No.");
    end;

    local procedure CreatePickCreateMessage(var ResponseJson: JsonObject; WhseShipmentNo: Code[20])
    var
        RequestJson: JsonObject;
        RequestText: Text;
    begin
        RequestJson.WriteTo(RequestText);

        Helper.RunMessage(Enum::"Message Type ori"::"Warehouse.Pick.Create", WhseShipmentNo, RequestText, ResponseJson);
    end;

    local procedure CreateRegisterMessage(var ResponseJson: JsonObject; PickNo: Code[20])
    var
        RequestJson: JsonObject;
        RequestText: Text;
    begin
        RequestJson.WriteTo(RequestText);

        Helper.RunMessage(Enum::"Message Type ori"::"Warehouse.Pick.Register", PickNo, RequestText, ResponseJson);
    end;
}
