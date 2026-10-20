namespace Origo.Bifrost.Warehouse.Test;

using Microsoft.Inventory.Item;
using Microsoft.Inventory.Location;
using Microsoft.Purchases.Document;
using Microsoft.Sales.Document;
using Microsoft.Warehouse.Document;
using Microsoft.Warehouse.History;
using Microsoft.Warehouse.Worksheet;
using Origo.Bifrost;
using Origo.Bifrost.Warehouse;
using System.TestLibraries.Utilities;

/// <summary>
/// Tests Warehouse.Worksheet.GetDocuments (#55): pick and put-away worksheets, refusals and the permission path.
/// </summary>
codeunit 97056 "Whse Wksh GetDocs Tests ori"
{
    Subtype = Test;
    TestPermissions = Disabled;

    var
        Assert: Codeunit "Library Assert";
        Helper: Codeunit "Whse Jnl Test Helper ori";
        ShipmentHelper: Codeunit "Whse Shipment Test Helper ori";

    /// <summary>AC01: a released shipment is added to the pick worksheet.</summary>
    [Test]
    procedure GetDocuments_PickWorksheet_AddsShipmentLine()
    var
        Location: Record Location;
        WorksheetName: Record "Whse. Worksheet Name";
        ShipmentHeader: Record "Warehouse Shipment Header";
        ResponseJson: JsonObject;
        LineJson: JsonObject;
    begin
        Helper.CreateReleasedShipment(Location, ShipmentHeader, 5);
        Helper.CreateWorksheetName(Enum::"Warehouse Worksheet Template Type"::Pick, Location.Code, WorksheetName);

        ResponseJson := Send(Helper.WorksheetRequest('pick', WorksheetName, ',"documentType":"Shipment","documentNo":"' + ShipmentHeader."No." + '"'));

        Helper.AssertSuccess(ResponseJson);
        Assert.AreEqual(1, Helper.IntegerValue(ResponseJson, 'lineCount'), Helper.ResponseText(ResponseJson));
        LineJson := Helper.ItemAt(Helper.ArrayValue(ResponseJson, 'lines'), 0);
        Assert.AreEqual('Shipment', Helper.TextValue(LineJson, 'whseDocumentType'), 'Document type.');
        Assert.AreEqual(ShipmentHeader."No.", Helper.TextValue(LineJson, 'whseDocumentNo'), 'Document number.');
        Assert.AreEqual(5, Helper.DecimalValue(LineJson, 'qtyOutstanding'), 'Outstanding quantity.');
    end;

    /// <summary>AC01: a posted receipt is added to the put-away worksheet.</summary>
    [Test]
    procedure GetDocuments_PutAwayWorksheet_AddsReceiptLine()
    var
        Location: Record Location;
        WorksheetName: Record "Whse. Worksheet Name";
        PostedReceiptHeader: Record "Posted Whse. Receipt Header";
        ResponseJson: JsonObject;
        LineJson: JsonObject;
    begin
        Helper.CreatePostedReceipt(Location, PostedReceiptHeader, 4);
        Helper.CreateWorksheetName(Enum::"Warehouse Worksheet Template Type"::"Put-away", Location.Code, WorksheetName);

        ResponseJson := Send(Helper.WorksheetRequest('putAway', WorksheetName, ''));

        Helper.AssertSuccess(ResponseJson);
        Assert.AreEqual(1, Helper.IntegerValue(ResponseJson, 'lineCount'), Helper.ResponseText(ResponseJson));
        LineJson := Helper.ItemAt(Helper.ArrayValue(ResponseJson, 'lines'), 0);
        Assert.AreEqual('Receipt', Helper.TextValue(LineJson, 'whseDocumentType'), 'Document type.');
        Assert.AreEqual(PostedReceiptHeader."No.", Helper.TextValue(LineJson, 'whseDocumentNo'), 'Posted receipt number.');
    end;

    /// <summary>Edge: no open document answers success with zero lines.</summary>
    [Test]
    procedure GetDocuments_NoOpenDocument_AnswersZeroLines()
    var
        Location: Record Location;
        Item: Record Item;
        WorksheetName: Record "Whse. Worksheet Name";
        ResponseJson: JsonObject;
    begin
        ShipmentHelper.SetupPickLocationAndItem(Location, Item, 0);
        Helper.CreateWorksheetName(Enum::"Warehouse Worksheet Template Type"::Pick, Location.Code, WorksheetName);

        ResponseJson := Send(Helper.WorksheetRequest('pick', WorksheetName, ''));

        Helper.AssertSuccess(ResponseJson);
        Assert.AreEqual(0, Helper.IntegerValue(ResponseJson, 'lineCount'), 'No document writes no line.');
    end;

    /// <summary>AC03: a location without pick is refused with the inventory activities next step.</summary>
    [Test]
    procedure GetDocuments_LocationWithoutPick_PreconditionFailed()
    var
        Location: Record Location;
    begin
        Helper.CreateBasicLocation(Location);

        Helper.ExpectError(Send('{"worksheetType":"pick","worksheetTemplateName":"PICK","worksheetName":"DEFAULT","locationCode":"' + Location.Code + '"}'), 'PreconditionFailed', 'Use the inventory activities instead.');
    end;

    /// <summary>AC04 and AC05: unknown worksheet name, missing and invalid keys.</summary>
    [Test]
    procedure GetDocuments_Refusals_AnswerCodesWithNextStep()
    var
        Location: Record Location;
        Item: Record Item;
        WorksheetName: Record "Whse. Worksheet Name";
    begin
        ShipmentHelper.SetupPickLocationAndItem(Location, Item, 0);
        Helper.CreateWorksheetName(Enum::"Warehouse Worksheet Template Type"::Pick, Location.Code, WorksheetName);

        Helper.ExpectError(Send('{"worksheetType":"pick","worksheetTemplateName":"' + WorksheetName."Worksheet Template Name" + '","worksheetName":"NONAME","locationCode":"' + Location.Code + '"}'), 'RecordNotFound', 'Create the worksheet name first.');
        Helper.ExpectError(Send('{"worksheetTemplateName":"' + WorksheetName."Worksheet Template Name" + '","worksheetName":"' + WorksheetName.Name + '","locationCode":"' + Location.Code + '"}'), 'MissingParameter', '');
        Helper.ExpectError(Send(Helper.WorksheetRequest('wave', WorksheetName, '')), 'InvalidParameter', 'Send worksheetType pick or putAway.');
        Helper.ExpectError(Send(Helper.WorksheetRequest('pick', WorksheetName, ',"documentType":"Receipt"')), 'InvalidParameter', 'Send a documentType of the worksheet type, or omit it.');
        Helper.ExpectError(Send(Helper.WorksheetRequest('pick', WorksheetName, ',"documentNo":12')), 'InvalidParameterFormat', '');
        Helper.ExpectError(Send(Helper.WorksheetRequest('pick', WorksheetName, ',"sort":"x"')), 'UnknownParameter', '');
        Helper.ExpectError(Send(Helper.WorksheetRequest('putAway', WorksheetName, '')), 'PreconditionFailed', 'Use the inventory activities instead.');
        Helper.ExpectError(Helper.RunType(Enum::"Message Type ori"::"Warehouse.Worksheet.GetDocuments", 'OTHERLOC', Helper.WorksheetRequest('pick', WorksheetName, '')), 'ConflictingIdentifiers', '');
    end;

    /// <summary>AC07: without worksheet write permission the type is disabled and answers PermissionDenied.</summary>
    [Test]
    [TestPermissions(TestPermissions::Restrictive)]
    procedure GetDocuments_WithoutPermission_ReturnsPermissionDenied()
    var
        TempArgument: Record "Message Argument ori" temporary;
        GetDocsImpl: Codeunit "Whse Wksh GetDocs Impl ori";
        LibraryLowerPermissions: Codeunit "Library - Lower Permissions";
        MessageTypeInterface: Interface "Msg Interface ori";
    begin
        LibraryLowerPermissions.PushPermissionSetWithoutDefaults('Whse NoRead Test ori');
        MessageTypeInterface := Enum::"Message Type ori"::"Warehouse.Worksheet.GetDocuments";
        Assert.IsFalse(MessageTypeInterface.IsEnabled(), 'GetDocuments must be disabled without worksheet write permission.');
        TempArgument.Init();
        TempArgument.Version := "Message Version ori"::"1.0";
        TempArgument.Insert(true);
        GetDocsImpl.ExecuteBifrostTask(TempArgument);
        Helper.ExpectError(TempArgument.GetResponseJson(), 'PermissionDenied', 'Ask an administrator to assign BIFROST Whse - Full ori.');
    end;

    local procedure Send(RequestText: Text): JsonObject
    begin
        exit(Helper.RunType(Enum::"Message Type ori"::"Warehouse.Worksheet.GetDocuments", '', RequestText));
    end;
}
