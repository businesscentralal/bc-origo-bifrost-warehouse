namespace Origo.Bifrost.Warehouse.Test;

using Microsoft.Foundation.Company;
using Origo.Bifrost;
using System.Globalization;
using Microsoft.Inventory.Item;
using Microsoft.Inventory.Location;
using Microsoft.Sales.Document;
using Microsoft.Warehouse.Document;
using System.TestLibraries.Utilities;

/// <summary>
/// Unit tests for Warehouse.Shipment.Create message type.
/// </summary>
codeunit 97011 "Whse Shipment Create Tests ori"
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
    procedure Create_SalesOrder_ReturnsShipmentNo()
    var
        Location: Record Location;
        Item: Record Item;
        SalesHeader: Record "Sales Header";
        WhseShipmentHeader: Record "Warehouse Shipment Header";
        ResponseJson: JsonObject;
        StatusToken, ShipmentsToken, ShipToken, NoToken : JsonToken;
        ShipmentsArray: JsonArray;
    begin
        // [SCENARIO] Creating a Warehouse Shipment from a released Sales Order returns the shipment number
        Initialize();
        Helper.SetupLocationAndItem(Location, Item, 100);
        Helper.CreateReleasedSalesOrder(SalesHeader, Item."No.", Location.Code, 5);

        CreateMessageWithSalesOrder(ResponseJson, SalesHeader."No.");
        Assert.IsTrue(ResponseJson.Get('status', StatusToken), 'status missing');
        Assert.AreEqual('Success', StatusToken.AsValue().AsText(), 'Status should be Success');

        Assert.IsTrue(ResponseJson.Get('shipments', ShipmentsToken), 'shipments missing');
        ShipmentsArray := ShipmentsToken.AsArray();
        Assert.AreEqual(1, ShipmentsArray.Count(), 'Expected one shipment created');

        ShipmentsArray.Get(0, ShipToken);
        Assert.IsTrue(ShipToken.AsObject().Get('no', NoToken), 'shipment no missing');
        Assert.IsTrue(WhseShipmentHeader.Get(NoToken.AsValue().AsText()), 'Warehouse Shipment Header should exist');
        Assert.AreEqual(Location.Code, WhseShipmentHeader."Location Code", 'Location Code mismatch');
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
        // [SCENARIO] Unsupported sourceType returns Error
        Initialize();

        SourceObj.Add('sourceType', 'PurchaseOrder');
        SourceObj.Add('documentNo', 'X');
        SourcesArray.Add(SourceObj);
        RequestJson.Add('sourceDocuments', SourcesArray);

        CreateMessageWithRequestJson(ResponseJson, RequestJson);
        Assert.IsTrue(ResponseJson.Get('status', StatusToken), 'status missing');
        Assert.AreEqual('Error', StatusToken.AsValue().AsText(), 'Status should be Error');
    end;

    [Test]
    procedure Create_SalesOrderNotReleased_ReturnsError()
    var
        Location: Record Location;
        Item: Record Item;
        SalesHeader: Record "Sales Header";
        ReopenSalesDocument: Codeunit "Release Sales Document";
        ResponseJson: JsonObject;
        StatusToken: JsonToken;
    begin
        // [SCENARIO] An Open sales order returns Error
        Initialize();
        Helper.SetupLocationAndItem(Location, Item, 100);
        Helper.CreateReleasedSalesOrder(SalesHeader, Item."No.", Location.Code, 5);
        ReopenSalesDocument.Reopen(SalesHeader);
        SalesHeader.Get(SalesHeader."Document Type"::Order, SalesHeader."No.");

        CreateMessageWithSalesOrder(ResponseJson, SalesHeader."No.");
        Assert.IsTrue(ResponseJson.Get('status', StatusToken), 'status missing');
        Assert.AreEqual('Error', StatusToken.AsValue().AsText(), 'Status should be Error');
    end;

    local procedure CreateMessageWithSalesOrder(var ResponseJson: JsonObject; SalesOrderNo: Code[20])
    var
        RequestJson, SourceObj : JsonObject;
        SourcesArray: JsonArray;
    begin
        SourceObj.Add('sourceType', 'SalesOrder');
        SourceObj.Add('documentNo', SalesOrderNo);
        SourcesArray.Add(SourceObj);
        RequestJson.Add('sourceDocuments', SourcesArray);
        CreateMessageWithRequestJson(ResponseJson, RequestJson);
    end;

    local procedure CreateMessageWithRequestJson(var ResponseJson: JsonObject; RequestJson: JsonObject)
    var
        RequestText: Text;
    begin
        RequestJson.WriteTo(RequestText);

        Helper.RunMessage(Enum::"Message Type ori"::"Warehouse.Shipment.Create", '', RequestText, ResponseJson);
    end;

    /// <summary>Verifies that Warehouse.Shipment.Create is enabled when write permission is present.</summary>
    [Test]
    procedure IsEnabledWithWritePermission()
    var
        MessageTypeInterface: Interface "Msg Interface ori";
    begin
        MessageTypeInterface := Enum::"Message Type ori"::"Warehouse.Shipment.Create";
        Assert.IsTrue(MessageTypeInterface.IsEnabled(), 'Warehouse.Shipment.Create must be enabled when the caller can write Warehouse Shipment Header.');
    end;

    /// <summary>Verifies that Warehouse.Shipment.Create is disabled without write permission on Warehouse Shipment Header.</summary>
    [Test]
    [TestPermissions(TestPermissions::Restrictive)]
    procedure IsDisabledWithoutWritePermission()
    var
        LibraryLowerPermissions: Codeunit "Library - Lower Permissions";
        MessageTypeInterface: Interface "Msg Interface ori";
    begin
        LibraryLowerPermissions.PushPermissionSetWithoutDefaults('Whse NoRead Test ori');
        MessageTypeInterface := Enum::"Message Type ori"::"Warehouse.Shipment.Create";
        Assert.IsFalse(MessageTypeInterface.IsEnabled(), 'Warehouse.Shipment.Create must be disabled without write permission on Warehouse Shipment Header.');
    end;
    /// <summary>Issue #27 AC08: refusal text is entirely in the requested language.</summary>
    [Test]
    procedure ShipmentCreate_Refusal_IsLocalized()
    var
        EnglishResponse: JsonObject;
        IcelandicResponse: JsonObject;
    begin
        // Story #27, AC08 | Time: independent of Today/WorkDate | Risk: native pipeline restores GlobalLanguage; company language restored before assertions.
        ReadLocalizedRefusal(1033, '{}', EnglishResponse);
        ReadLocalizedRefusal(1039, '{}', IcelandicResponse);
        AssertLocalizedError(EnglishResponse, 'sourceDocuments is required and must contain at least one entry.');
        AssertLocalizedError(IcelandicResponse, 'sourceDocuments er nauðsynlegt og verður að innihalda að minnsta kosti eina færslu.');
    end;

    local procedure ReadLocalizedRefusal(LanguageId: Integer; RequestText: Text; var ResponseJson: JsonObject)
    var
        CompanyInformation: Record "Company Information";
        Language: Record Language;
        ShipmentHelper: Codeunit "Whse Shipment Test Helper ori";
        OriginalLanguageCode: Code[10];
        TestLanguageCode: Code[10];
        OriginalLanguageId: Integer;
        Succeeded: Boolean;
    begin
        // The public dispatcher uses the company language when Foundation's default is blank.
        // Seed an owned language mapping; do not access Foundation Setup or licensing data.
        if LanguageId = 1039 then
            TestLanguageCode := 'W2IS'
        else
            TestLanguageCode := 'W2EN';
        if not Language.Get(TestLanguageCode) then begin
            Language.Init();
            Language.Code := TestLanguageCode;
            Language.Name := 'Owned W2 locale test';
            Language.Insert();
        end;
        Language."Windows Language ID" := LanguageId;
        Language.Modify();
        CompanyInformation.Get();
        OriginalLanguageCode := CompanyInformation."Default Language Code";
        CompanyInformation."Default Language Code" := Language.Code;
        CompanyInformation.Modify();
        OriginalLanguageId := GlobalLanguage();
        Succeeded := ShipmentHelper.RunMessage("Message Type ori"::"Warehouse.Shipment.Create", '', RequestText, ResponseJson, false);
        CompanyInformation."Default Language Code" := OriginalLanguageCode;
        CompanyInformation.Modify();
        // The orchestrator restores GlobalLanguage; company fixture state is restored before assertions.
        Assert.AreEqual(OriginalLanguageId, GlobalLanguage(), 'The native pipeline must restore the caller language.');
        Assert.IsTrue(Succeeded, 'Localized request must return JSON.');
    end;

    local procedure AssertLocalizedError(ResponseJson: JsonObject; ExpectedText: Text)
    var
        Token: JsonToken;
    begin
        Assert.IsTrue(ResponseJson.Get('error', Token), 'Refusal must have error text.');
        Assert.AreEqual(ExpectedText, Token.AsValue().AsText(), 'The entire refusal must match the requested language.');
    end;

}
