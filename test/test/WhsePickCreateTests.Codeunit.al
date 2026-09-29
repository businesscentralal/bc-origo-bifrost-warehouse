namespace Origo.Bifrost.Warehouse.Test;

using Origo.Bifrost;
using Microsoft.Inventory.Item;
using Microsoft.Inventory.Location;
using Microsoft.Sales.Document;
using Microsoft.Warehouse.Activity;
using Microsoft.Warehouse.Document;
using System.TestLibraries.Utilities;

/// <summary>
/// Unit tests for Warehouse.Pick.Create message type.
/// </summary>
codeunit 97017 "Whse Pick Create Tests ori"
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
    procedure PickCreate_HappyPath_ReturnsPickNo()
    var
        Location: Record Location;
        Item: Record Item;
        SalesHeader: Record "Sales Header";
        WhseShipmentHeader: Record "Warehouse Shipment Header";
        ResponseJson: JsonObject;
        StatusToken, PickNoToken, TotalLinesToken : JsonToken;
    begin
        // [SCENARIO] Pick.Create against a valid Warehouse Shipment returns a populated Pick No.
        Initialize();
        Helper.SetupPickLocationAndItem(Location, Item, 100);
        Helper.CreateReleasedSalesOrder(SalesHeader, Item."No.", Location.Code, 5);
        Helper.CreateWhseShipmentFromSalesOrder(WhseShipmentHeader, SalesHeader);

        CreateMessage(ResponseJson, WhseShipmentHeader."No.", '', '', false, false);
        Assert.IsTrue(ResponseJson.Get('status', StatusToken), 'status missing');
        Assert.AreEqual('Success', StatusToken.AsValue().AsText(), 'Status should be Success');
        Assert.IsTrue(ResponseJson.Get('pickNo', PickNoToken), 'pickNo missing');
        Assert.AreNotEqual('', PickNoToken.AsValue().AsText(), 'pickNo should be populated');
        Assert.IsTrue(ResponseJson.Get('totalPickLines', TotalLinesToken), 'totalPickLines missing');
        Assert.IsTrue(TotalLinesToken.AsValue().AsInteger() >= 1, 'totalPickLines should be at least 1');
    end;

    [Test]
    procedure PickCreate_WithAssignedUserId_AppliesToHeader()
    var
        Location: Record Location;
        Item: Record Item;
        SalesHeader: Record "Sales Header";
        WhseShipmentHeader: Record "Warehouse Shipment Header";
        WarehouseActivityHeader: Record "Warehouse Activity Header";
        ResponseJson: JsonObject;
        AssignedUserToken: JsonToken;
        AssignedUser: Code[50];
    begin
        // [SCENARIO] assignedUserId is applied to the created Warehouse Pick header
        Initialize();
        Helper.SetupPickLocationAndItem(Location, Item, 100);
        Helper.CreateReleasedSalesOrder(SalesHeader, Item."No.", Location.Code, 5);
        Helper.CreateWhseShipmentFromSalesOrder(WhseShipmentHeader, SalesHeader);

        AssignedUser := Helper.RegisterCurrentUserAsWarehouseEmployee(Location.Code);
        CreateMessage(ResponseJson, WhseShipmentHeader."No.", AssignedUser, '', false, false);
        Assert.IsTrue(ResponseJson.Get('assignedUserId', AssignedUserToken), 'assignedUserId missing');
        Assert.AreEqual(AssignedUser, AssignedUserToken.AsValue().AsText(), 'assignedUserId mismatch');

        Assert.IsTrue(Helper.FindPickForShipment(WhseShipmentHeader."No.", WarehouseActivityHeader), 'Pick header not found');
        Assert.AreEqual(AssignedUser, WarehouseActivityHeader."Assigned User ID", 'Assigned User ID not persisted on header');
    end;

    [Test]
    procedure PickCreate_InvalidSortingMethod_ReturnsError()
    var
        Location: Record Location;
        Item: Record Item;
        SalesHeader: Record "Sales Header";
        WhseShipmentHeader: Record "Warehouse Shipment Header";
        ResponseJson: JsonObject;
        StatusToken, ErrorToken : JsonToken;
    begin
        // [SCENARIO] An unknown sortingMethod returns Error and the supplied value appears in the error message
        Initialize();
        Helper.SetupPickLocationAndItem(Location, Item, 100);
        Helper.CreateReleasedSalesOrder(SalesHeader, Item."No.", Location.Code, 5);
        Helper.CreateWhseShipmentFromSalesOrder(WhseShipmentHeader, SalesHeader);

        CreateMessage(ResponseJson, WhseShipmentHeader."No.", '', 'NotAMethod', false, false);
        Assert.IsTrue(ResponseJson.Get('status', StatusToken), 'status missing');
        Assert.AreEqual('Error', StatusToken.AsValue().AsText(), 'Status should be Error');
        Assert.IsTrue(ResponseJson.Get('error', ErrorToken), 'error missing');
        Assert.IsTrue(ErrorToken.AsValue().AsText().Contains('NotAMethod'), 'Error should mention supplied sortingMethod value');
    end;

    [Test]
    procedure PickCreate_ShipmentNotFound_ReturnsError()
    var
        ResponseJson: JsonObject;
        StatusToken: JsonToken;
    begin
        // [SCENARIO] Non-existent Warehouse Shipment No. returns Error
        Initialize();

        CreateMessage(ResponseJson, 'DOES-NOT-EXIST', '', '', false, false);
        Assert.IsTrue(ResponseJson.Get('status', StatusToken), 'status missing');
        Assert.AreEqual('Error', StatusToken.AsValue().AsText(), 'Status should be Error');
        // [THEN] #135 amended AC6: RecordNotFound in the shared wording, with parameter and received.
        ResponseJson.Get('code', StatusToken);
        Assert.AreEqual('RecordNotFound', StatusToken.AsValue().AsText(), 'code');
        ResponseJson.Get('error', StatusToken);
        Assert.AreEqual('Warehouse Shipment Header "DOES-NOT-EXIST" was not found (from subject).', StatusToken.AsValue().AsText(), 'error');
        ResponseJson.Get('parameter', StatusToken);
        Assert.AreEqual('subject', StatusToken.AsValue().AsText(), 'parameter');
        ResponseJson.Get('received', StatusToken);
        Assert.AreEqual('DOES-NOT-EXIST', StatusToken.AsValue().AsText(), 'received');
    end;

    [Test]
    procedure PickCreate_MissingIdentifier_ReturnsError()
    var
        ResponseJson: JsonObject;
        StatusToken: JsonToken;
    begin
        // [SCENARIO] No Subject and no identifier key in request returns Error
        Initialize();

        CreateMessage(ResponseJson, '', '', '', false, false);
        Assert.IsTrue(ResponseJson.Get('status', StatusToken), 'status missing');
        Assert.AreEqual('Error', StatusToken.AsValue().AsText(), 'Status should be Error');
        ResponseJson.Get('code', StatusToken);
        Assert.AreEqual('MissingParameter', StatusToken.AsValue().AsText(), 'code');
    end;

    [Test]
    procedure PickCreate_SetBreakbulkFilterTrue_ReturnsError()
    var
        Location: Record Location;
        Item: Record Item;
        SalesHeader: Record "Sales Header";
        WhseShipmentHeader: Record "Warehouse Shipment Header";
        ResponseJson: JsonObject;
        StatusToken, ErrorToken : JsonToken;
    begin
        // [SCENARIO] setBreakbulkFilter = true is not supported by this API version
        Initialize();
        Helper.SetupPickLocationAndItem(Location, Item, 100);
        Helper.CreateReleasedSalesOrder(SalesHeader, Item."No.", Location.Code, 5);
        Helper.CreateWhseShipmentFromSalesOrder(WhseShipmentHeader, SalesHeader);

        CreateMessage(ResponseJson, WhseShipmentHeader."No.", '', '', true, false);
        Assert.IsTrue(ResponseJson.Get('status', StatusToken), 'status missing');
        Assert.AreEqual('Error', StatusToken.AsValue().AsText(), 'Status should be Error');
        Assert.IsTrue(ResponseJson.Get('error', ErrorToken), 'error missing');
        Assert.IsTrue(ErrorToken.AsValue().AsText().Contains('setBreakbulkFilter'), 'Error should mention setBreakbulkFilter');
    end;

    local procedure CreateMessage(var ResponseJson: JsonObject; WhseShipmentNo: Code[20]; AssignedUserId: Code[50]; SortingMethod: Text; SetBreakbulkFilter: Boolean; DoNotFillQtyToHandle: Boolean)
    var
        RequestJson: JsonObject;
        RequestText: Text;
    begin
        if AssignedUserId <> '' then
            RequestJson.Add('assignedUserId', AssignedUserId);
        if SortingMethod <> '' then
            RequestJson.Add('sortingMethod', SortingMethod);
        if SetBreakbulkFilter then
            RequestJson.Add('setBreakbulkFilter', true);
        if DoNotFillQtyToHandle then
            RequestJson.Add('doNotFillQtyToHandle', true);
        RequestJson.WriteTo(RequestText);

        Helper.RunMessage(Enum::"Message Type ori"::"Warehouse.Pick.Create", WhseShipmentNo, RequestText, ResponseJson);
    end;

    /// <summary>Verifies that Warehouse.Pick.Create is enabled when write permission is present.</summary>
    [Test]
    procedure IsEnabledWithWritePermission()
    var
        MessageTypeInterface: Interface "Msg Interface ori";
    begin
        MessageTypeInterface := Enum::"Message Type ori"::"Warehouse.Pick.Create";
        Assert.IsTrue(MessageTypeInterface.IsEnabled(), 'Warehouse.Pick.Create must be enabled when the caller can write Warehouse Shipment Header.');
    end;

    /// <summary>Verifies that Warehouse.Pick.Create is disabled without write permission on Warehouse Shipment Header.</summary>
    [Test]
    [TestPermissions(TestPermissions::Restrictive)]
    procedure IsDisabledWithoutWritePermission()
    var
        LibraryLowerPermissions: Codeunit "Library - Lower Permissions";
        MessageTypeInterface: Interface "Msg Interface ori";
    begin
        LibraryLowerPermissions.PushPermissionSetWithoutDefaults('Whse NoRead Test ori');
        MessageTypeInterface := Enum::"Message Type ori"::"Warehouse.Pick.Create";
        Assert.IsFalse(MessageTypeInterface.IsEnabled(), 'Warehouse.Pick.Create must be disabled without write permission on Warehouse Shipment Header.');
    end;
}
