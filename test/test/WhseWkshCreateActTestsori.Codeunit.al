namespace Origo.Bifrost.Warehouse.Test;

using Microsoft.Inventory.Item;
using Microsoft.Inventory.Location;
using Microsoft.Warehouse.Activity;
using Microsoft.Warehouse.Document;
using Microsoft.Warehouse.History;
using Microsoft.Warehouse.Worksheet;
using Origo.Bifrost;
using Origo.Bifrost.Warehouse;
using System.TestLibraries.Utilities;

/// <summary>
/// Tests Warehouse.Worksheet.CreateActivities (#55): picks and put-aways from worksheets, skipped lines, refusals and the permission path.
/// </summary>
codeunit 97057 "Whse Wksh CreateAct Tests ori"
{
    Subtype = Test;
    TestPermissions = Disabled;

    var
        Assert: Codeunit "Library Assert";
        Helper: Codeunit "Whse Jnl Test Helper ori";
        ContractAssert: Codeunit "Whse Contract Assert ori";

    /// <summary>AC02: the pick worksheet creates a pick and answers its number.</summary>
    [Test]
    procedure CreateActivities_PickWorksheet_CreatesPick()
    var
        Location: Record Location;
        WorksheetName: Record "Whse. Worksheet Name";
        ShipmentHeader: Record "Warehouse Shipment Header";
        ActivityHeader: Record "Warehouse Activity Header";
        WorksheetLine: Record "Whse. Worksheet Line";
        ResponseJson: JsonObject;
        ActivityJson: JsonObject;
    begin
        Helper.CreateReleasedShipment(Location, ShipmentHeader, 5);
        Helper.CreateWorksheetName(Enum::"Warehouse Worksheet Template Type"::Pick, Location.Code, WorksheetName);
        GetDocuments('pick', WorksheetName);

        ResponseJson := Send(Helper.WorksheetRequest('pick', WorksheetName, ',"sortingMethod":"Item","perWhseDoc":true'));

        Helper.AssertSuccess(ResponseJson);
        Assert.AreEqual(1, Helper.IntegerValue(ResponseJson, 'activityCount'), Helper.ResponseText(ResponseJson));
        ActivityJson := Helper.ItemAt(Helper.ArrayValue(ResponseJson, 'activities'), 0);
        Assert.AreEqual('Pick', Helper.TextValue(ActivityJson, 'activityType'), 'Activity type.');
        Assert.IsTrue(ActivityHeader.Get(ActivityHeader.Type::Pick, CopyStr(Helper.TextValue(ActivityJson, 'activityNo'), 1, 20)), 'The pick exists.');
        Assert.AreEqual(0, Helper.ArrayValue(ResponseJson, 'skipped').Count(), 'Nothing is skipped.');
        WorksheetLine.SetRange("Worksheet Template Name", WorksheetName."Worksheet Template Name");
        WorksheetLine.SetRange(Name, WorksheetName.Name);
        WorksheetLine.SetRange("Location Code", Location.Code);
        Assert.IsTrue(WorksheetLine.IsEmpty(), 'The handled worksheet line is gone.');
    end;

    /// <summary>AC02: the put-away worksheet creates a put-away.</summary>
    [Test]
    procedure CreateActivities_PutAwayWorksheet_CreatesPutAway()
    var
        Location: Record Location;
        WorksheetName: Record "Whse. Worksheet Name";
        PostedReceiptHeader: Record "Posted Whse. Receipt Header";
        ActivityHeader: Record "Warehouse Activity Header";
        ResponseJson: JsonObject;
        ActivityJson: JsonObject;
    begin
        Helper.CreatePostedReceipt(Location, PostedReceiptHeader, 4);
        Helper.CreateWorksheetName(Enum::"Warehouse Worksheet Template Type"::"Put-away", Location.Code, WorksheetName);
        GetDocuments('putAway', WorksheetName);

        ResponseJson := Send(Helper.WorksheetRequest('putAway', WorksheetName, ''));

        Helper.AssertSuccess(ResponseJson);
        Assert.AreEqual(1, Helper.IntegerValue(ResponseJson, 'activityCount'), Helper.ResponseText(ResponseJson));
        ActivityJson := Helper.ItemAt(Helper.ArrayValue(ResponseJson, 'activities'), 0);
        Assert.AreEqual('Put-away', Helper.TextValue(ActivityJson, 'activityType'), 'Activity type.');
        Assert.IsTrue(ActivityHeader.Get(ActivityHeader.Type::"Put-away", CopyStr(Helper.TextValue(ActivityJson, 'activityNo'), 1, 20)), 'The put-away exists.');
    end;

    /// <summary>AC06: a line with quantity to handle zero stays in the worksheet and is listed under skipped.</summary>
    [Test]
    procedure CreateActivities_ZeroQtyLine_IsSkipped()
    var
        Location: Record Location;
        Item: Record Item;
        WorksheetName: Record "Whse. Worksheet Name";
        ShipmentHeader: Record "Warehouse Shipment Header";
        SecondShipment: Record "Warehouse Shipment Header";
        WorksheetLine: Record "Whse. Worksheet Line";
        ResponseJson: JsonObject;
        SkippedJson: JsonObject;
    begin
        Helper.CreateReleasedShipment(Location, ShipmentHeader, 3);
        WorksheetLine.SetRange("Location Code", Location.Code);
        Item.Get(FindShipmentItem(ShipmentHeader."No."));
        Helper.AddReleasedShipment(Location.Code, Item."No.", 2, SecondShipment);
        Helper.CreateWorksheetName(Enum::"Warehouse Worksheet Template Type"::Pick, Location.Code, WorksheetName);
        GetDocuments('pick', WorksheetName);
        WorksheetLine.SetRange("Worksheet Template Name", WorksheetName."Worksheet Template Name");
        WorksheetLine.SetRange(Name, WorksheetName.Name);
        WorksheetLine.SetRange("Whse. Document No.", SecondShipment."No.");
        WorksheetLine.FindFirst();

        ResponseJson := Send(Helper.WorksheetRequest('pick', WorksheetName, ',"lines":[{"lineNo":' + Format(WorksheetLine."Line No.", 0, 9) + ',"qtyToHandle":0}]'));

        Helper.AssertSuccess(ResponseJson);
        Assert.AreEqual(1, Helper.IntegerValue(ResponseJson, 'activityCount'), Helper.ResponseText(ResponseJson));
        Assert.AreEqual(1, Helper.ArrayValue(ResponseJson, 'skipped').Count(), 'One line is skipped.');
        SkippedJson := Helper.ItemAt(Helper.ArrayValue(ResponseJson, 'skipped'), 0);
        Assert.AreEqual(WorksheetLine."Line No.", Helper.IntegerValue(SkippedJson, 'lineNo'), 'The zero line is skipped.');
        Assert.AreEqual(1, Helper.IntegerValue(ResponseJson, 'remainingLineCount'), 'The skipped line stays in the worksheet.');
        Assert.IsTrue(WorksheetLine.Get(WorksheetLine."Worksheet Template Name", WorksheetLine.Name, WorksheetLine."Location Code", WorksheetLine."Line No."), 'The skipped line still exists.');
    end;

    /// <summary>Edge: no line with quantity to handle is PreconditionFailed and nothing is created.</summary>
    [Test]
    procedure CreateActivities_NothingToHandle_PreconditionFailed()
    var
        Location: Record Location;
        WorksheetName: Record "Whse. Worksheet Name";
        ShipmentHeader: Record "Warehouse Shipment Header";
        WorksheetLine: Record "Whse. Worksheet Line";
    begin
        Helper.CreateReleasedShipment(Location, ShipmentHeader, 5);
        Helper.CreateWorksheetName(Enum::"Warehouse Worksheet Template Type"::Pick, Location.Code, WorksheetName);
        GetDocuments('pick', WorksheetName);
        WorksheetLine.SetRange("Worksheet Template Name", WorksheetName."Worksheet Template Name");
        WorksheetLine.SetRange(Name, WorksheetName.Name);
        WorksheetLine.FindFirst();

        Helper.ExpectError(Send(Helper.WorksheetRequest('pick', WorksheetName, ',"lines":[{"lineNo":' + Format(WorksheetLine."Line No.", 0, 9) + ',"qtyToHandle":0}]')), 'PreconditionFailed', 'Send qtyToHandle above zero on at least one line.');
        WorksheetLine.Get(WorksheetLine."Worksheet Template Name", WorksheetLine.Name, WorksheetLine."Location Code", WorksheetLine."Line No.");
        Assert.AreEqual(5, WorksheetLine."Qty. to Handle", 'The quantity to handle is not written.');
    end;

    /// <summary>AC03: a location without pick is refused with the inventory activities next step.</summary>
    [Test]
    procedure CreateActivities_LocationWithoutPick_PreconditionFailed()
    var
        Location: Record Location;
    begin
        Helper.CreateBasicLocation(Location);

        Helper.ExpectError(Send('{"worksheetType":"pick","worksheetTemplateName":"PICK","worksheetName":"DEFAULT","locationCode":"' + Location.Code + '"}'), 'PreconditionFailed', 'Use the inventory activities instead.');
    end;

    /// <summary>AC04 and AC05: unknown worksheet, quantity above outstanding, unknown line, grouping on put-away, bad sorting and unknown keys.</summary>
    [Test]
    procedure CreateActivities_Refusals_AnswerCodesWithNextStep()
    var
        Location: Record Location;
        WorksheetName: Record "Whse. Worksheet Name";
        ShipmentHeader: Record "Warehouse Shipment Header";
        WorksheetLine: Record "Whse. Worksheet Line";
        PutLocation: Record Location;
        PutWorksheetName: Record "Whse. Worksheet Name";
        PostedReceiptHeader: Record "Posted Whse. Receipt Header";
        LineText: Text;
    begin
        Helper.CreateReleasedShipment(Location, ShipmentHeader, 5);
        Helper.CreateWorksheetName(Enum::"Warehouse Worksheet Template Type"::Pick, Location.Code, WorksheetName);
        GetDocuments('pick', WorksheetName);
        WorksheetLine.SetRange("Worksheet Template Name", WorksheetName."Worksheet Template Name");
        WorksheetLine.SetRange(Name, WorksheetName.Name);
        WorksheetLine.FindFirst();
        LineText := Format(WorksheetLine."Line No.", 0, 9);
        Helper.CreatePostedReceipt(PutLocation, PostedReceiptHeader, 2);
        Helper.CreateWorksheetName(Enum::"Warehouse Worksheet Template Type"::"Put-away", PutLocation.Code, PutWorksheetName);

        Helper.ExpectError(Send('{"worksheetType":"pick","worksheetTemplateName":"' + WorksheetName."Worksheet Template Name" + '","worksheetName":"NONAME","locationCode":"' + Location.Code + '"}'), 'RecordNotFound', 'Create the worksheet name first.');
        Helper.ExpectError(Send(Helper.WorksheetRequest('pick', WorksheetName, ',"lines":[{"lineNo":' + LineText + ',"qtyToHandle":9}]')), 'InvalidParameter', 'Send a quantity from zero up to the outstanding quantity.');
        Helper.ExpectError(Send(Helper.WorksheetRequest('pick', WorksheetName, ',"lines":[{"lineNo":999999,"qtyToHandle":1}]')), 'RecordNotFound', 'Use the line numbers answered by Warehouse.Worksheet.GetDocuments.');
        Helper.ExpectError(Send(Helper.WorksheetRequest('putAway', PutWorksheetName, ',"perItem":true')), 'InvalidParameter', 'Remove the grouping option, or use a pick worksheet.');
        Helper.ExpectError(Send(Helper.WorksheetRequest('pick', WorksheetName, ',"sortingMethod":"Colour"')), 'InvalidParameter', 'Send one of "None", "Item", "Document", "Shelf or Bin", "Due Date", "Ship-To", "Bin Ranking" or "Action Type".');
        ContractAssert.AssertAnswerDeclared(Enum::"Message Type ori"::"Warehouse.Worksheet.CreateActivities", Send(Helper.WorksheetRequest('pick', WorksheetName, ',"sortingMethod":"Colour"')));
        Helper.ExpectError(Helper.RunTypeInLanguage(Enum::"Message Type ori"::"Warehouse.Worksheet.CreateActivities", '', Helper.WorksheetRequest('pick', WorksheetName, ',"sortingMethod":"Colour"'), 1039), 'InvalidParameter', 'Sendu eitt af "None", "Item", "Document", "Shelf or Bin", "Due Date", "Ship-To", "Bin Ranking" eða "Action Type".');
        Helper.ExpectError(Send(Helper.WorksheetRequest('pick', WorksheetName, ',"assignedUserId":"NOBODY-HERE"')), 'InvalidParameter', 'Send a warehouse employee of the location, or omit assignedUserId.');
        Helper.ExpectError(Send(Helper.WorksheetRequest('pick', WorksheetName, ',"perItem":"yes"')), 'InvalidParameterFormat', '');
        Helper.ExpectError(Send(Helper.WorksheetRequest('pick', WorksheetName, ',"wave":true')), 'UnknownParameter', '');
        Helper.ExpectError(Send(Helper.WorksheetRequest('pick', WorksheetName, ',"lines":[{"qtyToHandle":1}]')), 'MissingParameter', 'Send lineNo and qtyToHandle on every line.');
    end;

    /// <summary>AC07: without worksheet and activity write permission the type is disabled and answers PermissionDenied.</summary>
    [Test]
    [TestPermissions(TestPermissions::Restrictive)]
    procedure CreateActivities_WithoutPermission_ReturnsPermissionDenied()
    var
        TempArgument: Record "Message Argument ori" temporary;
        CreateImpl: Codeunit "Whse Wksh CreateAct Impl ori";
        LibraryLowerPermissions: Codeunit "Library - Lower Permissions";
        MessageTypeInterface: Interface "Msg Interface ori";
    begin
        LibraryLowerPermissions.PushPermissionSetWithoutDefaults('Whse NoRead Test ori');
        MessageTypeInterface := Enum::"Message Type ori"::"Warehouse.Worksheet.CreateActivities";
        Assert.IsFalse(MessageTypeInterface.IsEnabled(), 'CreateActivities must be disabled without write permission.');
        TempArgument.Init();
        TempArgument.Version := "Message Version ori"::"1.0";
        TempArgument.Insert(true);
        CreateImpl.ExecuteBifrostTask(TempArgument);
        Helper.ExpectError(TempArgument.GetResponseJson(), 'PermissionDenied', 'Ask an administrator to assign BIFROST Whse - Full ori.');
    end;

    local procedure GetDocuments(WorksheetType: Text; WorksheetName: Record "Whse. Worksheet Name")
    var
        ResponseJson: JsonObject;
    begin
        ResponseJson := Helper.RunType(Enum::"Message Type ori"::"Warehouse.Worksheet.GetDocuments", '', Helper.WorksheetRequest(WorksheetType, WorksheetName, ''));
        Helper.AssertSuccess(ResponseJson);
        Assert.IsTrue(Helper.IntegerValue(ResponseJson, 'lineCount') > 0, Helper.ResponseText(ResponseJson));
    end;

    local procedure FindShipmentItem(ShipmentNo: Code[20]): Code[20]
    var
        ShipmentLine: Record "Warehouse Shipment Line";
    begin
        ShipmentLine.SetRange("No.", ShipmentNo);
        ShipmentLine.FindFirst();
        exit(ShipmentLine."Item No.");
    end;

    local procedure Send(RequestText: Text): JsonObject
    begin
        exit(Helper.RunType(Enum::"Message Type ori"::"Warehouse.Worksheet.CreateActivities", '', RequestText));
    end;
}
