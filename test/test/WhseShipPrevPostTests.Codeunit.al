namespace Origo.Bifrost.Warehouse.Test;

using Origo.Bifrost;
using Microsoft.Inventory.Item;
using Microsoft.Inventory.Location;
using Microsoft.Sales.Document;
using Microsoft.Warehouse.Document;
using Microsoft.Warehouse.History;
using System.TestLibraries.Utilities;

/// <summary>
/// Unit tests for Warehouse.Shipment.PreviewPost message type implementation.
/// Verifies that the preview captures simulated ledger entries, leaves the warehouse
/// shipment in place (rollback), and always reports invoice=true since BC's preview
/// subscriber hardcodes ship+invoice.
/// </summary>
codeunit 97013 "Whse Ship Prev Post Tests ori"
{
    Subtype = Test;
    TestPermissions = Disabled;

    var
        Assert: Codeunit "Library Assert";
        Helper: Codeunit "Whse Shipment Test Helper ori";
        IsInitialized: Boolean;

    [Test]
    procedure PreviewPost_PostableShipment_ReturnsSuccessAndRollback()
    var
        Location: Record Location;
        Item: Record Item;
        SalesHeader: Record "Sales Header";
        WhseShipmentHeader: Record "Warehouse Shipment Header";
        ResponseJson: JsonObject;
        Token: JsonToken;
    begin
        // [SCENARIO] PreviewPost of a postable warehouse shipment returns Success with rollback=true;
        //            the shipment header remains afterwards.
        Initialize();

        Helper.SetupLocationAndItem(Location, Item, 100);
        Helper.CreateReleasedSalesOrder(SalesHeader, Item."No.", Location.Code, 5);
        Helper.CreateWhseShipmentFromSalesOrder(WhseShipmentHeader, SalesHeader);

        Assert.IsTrue(Helper.RunMessage(Enum::"Message Type ori"::"Warehouse.Shipment.PreviewPost", WhseShipmentHeader."No.", '', ResponseJson), 'Response JSON should parse');
        AssertStatus(ResponseJson, 'Success');
        Assert.IsTrue(ResponseJson.Get('rollback', Token), 'rollback flag should be present');
        Assert.IsTrue(Token.AsValue().AsBoolean(), 'rollback should be true');

        WhseShipmentHeader.SetRecFilter();
        Assert.RecordIsNotEmpty(WhseShipmentHeader);
    end;

    [Test]
    procedure PreviewPost_PostableShipment_DoesNotCreatePostedShipment()
    var
        Location: Record Location;
        Item: Record Item;
        SalesHeader: Record "Sales Header";
        WhseShipmentHeader: Record "Warehouse Shipment Header";
        PostedWhseShipmentHeader: Record "Posted Whse. Shipment Header";
        ResponseJson: JsonObject;
        PostedCountBefore, PostedCountAfter : Integer;
    begin
        // [SCENARIO] PreviewPost does not actually persist a Posted Whse. Shipment Header.
        Initialize();

        Helper.SetupLocationAndItem(Location, Item, 100);
        Helper.CreateReleasedSalesOrder(SalesHeader, Item."No.", Location.Code, 5);
        Helper.CreateWhseShipmentFromSalesOrder(WhseShipmentHeader, SalesHeader);
        PostedCountBefore := PostedWhseShipmentHeader.Count();

        Assert.IsTrue(Helper.RunMessage(Enum::"Message Type ori"::"Warehouse.Shipment.PreviewPost", WhseShipmentHeader."No.", '', ResponseJson), 'Response JSON should parse');
        AssertStatus(ResponseJson, 'Success');

        PostedCountAfter := PostedWhseShipmentHeader.Count();
        Assert.AreEqual(PostedCountBefore, PostedCountAfter, 'PreviewPost must not create a Posted Whse. Shipment Header');
    end;

    [Test]
    procedure PreviewPost_PostableShipment_ReturnsContextAndAlwaysInvoiceTrue()
    var
        Location: Record Location;
        Item: Record Item;
        SalesHeader: Record "Sales Header";
        WhseShipmentHeader: Record "Warehouse Shipment Header";
        ResponseJson: JsonObject;
        PreviewArrayToken, Token : JsonToken;
    begin
        // [SCENARIO] Response contains shipmentNo, invoice=true, summary, preview array.
        //            BC's preview subscriber hardcodes ship+invoice so invoice is always true.
        Initialize();

        Helper.SetupLocationAndItem(Location, Item, 100);
        Helper.CreateReleasedSalesOrder(SalesHeader, Item."No.", Location.Code, 5);
        Helper.CreateWhseShipmentFromSalesOrder(WhseShipmentHeader, SalesHeader);

        Assert.IsTrue(Helper.RunMessage(Enum::"Message Type ori"::"Warehouse.Shipment.PreviewPost", WhseShipmentHeader."No.", '', ResponseJson), 'Response JSON should parse');
        AssertStatus(ResponseJson, 'Success');

        Assert.IsTrue(ResponseJson.Get('shipmentNo', Token), 'Should have shipmentNo');
        Assert.AreEqual(WhseShipmentHeader."No.", Token.AsValue().AsText(), 'shipmentNo should match');

        Assert.IsTrue(ResponseJson.Get('invoice', Token), 'Should have invoice flag');
        Assert.IsTrue(Token.AsValue().AsBoolean(), 'invoice should always be true (BC preview hardcodes ship+invoice)');

        Assert.IsTrue(ResponseJson.Get('summary', Token), 'Should have summary');

        Assert.IsTrue(ResponseJson.Get('preview', PreviewArrayToken), 'Should have preview array');
        Assert.IsTrue(PreviewArrayToken.AsArray().Count() > 0, 'Preview array should have at least one populated table');
    end;

    [Test]
    procedure PreviewPost_SystemIdSubject_ReturnsSuccess()
    var
        Location: Record Location;
        Item: Record Item;
        SalesHeader: Record "Sales Header";
        WhseShipmentHeader: Record "Warehouse Shipment Header";
        ResponseJson: JsonObject;
    begin
        // [SCENARIO] Subject containing the SystemId GUID resolves the shipment.
        Initialize();

        Helper.SetupLocationAndItem(Location, Item, 100);
        Helper.CreateReleasedSalesOrder(SalesHeader, Item."No.", Location.Code, 5);
        Helper.CreateWhseShipmentFromSalesOrder(WhseShipmentHeader, SalesHeader);

        Assert.IsTrue(Helper.RunMessage(Enum::"Message Type ori"::"Warehouse.Shipment.PreviewPost", Format(WhseShipmentHeader.SystemId, 0, 4), '', ResponseJson), 'Response JSON should parse');
        AssertStatus(ResponseJson, 'Success');
    end;

    [Test]
    procedure PreviewPost_ShipmentNotFound_ReturnsError()
    var
        ResponseJson: JsonObject;
    begin
        Initialize();

        Assert.IsTrue(Helper.RunMessage(Enum::"Message Type ori"::"Warehouse.Shipment.PreviewPost", 'NONEXISTENT-WS', '', ResponseJson), 'Response JSON should parse');
        AssertStatus(ResponseJson, 'Error');
    end;

    [Test]
    procedure PreviewPost_MissingIdentification_ReturnsError()
    var
        ResponseJson: JsonObject;
    begin
        Initialize();

        Assert.IsTrue(Helper.RunMessage(Enum::"Message Type ori"::"Warehouse.Shipment.PreviewPost", '', '', ResponseJson), 'Response JSON should parse');
        AssertStatus(ResponseJson, 'Error');
    end;

    [Test]
    procedure PreviewPost_NothingToShip_ReturnsNothingToPreview()
    var
        Location: Record Location;
        Item: Record Item;
        SalesHeader: Record "Sales Header";
        WhseShipmentHeader: Record "Warehouse Shipment Header";
        WhseShipmentLine: Record "Warehouse Shipment Line";
        ResponseJson: JsonObject;
        Token: JsonToken;
    begin
        // [SCENARIO] #140 AC5: a shipment with no Qty. to Ship never previews as Success.
        Initialize();

        Helper.SetupLocationAndItem(Location, Item, 100);
        Helper.CreateReleasedSalesOrder(SalesHeader, Item."No.", Location.Code, 5);
        Helper.CreateWhseShipmentFromSalesOrder(WhseShipmentHeader, SalesHeader);
        WhseShipmentLine.SetRange("No.", WhseShipmentHeader."No.");
        WhseShipmentLine.FindSet(true);
        repeat
            WhseShipmentLine.Validate("Qty. to Ship", 0);
            WhseShipmentLine.Modify(true);
        until WhseShipmentLine.Next() = 0;
        Commit();

        Assert.IsTrue(Helper.RunMessage(Enum::"Message Type ori"::"Warehouse.Shipment.PreviewPost", WhseShipmentHeader."No.", '', ResponseJson), 'Response JSON should parse');
        AssertStatus(ResponseJson, 'Error');
        Assert.IsTrue(ResponseJson.Get('code', Token), 'code');
        Assert.AreEqual('NothingToPreview', Token.AsValue().AsText(), 'code');
        Assert.IsTrue(ResponseJson.Get('nextStep', Token), 'nextStep');
        Assert.IsTrue(Token.AsValue().AsText().Contains('Qty. to Ship'), 'nextStep names Qty. to Ship');
    end;

    local procedure Initialize()
    begin
        if IsInitialized then
            exit;
        IsInitialized := true;
    end;

    local procedure AssertStatus(ResponseJson: JsonObject; ExpectedStatus: Text)
    var
        Token: JsonToken;
    begin
        Assert.IsTrue(ResponseJson.Get('status', Token), 'Response should contain status');
        Assert.AreEqual(ExpectedStatus, Token.AsValue().AsText(), StrSubstNo('Status should be %1', ExpectedStatus));
    end;
}
